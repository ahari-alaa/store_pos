const { pool } = require('../config/db');

async function findByOperationId(conn, storeId, operationId) {
  const runner = conn || pool;
  const [rows] = await runner.query(
    'SELECT * FROM sync_operations WHERE store_id = ? AND operation_id = ? LIMIT 1',
    [storeId, operationId]
  );
  return rows[0] || null;
}

async function record(conn, entry) {
  const runner = conn || pool;
  await runner.query(
    `INSERT INTO sync_operations
       (id, operation_id, store_id, user_id, entity_type, entity_id, operation_type, status, error_message)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      entry.id,
      entry.operationId,
      entry.storeId,
      entry.userId || null,
      entry.entityType,
      entry.entityId,
      entry.operationType,
      entry.status,
      entry.errorMessage || null,
    ]
  );
}

async function pendingCountSince(storeId, since) {
  // Informational only — the authoritative pending count lives in the
  // Flutter sync_queue table on-device; this just reports what the server
  // has seen recently, useful for /api/sync/status diagnostics.
  const [rows] = await pool.query(
    `SELECT status, COUNT(*) AS count
       FROM sync_operations
      WHERE store_id = ? AND created_at >= ?
      GROUP BY status`,
    [storeId, since]
  );
  return rows;
}

module.exports = { findByOperationId, record, pendingCountSince };
