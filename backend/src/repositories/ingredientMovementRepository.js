const { pool } = require('../config/db');

async function insertMovement(conn, storeId, movement) {
  await conn.query(
    `INSERT INTO ingredient_stock_movements
       (id, store_id, ingredient_id, quantity_delta, movement_type, reference_id, note)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      movement.id,
      storeId,
      movement.ingredientId,
      movement.quantityDelta,
      movement.movementType,
      movement.referenceId || null,
      movement.note || null,
    ]
  );
}

async function listForIngredient(storeId, ingredientId, { page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const [rows] = await pool.query(
    `SELECT * FROM ingredient_stock_movements
      WHERE store_id = ? AND ingredient_id = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?`,
    [storeId, ingredientId, pageSize, offset]
  );
  return rows;
}

async function listForStore(storeId, { page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const [rows] = await pool.query(
    `SELECT m.*, i.name AS ingredient_name, i.unit AS ingredient_unit
       FROM ingredient_stock_movements m
       JOIN ingredients i ON i.id = m.ingredient_id
      WHERE m.store_id = ?
      ORDER BY m.created_at DESC
      LIMIT ? OFFSET ?`,
    [storeId, pageSize, offset]
  );
  return rows;
}

/** All consumption rows tied to one sale (Ventes → "Consommation
 * automatique" trail) so the UI can show exactly what a sale used up. */
async function listForReference(storeId, referenceId) {
  const [rows] = await pool.query(
    `SELECT m.*, i.name AS ingredient_name, i.unit AS ingredient_unit
       FROM ingredient_stock_movements m
       JOIN ingredients i ON i.id = m.ingredient_id
      WHERE m.store_id = ? AND m.reference_id = ?
      ORDER BY m.created_at ASC`,
    [storeId, referenceId]
  );
  return rows;
}

/** Latest movement recorded against a given reference (e.g. an expense
 * id), inside an existing transaction connection — the ingredient-side
 * counterpart of inventoryRepository.findLatestForReference, used to
 * reverse a supply purchase's stock effect when the expense is edited or
 * deleted (spec §3/§19). */
async function findLatestForReference(conn, storeId, referenceId) {
  const [rows] = await conn.query(
    `SELECT * FROM ingredient_stock_movements
      WHERE store_id = ? AND reference_id = ?
      ORDER BY created_at DESC
      LIMIT 1`,
    [storeId, referenceId]
  );
  return rows[0] || null;
}

/** Whether this ingredient has ANY stock-movement history at all
 * (purchase, sale consumption, manual adjustment, damage) — used by
 * ingredientService.remove to decide whether a hard DELETE would destroy
 * auditable history, in which case it must be refused in favor of
 * deactivation (is_active = 0). A cheap `LIMIT 1` existence check rather
 * than a full COUNT since the caller only needs a boolean. */
async function hasHistory(storeId, ingredientId) {
  const [rows] = await pool.query(
    `SELECT 1 FROM ingredient_stock_movements WHERE store_id = ? AND ingredient_id = ? LIMIT 1`,
    [storeId, ingredientId]
  );
  return rows.length > 0;
}

/**
 * Transaction-scoped variant of hasHistory — used by ingredientService.remove
 * (spec §3) inside the same transaction as the recipe-line cleanup and the
 * hard/soft delete decision, so the history check is consistent with
 * whatever else that transaction is doing to this ingredient.
 */
async function hasHistoryTx(conn, storeId, ingredientId) {
  const [rows] = await conn.query(
    `SELECT 1 FROM ingredient_stock_movements WHERE store_id = ? AND ingredient_id = ? LIMIT 1`,
    [storeId, ingredientId]
  );
  return rows.length > 0;
}

module.exports = {
  insertMovement,
  listForIngredient,
  listForStore,
  listForReference,
  findLatestForReference,
  hasHistory,
  hasHistoryTx,
};
