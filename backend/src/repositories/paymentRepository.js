async function insertPayments(conn, saleId, userId, payments) {
  if (payments.length === 0) return;
  const values = [];
  const params = [];
  for (const p of payments) {
    values.push('(?, ?, ?, ?, ?, ?)');
    params.push(p.id, saleId, userId, p.clientOperationId || null, p.amount, p.paymentMethod);
  }
  await conn.query(
    `INSERT INTO payments (id, sale_id, user_id, client_operation_id, amount, payment_method)
     VALUES ${values.join(', ')}`,
    params
  );
}

async function findByClientOperationId(conn, saleId, clientOperationId) {
  const [rows] = await conn.query(
    'SELECT * FROM payments WHERE sale_id = ? AND client_operation_id = ? LIMIT 1',
    [saleId, clientOperationId]
  );
  return rows[0] || null;
}

async function sumBySale(conn, saleId) {
  const [rows] = await conn.query(
    'SELECT COALESCE(SUM(amount), 0) AS total_paid FROM payments WHERE sale_id = ?',
    [saleId]
  );
  return Number(rows[0].total_paid);
}

module.exports = { insertPayments, findByClientOperationId, sumBySale };
