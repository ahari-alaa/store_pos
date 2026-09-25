const mysql = require('mysql2/promise');
const env = require('./env');

const pool = mysql.createPool({
  host: env.db.host,
  port: env.db.port,
  database: env.db.name,
  user: env.db.user,
  password: env.db.password,
  waitForConnections: true,
  connectionLimit: env.db.connectionLimit,
  queueLimit: 0,
  decimalNumbers: false, // keep DECIMAL as string to avoid float rounding on money
  dateStrings: true,
});

/**
 * Run `work(connection)` inside a MySQL transaction.
 * Commits on success, rolls back and rethrows on any error.
 * Always releases the connection back to the pool.
 */
async function withTransaction(work) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await work(conn);
    await conn.commit();
    return result;
  } catch (err) {
    try {
      await conn.rollback();
    } catch (rollbackErr) {
      // rollback failure is secondary to the original error; log and continue
      // eslint-disable-next-line no-console
      console.error('Rollback failed:', rollbackErr);
    }
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = { pool, withTransaction };
