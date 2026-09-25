const { pool } = require('../config/db');

/**
 * Mirrors productRepository's shape: every query is scoped by store_id so
 * a user from Store A can never read/write Store B's suppliers.
 */

async function findById(storeId, id) {
  const [rows] = await pool.query(
    'SELECT * FROM suppliers WHERE id = ? AND store_id = ? LIMIT 1',
    [id, storeId]
  );
  return rows[0] || null;
}

async function list(storeId, { search, isActive, page, pageSize }) {
  const where = ['store_id = ?'];
  const params = [storeId];

  if (search) {
    where.push('(name LIKE ? OR phone LIKE ? OR email LIKE ?)');
    params.push(`%${search}%`, `%${search}%`, `%${search}%`);
  }
  if (typeof isActive === 'boolean') {
    where.push('is_active = ?');
    params.push(isActive ? 1 : 0);
  }

  const whereSql = where.join(' AND ');
  const offset = (page - 1) * pageSize;

  const [rows] = await pool.query(
    `SELECT * FROM suppliers WHERE ${whereSql} ORDER BY name ASC LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  );
  const [countRows] = await pool.query(
    `SELECT COUNT(*) AS total FROM suppliers WHERE ${whereSql}`,
    params
  );

  return { items: rows, total: countRows[0].total, page, pageSize };
}

async function create(storeId, supplier) {
  await pool.query(
    `INSERT INTO suppliers
       (id, store_id, name, contact_name, phone, email, address, notes, is_active)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      supplier.id,
      storeId,
      supplier.name,
      supplier.contact_name || null,
      supplier.phone || null,
      supplier.email || null,
      supplier.address || null,
      supplier.notes || null,
      supplier.is_active ? 1 : 0,
    ]
  );
  return findById(storeId, supplier.id);
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
    `UPDATE suppliers SET ${columns.join(', ')} WHERE id = ? AND store_id = ?`,
    params
  );
  if (result.affectedRows === 0) return null;
  return findById(storeId, id);
}

async function softDelete(storeId, id) {
  const [result] = await pool.query(
    'UPDATE suppliers SET is_active = 0 WHERE id = ? AND store_id = ?',
    [id, storeId]
  );
  return result.affectedRows > 0;
}

module.exports = { findById, list, create, update, softDelete };
