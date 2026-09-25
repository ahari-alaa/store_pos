const { pool } = require('../config/db');

async function findByEmail(email) {
  const [rows] = await pool.query('SELECT * FROM users WHERE email = ? LIMIT 1', [email]);
  return rows[0] || null;
}

async function findById(id) {
  const [rows] = await pool.query('SELECT * FROM users WHERE id = ? LIMIT 1', [id]);
  return rows[0] || null;
}

/**
 * PIN login (see authService.js#loginWithPin): looks a user up by the
 * deterministic PIN lookup hash instead of an email/username the cashier
 * would otherwise have to select. `pin_hash` has a UNIQUE key (see
 * migrations/010_pin_authentication.sql) so this can never match more
 * than one row.
 */
async function findByPinHash(pinHash) {
  const [rows] = await pool.query('SELECT * FROM users WHERE pin_hash = ? LIMIT 1', [pinHash]);
  return rows[0] || null;
}

async function create({ id, storeId, name, email, passwordHash, role }) {
  await pool.query(
    `INSERT INTO users (id, store_id, name, email, password_hash, role, is_active)
     VALUES (?, ?, ?, ?, ?, ?, 1)`,
    [id, storeId, name, email, passwordHash, role]
  );
  return findById(id);
}

/**
 * Store-scoped lookup — same "never trust an ID alone" rule as every other
 * repository (see productRepository), so an admin from Store A can never
 * read/edit a cashier belonging to Store B.
 */
async function findByIdForStore(storeId, id) {
  const [rows] = await pool.query('SELECT * FROM users WHERE id = ? AND store_id = ? LIMIT 1', [
    id,
    storeId,
  ]);
  return rows[0] || null;
}

async function listByStore(storeId, { search, role, isActive, page, pageSize }) {
  const where = ['store_id = ?'];
  const params = [storeId];

  if (search) {
    where.push('(name LIKE ? OR email LIKE ?)');
    params.push(`%${search}%`, `%${search}%`);
  }
  if (role) {
    where.push('role = ?');
    params.push(role);
  }
  if (typeof isActive === 'boolean') {
    where.push('is_active = ?');
    params.push(isActive ? 1 : 0);
  }

  const whereSql = where.join(' AND ');
  const offset = (page - 1) * pageSize;

  const [rows] = await pool.query(
    `SELECT * FROM users WHERE ${whereSql} ORDER BY name ASC LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  );
  const [countRows] = await pool.query(
    `SELECT COUNT(*) AS total FROM users WHERE ${whereSql}`,
    params
  );

  return { items: rows, total: countRows[0].total, page, pageSize };
}

async function updateForStore(storeId, id, fields) {
  const columns = [];
  const params = [];
  for (const [key, value] of Object.entries(fields)) {
    columns.push(`${key} = ?`);
    params.push(value);
  }
  if (columns.length === 0) return findByIdForStore(storeId, id);

  params.push(id, storeId);
  const [result] = await pool.query(
    `UPDATE users SET ${columns.join(', ')} WHERE id = ? AND store_id = ?`,
    params
  );
  if (result.affectedRows === 0) return null;
  return findByIdForStore(storeId, id);
}

module.exports = {
  findByEmail,
  findById,
  findByPinHash,
  create,
  findByIdForStore,
  listByStore,
  updateForStore,
};
