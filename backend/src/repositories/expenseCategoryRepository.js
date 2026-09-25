const { pool } = require('../config/db');

/**
 * Configurable expense categories (spec §1) — mirrors productRepository's
 * shape: every query is scoped by store_id.
 */

async function list(storeId, { expenseType, includeInactive = false } = {}) {
  const where = ['store_id = ?'];
  const params = [storeId];
  if (expenseType) {
    where.push('expense_type = ?');
    params.push(expenseType);
  }
  if (!includeInactive) {
    where.push('is_active = 1');
  }
  const [rows] = await pool.query(
    `SELECT * FROM expense_categories WHERE ${where.join(' AND ')} ORDER BY expense_type ASC, name ASC`,
    params
  );
  return rows;
}

async function findById(storeId, id) {
  const [rows] = await pool.query(
    'SELECT * FROM expense_categories WHERE id = ? AND store_id = ? LIMIT 1',
    [id, storeId]
  );
  return rows[0] || null;
}

async function create(storeId, category) {
  await pool.query(
    `INSERT INTO expense_categories (id, store_id, name, expense_type, is_active)
     VALUES (?, ?, ?, ?, ?)`,
    [category.id, storeId, category.name, category.expenseType, category.isActive === false ? 0 : 1]
  );
  return findById(storeId, category.id);
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
    `UPDATE expense_categories SET ${columns.join(', ')} WHERE id = ? AND store_id = ?`,
    params
  );
  if (result.affectedRows === 0) return null;
  return findById(storeId, id);
}

/** Categories are deactivated, never hard-deleted — existing expenses
 * still reference them (category_id ON DELETE SET NULL would silently
 * orphan history on a hard delete). */
async function deactivate(storeId, id) {
  const [result] = await pool.query(
    'UPDATE expense_categories SET is_active = 0 WHERE id = ? AND store_id = ?',
    [id, storeId]
  );
  return result.affectedRows > 0;
}

module.exports = { list, findById, create, update, deactivate };
