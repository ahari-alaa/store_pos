const { pool } = require('../config/db');

async function findByClientOperationId(conn, storeId, clientOperationId) {
  const [rows] = await conn.query(
    'SELECT * FROM sales WHERE store_id = ? AND client_operation_id = ? LIMIT 1',
    [storeId, clientOperationId]
  );
  return rows[0] || null;
}

async function insertSale(conn, storeId, sale) {
  await conn.query(
    `INSERT INTO sales
       (id, store_id, user_id, client_operation_id, subtotal, discount_total, tax_total,
        total, payment_status, sale_status, note, occurred_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      sale.id,
      storeId,
      sale.userId,
      sale.clientOperationId,
      sale.subtotal,
      sale.discountTotal,
      sale.taxTotal,
      sale.total,
      sale.paymentStatus,
      sale.saleStatus,
      sale.note || null,
      sale.occurredAt,
    ]
  );
}

async function insertSaleItems(conn, saleId, items) {
  if (items.length === 0) return;
  const values = [];
  const params = [];
  for (const item of items) {
    values.push('(?, ?, ?, ?, ?, ?)');
    params.push(item.id, saleId, item.productId, item.quantity, item.unitPrice, item.subtotal);
  }
  await conn.query(
    `INSERT INTO sale_items (id, sale_id, product_id, quantity, unit_price, subtotal)
     VALUES ${values.join(', ')}`,
    params
  );
}

// Cashier name is joined in from `users` rather than duplicated onto the
// `sales` row — the Sales screen (spec §1/§14: "Cashier: alaa") just needs
// it for display, and `sales.user_id` already carries the relationship.
//
// `payment_method` is derived the same way dashboardRecentSales computes
// it in reportService.js ('MIXED' when more than one distinct method was
// used on the sale, NULL-safe for a sale that hasn't been paid yet) —
// added here so the Rapports "Transactions récentes" table (which reuses
// this same GET /sales list rather than a duplicate endpoint) can show
// the payment method column without a second round trip per row.
const SALE_SELECT = `
  SELECT s.*, u.name AS cashier_name,
         su.name AS served_by_name,
         pu.name AS receipt_printed_by_name,
         csi.settlement_id AS settlement_id, cs.settlement_number AS settlement_number,
         cs.status AS settlement_status,
         (SELECT COUNT(DISTINCT payment_method) FROM payments WHERE sale_id = s.id) AS payment_method_count,
         (SELECT payment_method FROM payments WHERE sale_id = s.id ORDER BY created_at DESC LIMIT 1) AS last_payment_method
  FROM sales s
  LEFT JOIN users u ON u.id = s.user_id
  LEFT JOIN users su ON su.id = s.served_by
  LEFT JOIN users pu ON pu.id = s.receipt_printed_by
  LEFT JOIN cashier_settlement_items csi ON csi.sale_id = s.id
  LEFT JOIN cashier_settlements cs ON cs.id = csi.settlement_id
`;

async function findById(storeId, id) {
  const [sales] = await pool.query(`${SALE_SELECT} WHERE s.id = ? AND s.store_id = ? LIMIT 1`, [
    id,
    storeId,
  ]);
  const sale = sales[0];
  if (!sale) return null;

  // Product name is joined in the same way (not duplicated onto
  // sale_items) so the receipt/Sale-details view can show it even if the
  // product is later renamed or deactivated.
  const [items] = await pool.query(
    `SELECT si.*, p.name AS product_name
     FROM sale_items si
     LEFT JOIN products p ON p.id = si.product_id
     WHERE si.sale_id = ?`,
    [id]
  );
  const [payments] = await pool.query('SELECT * FROM payments WHERE sale_id = ? ORDER BY created_at ASC', [id]);
  const { payment_method_count: methodCount, last_payment_method: lastMethod, ...saleFields } = sale;
  return {
    ...saleFields,
    payment_method: Number(methodCount) > 1 ? 'MIXED' : lastMethod,
    items,
    payments,
  };
}

async function list(storeId, { from, to, userId, search, paymentStatus, page, pageSize }) {
  const where = ['s.store_id = ?'];
  const params = [storeId];

  if (from) {
    where.push('s.occurred_at >= ?');
    params.push(from);
  }
  if (to) {
    where.push('s.occurred_at <= ?');
    params.push(to);
  }
  if (userId) {
    where.push('s.user_id = ?');
    params.push(userId);
  }
  if (paymentStatus) {
    where.push('s.payment_status = ?');
    params.push(paymentStatus);
  }
  // Sales-screen search (spec §15): matches the receipt number (sale id),
  // the cashier's name, or the sale note — a single free-text box covering
  // every field the spec asks for that this schema actually has (there is
  // no separate "customer" entity in this app to search by).
  if (search && search.trim()) {
    where.push('(s.id LIKE ? OR u.name LIKE ? OR s.note LIKE ?)');
    const like = `%${search.trim()}%`;
    params.push(like, like, like);
  }

  const whereSql = where.join(' AND ');
  const offset = (page - 1) * pageSize;

  const [rows] = await pool.query(
    `${SALE_SELECT} WHERE ${whereSql} ORDER BY s.occurred_at DESC LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  );
  const [countRows] = await pool.query(
    `SELECT COUNT(*) AS total FROM sales s LEFT JOIN users u ON u.id = s.user_id WHERE ${whereSql}`,
    params
  );

  // Collapse the two payment_method_count/last_payment_method helper
  // columns from SALE_SELECT into one clean `payment_method` field
  // ('MIXED' for more than one distinct method, null for an unpaid sale)
  // — same convention as reportService.dashboardRecentSales, so the
  // Rapports "Transactions récentes" table (which reuses this endpoint)
  // gets a ready-to-display value instead of raw helper columns.
  const items = rows.map((row) => {
    const { payment_method_count: methodCount, last_payment_method: lastMethod, ...rest } = row;
    return {
      ...rest,
      payment_method: Number(methodCount) > 1 ? 'MIXED' : lastMethod,
    };
  });

  return { items, total: countRows[0].total, page, pageSize };
}

