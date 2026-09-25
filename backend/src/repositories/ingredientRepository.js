const { pool } = require('../config/db');

async function list(storeId, { search, isActive } = {}) {
  const where = ['store_id = ?'];
  const params = [storeId];

  if (search) {
    where.push('name LIKE ?');
    params.push(`%${search}%`);
  }
  // Default to active-only so soft-deleted ingredients (is_active = 0)
  // disappear from the main list after "Supprimer". Callers that need
  // inactive rows must pass isActive: false explicitly.
  if (typeof isActive === 'boolean') {
    where.push('is_active = ?');
    params.push(isActive ? 1 : 0);
  } else {
    where.push('is_active = 1');
  }

  const [rows] = await pool.query(
    `SELECT * FROM ingredients WHERE ${where.join(' AND ')} ORDER BY name ASC`,
    params
  );
  return rows;
}

async function findById(storeId, id) {
  const [rows] = await pool.query(
    'SELECT * FROM ingredients WHERE id = ? AND store_id = ? LIMIT 1',
    [id, storeId]
  );
  return rows[0] || null;
}

async function findByIdForUpdate(conn, storeId, id) {
  const [rows] = await conn.query(
    'SELECT * FROM ingredients WHERE id = ? AND store_id = ? FOR UPDATE',
    [id, storeId]
  );
  return rows[0] || null;
}

