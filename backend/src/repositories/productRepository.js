const { pool } = require('../config/db');

/**
 * Every query here takes storeId and filters by it explicitly.
 * This is the enforcement point for section 14 of the spec: a user from
 * Store A can never read/write Store B's products by guessing an ID,
 * because the WHERE clause always includes their own store_id from the
 * JWT — never from client-supplied input.
 */

async function findById(storeId, id) {
  const [rows] = await pool.query('SELECT * FROM products WHERE id = ? AND store_id = ? LIMIT 1', [
    id,
    storeId,
  ]);
  return rows[0] || null;
}

async function list(storeId, { search, category, isActive, page, pageSize, updatedSince }) {
  const where = ['store_id = ?'];
  const params = [storeId];

  if (search) {
    where.push('(name LIKE ? OR barcode = ? OR sku = ?)');
    params.push(`%${search}%`, search, search);
  }
  if (category) {
    where.push('category = ?');
    params.push(category);
  }
  if (typeof isActive === 'boolean') {
    where.push('is_active = ?');
    params.push(isActive ? 1 : 0);
  }
  if (updatedSince) {
    // Incremental pull for offline sync: "give me everything changed since X"
    where.push('updated_at > ?');
    params.push(updatedSince);
  }

  const whereSql = where.join(' AND ');
  const offset = (page - 1) * pageSize;

  const [rows] = await pool.query(
    `SELECT * FROM products WHERE ${whereSql} ORDER BY name ASC LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  );
  const [countRows] = await pool.query(
    `SELECT COUNT(*) AS total FROM products WHERE ${whereSql}`,
    params
  );

  return { items: rows, total: countRows[0].total, page, pageSize };
}

async function create(storeId, product) {
  await pool.query(
    `INSERT INTO products
       (id, store_id, category, image_url, name, barcode, sku, price, cost, tax_rate, stock_quantity, is_active)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      product.id,
      storeId,
      product.category || null,
      product.image_url || null,
      product.name,
      product.barcode || null,
      product.sku || null,
      product.price,
      product.cost,
      product.tax_rate,
      product.stock_quantity,
      product.is_active ? 1 : 0,
    ]
  );
  return findById(storeId, product.id);
}

async function update(storeId, id, fields) {
  const columns = [];
  const params = [];
  for (const [key, value] of Object.entries(fields)) {
    columns.push(`${key} = ?`);
    params.push(value);
  }
  if (columns.length === 0) return findById(storeId, id);

  params.push(id, storeId);
  const [result] = await pool.query(
    `UPDATE products SET ${columns.join(', ')} WHERE id = ? AND store_id = ?`,
    params
  );
  if (result.affectedRows === 0) return null;
  return findById(storeId, id);
}

async function softDelete(storeId, id) {
  const [result] = await pool.query(
    'UPDATE products SET is_active = 0 WHERE id = ? AND store_id = ?',
    [id, storeId]
  );
  return result.affectedRows > 0;
}

/**
 * Actually removes the row. `sale_items.product_id` has an
 * `ON DELETE RESTRICT` FK (see migrations/001_init.sql), so this throws a
 * MySQL FK error (errno 1451 / ER_ROW_IS_REFERENCED_2) if the product has
 * ever appeared in a sale — that's intentional: a sold product can't be
 * hard-deleted without corrupting historical sales/reporting. The caller
 * (productService.remove) catches that specific error and falls back to
 * softDelete so the request still succeeds from the user's point of view.
 */
async function hardDelete(storeId, id) {
  const [result] = await pool.query('DELETE FROM products WHERE id = ? AND store_id = ?', [
    id,
    storeId,
  ]);
  return result.affectedRows > 0;
}

/**
 * Adjusts stock_quantity by delta within an existing transaction connection.
 * Uses a conditional UPDATE so a sale can never push stock negative under
 * concurrent access (see saleService for how the affectedRows check is used
 * to detect and reject an oversell).
 */
async function adjustStock(conn, storeId, productId, delta) {
  const [result] = await conn.query(
    `UPDATE products
        SET stock_quantity = stock_quantity + ?
      WHERE id = ? AND store_id = ? AND stock_quantity + ? >= 0`,
    [delta, productId, storeId, delta]
  );
  return result.affectedRows > 0;
}

async function findByIdForUpdate(conn, storeId, id) {
  const [rows] = await conn.query(
    'SELECT * FROM products WHERE id = ? AND store_id = ? FOR UPDATE',
    [id, storeId]
  );
  return rows[0] || null;
}

/**
 * Adjusts stock_quantity by `delta`, clamping the result at zero instead
 * of failing — the product-stock counterpart of
 * ingredientRepository.clampedAdjustStock, used when REVERSING a previous
 * purchase (editing/deleting an expense) rather than when consuming stock
 * for a sale. A plain `adjustStock` call there silently does nothing if
 * it would go negative (0 affected rows) while the caller went on to log
 * a movement claiming the reversal happened anyway — this makes the
 * actually-applied amount explicit so the movement log stays honest.
 * Returns the amount actually applied (may be smaller in magnitude than
 * `delta` if clamping kicked in).
 */
async function clampedAdjustStock(conn, storeId, productId, delta) {
  const [rows] = await conn.query(
    'SELECT stock_quantity FROM products WHERE id = ? AND store_id = ? FOR UPDATE',
    [productId, storeId]
  );
  if (rows.length === 0) return { applied: 0, clamped: false };

  const current = Number(rows[0].stock_quantity);
  const desired = current + Number(delta);
  const next = Math.max(0, desired);
  const applied = next - current;

  if (applied !== 0) {
    await conn.query('UPDATE products SET stock_quantity = ? WHERE id = ? AND store_id = ?', [
      next,
      productId,
      storeId,
    ]);
  }
  return { applied, clamped: next !== desired };
}

module.exports = {
  findById,
  list,
  create,
  update,
  softDelete,
  hardDelete,
  adjustStock,
  clampedAdjustStock,
  findByIdForUpdate,
};