// Shared by cashierSalesSummary/cashierSalesByDay: the amount actually
// applied toward each sale's total (never more than the total), matching
// Sale.appliedAmount on the Flutter side (sales/domain/entities/sale.dart)
// so the backend report and the client's own per-sale math always agree.
// Computed once per sale_id via a derived table rather than joining
// `payments` directly, so a sale with N payment rows isn't double-counted
// by the outer GROUP BY.
const PAID_AMOUNT_JOIN = `
  LEFT JOIN (
    SELECT sale_id, SUM(amount) AS paid_amount
    FROM payments
    GROUP BY sale_id
  ) pay ON pay.sale_id = s.id
`;

// Per-sale item quantity, pre-aggregated to one row per sale_id before
// joining — SUMming this in the outer aggregate (or per DATE(...) group
// in cashierSalesByDay) is safe from the fan-out that joining `sale_items`
// directly onto `sales` would cause (a sale with 3 line items would
// otherwise triple-count that sale in COUNT(*)/total_sales).
const ITEMS_JOIN = `
  LEFT JOIN (
    SELECT sale_id, SUM(quantity) AS items_sold
    FROM sale_items
    GROUP BY sale_id
  ) items ON items.sale_id = s.id
`;

const CASHIER_REPORT_AGGREGATES = `
    COUNT(*) AS order_count,
    COALESCE(SUM(LEAST(COALESCE(pay.paid_amount, 0), s.total)), 0) AS total_sales,
    COALESCE(SUM(items.items_sold), 0) AS items_sold,
    SUM(CASE WHEN s.payment_status = 'PAID' THEN 1 ELSE 0 END) AS paid_count,
    SUM(CASE WHEN s.payment_status = 'PENDING' THEN 1 ELSE 0 END) AS not_paid_count,
    SUM(CASE WHEN s.payment_status = 'PARTIALLY_PAID' THEN 1 ELSE 0 END) AS partially_paid_count
`;

/**
 * One cashier's aggregate stats over [from, to] — used for both the Day
 * report (from/to spanning a single day) and the Month report's top
 * summary cards. All aggregation happens in SQL (COUNT/SUM/LEAST on the
 * DECIMAL `total`/`amount` columns) so Flutter never has to download every
 * sale row just to add them up (spec section 10).
 */
async function cashierSalesSummary(storeId, userId, from, to) {
  const [[row]] = await pool.query(
    `SELECT ${CASHIER_REPORT_AGGREGATES}
       FROM sales s
       ${PAID_AMOUNT_JOIN}
       ${ITEMS_JOIN}
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ?`,
    [storeId, userId, from, to]
  );
  return row;
}