async function create(storeId, ingredient) {
  await pool.query(
    `INSERT INTO ingredients
       (id, store_id, name, unit, stock_quantity, min_stock, cost_per_unit, is_active)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      ingredient.id,
      storeId,
      ingredient.name,
      ingredient.unit,
      ingredient.stock_quantity ?? 0,
      ingredient.min_stock ?? 0,
      ingredient.cost_per_unit ?? 0,
      ingredient.is_active === false ? 0 : 1,
    ]
  );
  return findById(storeId, ingredient.id);
}

const UPDATABLE_FIELDS = ['name', 'unit', 'min_stock', 'cost_per_unit', 'is_active'];

async function update(storeId, id, fields) {
  const sets = [];
  const params = [];
  for (const key of UPDATABLE_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(fields, key)) {
      sets.push(`${key} = ?`);
      params.push(fields[key]);
    }
  }
  if (sets.length === 0) return findById(storeId, id);

  params.push(id, storeId);
  const [result] = await pool.query(
    `UPDATE ingredients SET ${sets.join(', ')} WHERE id = ? AND store_id = ?`,
    params
  );
  if (result.affectedRows === 0) return null;
  return findById(storeId, id);
}

/**
 * Actually removes the row. `product_ingredients.ingredient_id` and
 * `ingredient_stock_movements.ingredient_id` are both `ON DELETE
 * RESTRICT` (see migrations/008_ingredient_delete_integrity.sql), so this
 * throws a MySQL FK error (errno 1451 / ER_ROW_IS_REFERENCED_2) if the
 * ingredient is still used by a recipe or has any stock-movement history.
 * ingredientService.remove is expected to check those cases explicitly
 * BEFORE calling this (so it can return a precise INGREDIENT_IN_USE /
 * INGREDIENT_HAS_HISTORY error with details) — this raw FK error is only
 * a defense-in-depth backstop for a race or a check that was missed.
 */
async function hardDelete(storeId, id) {
  const [result] = await pool.query('DELETE FROM ingredients WHERE id = ? AND store_id = ?', [
    id,
    storeId,
  ]);
  return result.affectedRows > 0;
}

/**
 * Transaction-scoped variant of hardDelete — used by ingredientService.remove
 * (spec §3/§4) so the physical DELETE happens in the SAME transaction as
 * the recipe-line cleanup that must precede it. See hardDelete for the FK
 * behavior this relies on as a backstop.
 */
async function hardDeleteTx(conn, storeId, id) {
  const [result] = await conn.query('DELETE FROM ingredients WHERE id = ? AND store_id = ?', [
    id,
    storeId,
  ]);
  return result.affectedRows > 0;
}

/**
 * Transaction-scoped variant of softDelete — used by ingredientService.remove
 * when the ingredient has historical stock movements or expense references
 * that must be preserved, so is_active is flipped inside the same
 * transaction as the recipe-line cleanup (spec §2/§3).
 */
async function softDeleteTx(conn, storeId, id) {
  const [result] = await conn.query(
    'UPDATE ingredients SET is_active = 0 WHERE id = ? AND store_id = ?',
    [id, storeId]
  );
  return result.affectedRows > 0;
}

/** Soft delete ("Désactiver") — the safe alternative to hardDelete for an
 * ingredient that's in use or has history. Sets is_active = 0 so it:
 *  - disappears from active supply selection / new-recipe pickers
 *  - remains attached to every existing recipe, sale and stock movement
 *  - remains visible in historical reports
 * See spec §13. */
async function softDelete(storeId, id) {
  const [result] = await pool.query(
    'UPDATE ingredients SET is_active = 0 WHERE id = ? AND store_id = ?',
    [id, storeId]
  );
  return result.affectedRows > 0;
}

/**
 * Adjusts stock by `delta` (positive for a restock/purchase, negative for
 * consumption/damage — including automatic recipe consumption on a sale,
 * see ingredientService.consumeForSale). Mirrors productRepository.adjustStock:
 * the WHERE clause blocks the update from ever pushing stock below zero
 * under concurrent writers, returning false instead of throwing so the
 * caller decides how to react to "would go negative" (e.g. rolling back
 * the whole sale transaction).
 */
async function adjustStock(conn, storeId, ingredientId, delta) {
  const [result] = await conn.query(
    `UPDATE ingredients
        SET stock_quantity = stock_quantity + ?
      WHERE id = ? AND store_id = ? AND stock_quantity + ? >= 0`,
    [delta, ingredientId, storeId, delta]
  );
  return result.affectedRows > 0;
}

/**
 * Adjusts stock by `delta`, but CLAMPS the result at zero instead of
 * either failing (like adjustStock) or forcing it below zero (like the
 * old, now-removed forceAdjustStock).
 *
 * This exists specifically to reverse a previous restock safely — e.g.
 * editing or deleting an expense that had added stock (see
 * expenseService.reverseIngredientPurchase). The bug this fixes: the
 * original purchase amount is NOT necessarily still sitting in stock by
 * the time it's reversed — a sale may have consumed some or all of it in
 * the meantime. Blindly subtracting the full original purchase amount
 * (the old forceAdjustStock behavior) could then drive stock negative
 * (this is how a "café" ingredient reached -425 kg: a large purchase was
 * edited/deleted long after sales had already consumed most of it).
 *
 * Takes the same row lock as adjustStock/findByIdForUpdate so concurrent
 * writers can't race between reading `before` and writing `next`. Returns
 * the amount ACTUALLY applied (which may be smaller in magnitude than
 * `delta` if clamping kicked in) so the caller can log an honest movement
 * instead of one that claims a change that didn't fully happen.
 */
async function clampedAdjustStock(conn, storeId, ingredientId, delta) {
  const [rows] = await conn.query(
    'SELECT stock_quantity FROM ingredients WHERE id = ? AND store_id = ? FOR UPDATE',
    [ingredientId, storeId]
  );
  if (rows.length === 0) return { applied: 0, clamped: false };

  const current = Number(rows[0].stock_quantity);
  const desired = current + Number(delta);
  const next = Math.max(0, desired);
  const applied = next - current;

  if (applied !== 0) {
    await conn.query('UPDATE ingredients SET stock_quantity = ? WHERE id = ? AND store_id = ?', [
      next,
      ingredientId,
      storeId,
    ]);
  }
  return { applied, clamped: next !== desired };
}

async function lowStock(storeId) {
  const [rows] = await pool.query(
    `SELECT * FROM ingredients
      WHERE store_id = ? AND is_active = 1 AND stock_quantity <= min_stock
      ORDER BY (stock_quantity - min_stock) ASC`,
    [storeId]
  );
  return rows;
}

module.exports = {
  list,
  findById,
  findByIdForUpdate,
  create,
  update,
  hardDelete,
  softDelete,
  hardDeleteTx,
  softDeleteTx,
  adjustStock,
  clampedAdjustStock,
  lowStock,
};
