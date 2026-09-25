const { pool } = require('../config/db');

async function findByClientOperationId(storeId, clientOperationId) {
  if (!clientOperationId) return null;
  const [rows] = await pool.query(
    'SELECT * FROM inventory_movements WHERE store_id = ? AND client_operation_id = ? LIMIT 1',
    [storeId, clientOperationId]
  );
  return rows[0] || null;
}

async function insertMovement(conn, storeId, movement) {
  await conn.query(
    `INSERT INTO inventory_movements
       (id, store_id, product_id, client_operation_id, quantity_delta, movement_type, reference_id, note)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      movement.id,
      storeId,
      movement.productId,
      movement.clientOperationId || null,
      movement.quantityDelta,
      movement.movementType,
      movement.referenceId || null,
      movement.note || null,
    ]
  );
}

async function listForProduct(storeId, productId, { page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const [rows] = await pool.query(
    `SELECT * FROM inventory_movements
      WHERE store_id = ? AND product_id = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?`,
    [storeId, productId, pageSize, offset]
  );
  return rows;
}

/**
 * Latest movement recorded against a given reference (e.g. an expense
 * id), inside an existing transaction connection. Used by expenseService
 * to reverse a purchase's stock effect when that expense is edited (in a
 * way that changes its inventory impact) or deleted — see spec §14/§10.
 */
async function findLatestForReference(conn, storeId, referenceId) {
  const [rows] = await conn.query(
    `SELECT * FROM inventory_movements
      WHERE store_id = ? AND reference_id = ?
      ORDER BY created_at DESC
      LIMIT 1`,
    [storeId, referenceId]
  );
  return rows[0] || null;
}

async function listForStore(storeId, { page = 1, pageSize = 50 } = {}) {
  const offset = (page - 1) * pageSize;
  const [rows] = await pool.query(
    `SELECT im.*, p.name AS product_name
       FROM inventory_movements im
       JOIN products p ON p.id = im.product_id
      WHERE im.store_id = ?
      ORDER BY im.created_at DESC
      LIMIT ? OFFSET ?`,
    [storeId, pageSize, offset]
  );
  return rows;
}

module.exports = {
  findByClientOperationId,
  insertMovement,
  listForProduct,
  listForStore,
  findLatestForReference,
};