/**
 * Same aggregates as [cashierSalesSummary], grouped by calendar day — the
 * Month report's daily breakdown table. `DATE(s.occurred_at)` is computed
 * from the same `occurred_at` value the Day report and the rest of the
 * app already treat as the sale's business date (spec section 15), so a
 * sale never lands on a different day here than it would in the Day view.
 */
async function cashierSalesByDay(storeId, userId, from, to) {
  const [rows] = await pool.query(
    `SELECT DATE(s.occurred_at) AS day, ${CASHIER_REPORT_AGGREGATES}
       FROM sales s
       ${PAID_AMOUNT_JOIN}
       ${ITEMS_JOIN}
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ?
      GROUP BY DATE(s.occurred_at)
      ORDER BY day ASC`,
    [storeId, userId, from, to]
  );
  return rows;
}

/**
 * Payment method breakdown for one cashier over [from, to] — backs the
 * Rapports cashier-detail drill-down's "Payment breakdown" section (spec
 * §11). Same shape/aggregation style as the store-wide equivalent
 * reportService.salesSummary computes for the whole store; kept as its
 * own repository function (rather than an inline query in reportService)
 * so it's mockable the same way cashierSalesSummary/cashierSalesByDay
 * already are.
 */
async function cashierPaymentBreakdown(storeId, userId, from, to) {
  const [rows] = await pool.query(
    `SELECT p.payment_method, COUNT(*) AS tx_count, COALESCE(SUM(p.amount), 0) AS amount
       FROM payments p
       JOIN sales s ON s.id = p.sale_id
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ?
      GROUP BY p.payment_method
      ORDER BY amount DESC`,
    [storeId, userId, from, to]
  );
  return rows;
}

async function findByIdForUpdate(conn, storeId, id) {
  const [rows] = await conn.query('SELECT * FROM sales WHERE id = ? AND store_id = ? FOR UPDATE', [
    id,
    storeId,
  ]);
  return rows[0] || null;
}

async function updatePaymentStatus(conn, id, paymentStatus) {
  await conn.query('UPDATE sales SET payment_status = ? WHERE id = ?', [paymentStatus, id]);
}

// ---------------------------------------------------------------------
// Serving / reprint (cashier "À servir → Servies" workflow)
//
// NOTHING here deletes or rewrites a sale, its items or its payments: it
// only writes the dedicated serving/printing columns added by migration
// 012. Revenue, sale counts and every report are computed from columns
// this code never touches.
// ---------------------------------------------------------------------

/**
 * Atomically claims an order as served. The `served_at IS NULL` guard is
 * the whole concurrency story: if two cashier clients race, MySQL lets
 * exactly one UPDATE match the row; the other affects 0 rows and the
 * caller reports "already served". `served_at` is therefore written once
 * and never changes afterwards.
 *
 * Only COMPLETED sales owned by `userId` can be claimed (a cashier serves
 * their own orders); the service checks existence/ownership first to give
 * a precise error, and this WHERE clause repeats those conditions so the
 * write itself can never be wider than what was authorised.
 *
 * @returns {Promise<boolean>} true when THIS call served the order.
 */
async function markServed(conn, storeId, saleId, userId, servedAt) {
  const [result] = await conn.query(
    `UPDATE sales
        SET served_at = ?, served_by = ?,
            receipt_printed_at = ?, receipt_printed_by = ?,
            receipt_print_count = receipt_print_count + 1
      WHERE id = ? AND store_id = ? AND user_id = ?
        AND sale_status = 'COMPLETED' AND served_at IS NULL`,
    [servedAt, userId, servedAt, userId, saleId, storeId, userId]
  );
  return result.affectedRows === 1;
}

/**
 * Records that an already-served order's receipt was printed again. Leaves
 * served_at / served_by untouched by construction (they are not in the SET
 * list), and only applies to orders that ARE served.
 */
async function markReprinted(conn, storeId, saleId, userId, printedAt) {
  const [result] = await conn.query(
    `UPDATE sales
        SET receipt_printed_at = ?, receipt_printed_by = ?,
            receipt_print_count = receipt_print_count + 1
      WHERE id = ? AND store_id = ? AND user_id = ? AND served_at IS NOT NULL`,
    [printedAt, userId, saleId, storeId, userId]
  );
  return result.affectedRows === 1;
}

module.exports = {
  markServed,
  markReprinted,
  findByClientOperationId,
  insertSale,
  insertSaleItems,
  findById,
  list,
  cashierSalesSummary,
  cashierSalesByDay,
  cashierPaymentBreakdown,
  findByIdForUpdate,
  updatePaymentStatus,
};
