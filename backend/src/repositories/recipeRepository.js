const { pool } = require('../config/db');

const LINE_SELECT = `
  SELECT pi.id, pi.product_id, pi.ingredient_id, pi.quantity, pi.unit,
         i.name AS ingredient_name, i.unit AS ingredient_unit,
         i.stock_quantity AS ingredient_stock, i.min_stock AS ingredient_min_stock,
         i.cost_per_unit
    FROM product_ingredients pi
    JOIN ingredients i ON i.id = pi.ingredient_id
`;

/** Full recipe for a product, joined with ingredient name/unit/cost/stock
 * so the "Coût des ingrédients" panel AND the possible-production /
 * supply-availability panel (Modifier le produit → Ingrédients / Recette,
 * Product Detail → Recipe) can both be computed without extra round trips. */
async function listForProduct(storeId, productId) {
  const [rows] = await pool.query(
    `${LINE_SELECT} WHERE pi.store_id = ? AND pi.product_id = ? ORDER BY i.name ASC`,
    [storeId, productId]
  );
  return rows;
}

/** Same shape, usable inside a transaction (sale creation) for consumption. */
async function listForProductTx(conn, storeId, productId) {
  const [rows] = await conn.query(
    `SELECT pi.ingredient_id, pi.quantity, pi.unit, i.name AS ingredient_name, i.unit AS ingredient_unit
       FROM product_ingredients pi
       JOIN ingredients i ON i.id = pi.ingredient_id
      WHERE pi.store_id = ? AND pi.product_id = ?`,
    [storeId, productId]
  );
  return rows;
}

/** Replaces a product's entire recipe with `lines` (array of
 * {ingredient_id, quantity, unit}) in one go — used by the legacy "submit
 * the whole list at once" recipe editor. */
async function replaceForProduct(storeId, productId, lines) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('DELETE FROM product_ingredients WHERE store_id = ? AND product_id = ?', [
      storeId,
      productId,
    ]);
    for (const line of lines) {
      await conn.query(
        `INSERT INTO product_ingredients (id, store_id, product_id, ingredient_id, quantity, unit)
         VALUES (UUID(), ?, ?, ?, ?, ?)`,
        [storeId, productId, line.ingredient_id, line.quantity, line.unit || null]
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
  return listForProduct(storeId, productId);
}

/** Adds ONE supply to a product's recipe ("+ Add supply" dialog). Fails
 * with a duplicate-key error (caught in the service) if that ingredient
 * is already on the recipe — use updateLine to change its quantity. */
async function addLine(storeId, productId, { ingredientId, quantity, unit }) {
  await pool.query(
    `INSERT INTO product_ingredients (id, store_id, product_id, ingredient_id, quantity, unit)
     VALUES (UUID(), ?, ?, ?, ?, ?)`,
    [storeId, productId, ingredientId, quantity, unit || null]
  );
  return listForProduct(storeId, productId);
}

/** Updates the quantity/unit of ONE existing recipe line ("Edit recipe
 * supply" dialog). Returns false if the line doesn't exist. */
async function updateLine(storeId, productId, ingredientId, { quantity, unit }) {
  const [result] = await pool.query(
    `UPDATE product_ingredients SET quantity = ?, unit = ?
      WHERE store_id = ? AND product_id = ? AND ingredient_id = ?`,
    [quantity, unit || null, storeId, productId, ingredientId]
  );
  return result.affectedRows > 0;
}

async function removeLine(storeId, productId, ingredientId) {
  const [result] = await pool.query(
    'DELETE FROM product_ingredients WHERE store_id = ? AND product_id = ? AND ingredient_id = ?',
    [storeId, productId, ingredientId]
  );
  return result.affectedRows > 0;
}

/** Every product currently using a given ingredient, with its
 * quantity/unit — powers the "Used in" list on the Supply Detail screen
 * (spec §23). */
async function listProductsUsingIngredient(storeId, ingredientId) {
  const [rows] = await pool.query(
    `SELECT pi.product_id, pi.quantity, pi.unit, p.name AS product_name
       FROM product_ingredients pi
       JOIN products p ON p.id = pi.product_id
      WHERE pi.store_id = ? AND pi.ingredient_id = ?
      ORDER BY p.name ASC`,
    [storeId, ingredientId]
  );
  return rows;
}

/**
 * Removes EVERY recipe line that references `ingredientId`, across every
 * product, inside an existing transaction connection. Used by
 * ingredientService.remove (spec §1/§4): when an ingredient is deleted it
 * must disappear from every product's recipe rather than blocking the
 * delete, and this has to happen in the SAME transaction as the
 * hard-delete/deactivate decision that follows it so the two can never
 * end up inconsistent (recipe lines gone but ingredient still there, or
 * vice versa).
 */
async function deleteAllRecipeLinesForIngredientTx(conn, storeId, ingredientId) {
  const [result] = await conn.query(
    'DELETE FROM product_ingredients WHERE store_id = ? AND ingredient_id = ?',
    [storeId, ingredientId]
  );
  return result.affectedRows;
}

module.exports = {
  listForProduct,
  listForProductTx,
  replaceForProduct,
  addLine,
  updateLine,
  removeLine,
  listProductsUsingIngredient,
  deleteAllRecipeLinesForIngredientTx,
};
