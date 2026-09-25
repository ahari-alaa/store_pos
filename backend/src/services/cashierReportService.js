const { pool } = require('../config/db');
const {
  resolveOrThrow,
  withReadSnapshot,
  allocateChange,
  toCents,
  money,
  toInt,
  percent,
  localDateTime,
  inclusiveDays,
} = require('./reportOverviewService');

/**
 * The cashier's PERSONAL report ("Rapport") and order queue.
 *
 * It answers one question — "what did THIS cashier sell?" — and it is built
 * for a single user: every function takes `userId` and every query filters
 * `s.user_id = ?`. Callers pass `req.user.id` (verified JWT). There is no
 * code path that accepts a cashier id from the client, so one cashier can
 * never read another cashier's figures.
 *
 * Counting rules are the ADMIN report's rules (reportOverviewService.js),
 * on purpose, so a store's cashier reports add up to the admin report:
 *   - a "vente"/"commande" = a sales row with sale_status = 'COMPLETED'
 *     whose `occurred_at` falls in the period;
 *   - revenue = SUM(sales.total); encaissé = SUM(LEAST(paid, total));
 *   - product quantities = SUM(sale_items.quantity) of THIS cashier's sales
 *     (never the store-wide quantity).
 *
 * Serving/printing state (served_at, ...) is only ever READ here to split
 * the queue; it never enters a revenue/count/quantity computation, which is
 * why serving an order cannot change any figure below.
 *
 * Nothing in this file writes to the database.
 */

const COMPLETED = "s.sale_status = 'COMPLETED'";
const MAX_PRODUCTS = 500;
// Ceiling for the optional full order list used by the printed report.
const MAX_ORDERS_LIST = 2000;

function receiptNumber(saleId) {
  const id = String(saleId || '');
  return id.length > 8 ? id.substring(0, 8) : id;
}

// ---------------------------------------------------------------------
// Orders (cards): one row per sale + its lines
// ---------------------------------------------------------------------

const ORDER_SELECT = `
  SELECT s.id, s.subtotal, s.discount_total, s.tax_total, s.total,
         s.payment_status, s.sale_status, s.note, s.occurred_at,
         s.served_at, s.served_by, su.name AS served_by_name,
         s.receipt_printed_at, s.receipt_print_count,
         csi.settlement_id AS settlement_id, cs.settlement_number AS settlement_number,
         cs.status AS settlement_status,
         (SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.sale_id = s.id)       AS paid_amount,
         (SELECT COUNT(DISTINCT p.payment_method) FROM payments p WHERE p.sale_id = s.id) AS payment_method_count,
         (SELECT p.payment_method FROM payments p WHERE p.sale_id = s.id
           ORDER BY p.created_at DESC LIMIT 1)                                            AS last_payment_method
    FROM sales s
    LEFT JOIN users su ON su.id = s.served_by
    LEFT JOIN cashier_settlement_items csi ON csi.sale_id = s.id
    LEFT JOIN cashier_settlements cs ON cs.id = csi.settlement_id
`;

function orderRow(r, items) {
  const totalCents = toCents(r.total);
  return {
    id: r.id,
    receipt_number: receiptNumber(r.id),
    occurred_at: String(r.occurred_at),
    subtotal: money(toCents(r.subtotal)),
    discount_total: money(toCents(r.discount_total)),
    tax_total: money(toCents(r.tax_total)),
    total: money(totalCents),
    payment_status: r.payment_status,
    sale_status: r.sale_status,
    note: r.note || null,
    // Applied amount never exceeds the total (change handed back is not revenue).
    paid_amount: money(Math.min(toCents(r.paid_amount), totalCents)),
    payment_method: toInt(r.payment_method_count) > 1 ? 'MIXED' : r.last_payment_method || null,
    is_served: r.served_at != null,
    served_at: r.served_at != null ? String(r.served_at) : null,
    served_by: r.served_by || null,
    served_by_name: r.served_by_name || null,
    receipt_printed_at: r.receipt_printed_at != null ? String(r.receipt_printed_at) : null,
    receipt_print_count: toInt(r.receipt_print_count),
    // Cashier WORK-payment settlement status (spec §2/§9) — completely
    // independent of payment_status above. NOT NULL settlement_id means
    // this order was already used to justify a cashier settlement and can
    // never be selected for another one (see cashierSettlementService).
    settlement_id: r.settlement_id || null,
    settlement_number: r.settlement_number || null,
    settlement_status: r.settlement_status || null,
    items_count: items.reduce((sum, i) => sum + i.quantity, 0),
    items,
  };
}

// Lines of one order are inserted in a single statement (identical
// created_at) and sale_items has no line-number column, so insertion order is
// not recoverable. They are sorted by product name so an order card always
// lists its lines in the same, predictable order.
async function itemsBySale(db, saleIds) {
  const bySale = new Map();
  if (saleIds.length === 0) return bySale;
  const [rows] = await db.query(
    `SELECT si.sale_id, si.product_id, p.name AS product_name,
            si.quantity, si.unit_price, si.subtotal
       FROM sale_items si
       LEFT JOIN products p ON p.id = si.product_id
      WHERE si.sale_id IN (?)
      ORDER BY p.name ASC, si.id ASC`,
    [saleIds]
  );
  for (const r of rows) {
    const list = bySale.get(r.sale_id) || [];
    list.push({
      product_id: r.product_id,
      name: r.product_name || 'Produit',
      quantity: toInt(r.quantity),
      unit_price: money(toCents(r.unit_price)),
      subtotal: money(toCents(r.subtotal)),
    });
    bySale.set(r.sale_id, list);
  }
  return bySale;
}

/**
 * WHERE fragment (+ params) shared by the order list and its count. Always
 * starts with store + THIS cashier + COMPLETED.
 */
function orderFilter(storeId, userId, { range, serveStatus, paymentStatus, search }) {
  const where = ['s.store_id = ?', 's.user_id = ?', COMPLETED];
  const params = [storeId, userId];
  if (range) {
    where.push('s.occurred_at BETWEEN ? AND ?');
    params.push(range.start, range.end);
  }
  if (serveStatus === 'to_serve') where.push('s.served_at IS NULL');
  if (serveStatus === 'served') where.push('s.served_at IS NOT NULL');
  if (paymentStatus === 'UNPAID') {
    where.push("s.payment_status IN ('PENDING', 'PARTIALLY_PAID')");
  } else if (paymentStatus) {
    where.push('s.payment_status = ?');
    params.push(paymentStatus);
  }
  if (search && String(search).trim()) {
    where.push('s.id LIKE ?');
    params.push(`${String(search).trim()}%`);
  }
  return { whereSql: where.join(' AND '), params };
}

/**
 * GET /reports/my-orders — this cashier's orders with their lines, split by
 * serving state. `to_serve` is the operational queue (oldest first, so
 * orders are served in the order they were taken); everything else is
 * newest first. `period` is optional: omitted = no date bound, which is what
 * the "À servir" queue wants (an unserved order from yesterday must not
 * vanish from the queue just because the day changed).
 */
async function myOrders(storeId, userId, opts = {}) {
  const { period, from, to, serveStatus = 'all', paymentStatus, search } = opts;
  const page = opts.page || 1;
  const pageSize = opts.pageSize || 50;
  const range = period || from || to ? resolveOrThrow(period, from, to) : null;

  const { whereSql, params } = orderFilter(storeId, userId, {
    range,
    serveStatus,
    paymentStatus,
    search,
  });
  const direction = serveStatus === 'to_serve' ? 'ASC' : 'DESC';

  const [rows] = await pool.query(
    `${ORDER_SELECT}
      WHERE ${whereSql}
      ORDER BY s.occurred_at ${direction}, s.created_at ${direction}
      LIMIT ? OFFSET ?`,
    [...params, pageSize, (page - 1) * pageSize]
  );
  const [[countRow]] = await pool.query(
    `SELECT COUNT(*) AS total FROM sales s WHERE ${whereSql}`,
    params
  );
  const items = await itemsBySale(
    pool,
    rows.map((r) => r.id)
  );

  return {
    items: rows.map((r) => orderRow(r, items.get(r.id) || [])),
    total: toInt(countRow.total),
    page,
    pageSize,
  };
}

// ---------------------------------------------------------------------
// Personal report
// ---------------------------------------------------------------------

async function payments(db, storeId, userId, range) {
  const { start, end } = range;
  const [methodRows] = await db.query(
    `SELECT p.payment_method AS method, COUNT(*) AS tx_count, COALESCE(SUM(p.amount), 0) AS amount
       FROM payments p
       JOIN sales s ON s.id = p.sale_id
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ? AND ${COMPLETED}
      GROUP BY p.payment_method
      ORDER BY amount DESC`,
    [storeId, userId, start, end]
  );

  // Per-sale paid amount in a derived table so a sale with N payment rows is
  // never counted N times (same technique as the admin report).
  const [[settle]] = await db.query(
    `SELECT COALESCE(SUM(LEAST(x.paid, x.total)), 0)                                      AS collected,
            COALESCE(SUM(x.total - LEAST(x.paid, x.total)), 0)                            AS outstanding,
            COALESCE(SUM(GREATEST(x.paid - x.total, 0)), 0)                               AS change_given,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PENDING' THEN 1 ELSE 0 END), 0)    AS unpaid_count,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PENDING'
                              THEN x.total - LEAST(x.paid, x.total) ELSE 0 END), 0)       AS unpaid_amount,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PARTIALLY_PAID' THEN 1 ELSE 0 END), 0) AS partial_count,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PARTIALLY_PAID'
                              THEN x.total - LEAST(x.paid, x.total) ELSE 0 END), 0)       AS partial_remaining
       FROM (
         SELECT s.total, s.payment_status,
                (SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.sale_id = s.id) AS paid
           FROM sales s
          WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ? AND ${COMPLETED}
       ) x`,
    [storeId, userId, start, end]
  );

  const methods = methodRows.map((r) => ({
    method: String(r.method),
    count: toInt(r.tx_count),
    rawCents: toCents(r.amount),
    netCents: toCents(r.amount),
  }));
  allocateChange(methods, toCents(settle.change_given));
  const totalNet = methods.reduce((sum, m) => sum + m.netCents, 0);

  return {
    methods: methods.map((m) => ({
      method: m.method,
      amount: money(m.netCents),
      count: m.count,
      percent: percent(m.netCents, totalNet),
    })),
    total_collected: money(totalNet),
    change_given: money(toCents(settle.change_given)),
    outstanding: money(toCents(settle.outstanding)),
    unpaid: { count: toInt(settle.unpaid_count), amount: money(toCents(settle.unpaid_amount)) },
    partial: {
      count: toInt(settle.partial_count),
      remaining: money(toCents(settle.partial_remaining)),
    },
    _collected_cents: toCents(settle.collected),
  };
}

async function productsSold(db, storeId, userId, range) {
  // Quantities are summed over THIS cashier's sales only (s.user_id = ?).
  const [rows] = await db.query(
    `SELECT si.product_id, p.name,
            SUM(si.quantity)              AS quantity,
            COALESCE(SUM(si.subtotal), 0) AS revenue
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
       JOIN products p ON p.id = si.product_id
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ? AND ${COMPLETED}
      GROUP BY si.product_id, p.name
      ORDER BY quantity DESC, revenue DESC, p.name ASC
      LIMIT ?`,
    [storeId, userId, range.start, range.end, MAX_PRODUCTS]
  );
  return rows.map((r) => ({
    product_id: String(r.product_id),
    name: r.name,
    quantity: toInt(r.quantity),
    revenue: money(toCents(r.revenue)),
  }));
}

async function buildMyReport(db, storeId, user, range, options = {}) {
  const userId = user.id;
  const { start, end } = range;

  const [[storeRow]] = await db.query(
    'SELECT name, address, phone, currency FROM stores WHERE id = ? LIMIT 1',
    [storeId]
  );
  const [[totals]] = await db.query(
    `SELECT COUNT(*) AS order_count, COALESCE(SUM(s.total), 0) AS revenue
       FROM sales s
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ? AND ${COMPLETED}`,
    [storeId, userId, start, end]
  );
  const [[itemsRow]] = await db.query(
    `SELECT COALESCE(SUM(si.quantity), 0) AS items_sold
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ? AND ${COMPLETED}`,
    [storeId, userId, start, end]
  );
  const pay = await payments(db, storeId, userId, range);
  const products = await productsSold(db, storeId, userId, range);

  // Serving counters are informational (they never feed a revenue figure):
  //  - to_serve_total: the whole backlog, whatever its date
  //  - served_in_period: orders of the period that were already served
  const [[servingRow]] = await db.query(
    `SELECT COALESCE(SUM(CASE WHEN s.served_at IS NULL THEN 1 ELSE 0 END), 0) AS to_serve_total
       FROM sales s
      WHERE s.store_id = ? AND s.user_id = ? AND ${COMPLETED}`,
    [storeId, userId]
  );
  const [[servedRow]] = await db.query(
    `SELECT COALESCE(SUM(CASE WHEN s.served_at IS NOT NULL THEN 1 ELSE 0 END), 0) AS served_in_period
       FROM sales s
      WHERE s.store_id = ? AND s.user_id = ? AND s.occurred_at BETWEEN ? AND ? AND ${COMPLETED}`,
    [storeId, userId, start, end]
  );

  let orders = null;
  let ordersTruncated = false;
  if (options.includeOrders) {
    const { whereSql, params } = orderFilter(storeId, userId, { range });
    const [rows] = await db.query(
      `${ORDER_SELECT} WHERE ${whereSql} ORDER BY s.occurred_at ASC, s.created_at ASC LIMIT ?`,
      [...params, MAX_ORDERS_LIST + 1]
    );
    ordersTruncated = rows.length > MAX_ORDERS_LIST;
    const kept = rows.slice(0, MAX_ORDERS_LIST);
    const items = await itemsBySale(
      db,
      kept.map((r) => r.id)
    );
    orders = kept.map((r) => orderRow(r, items.get(r.id) || []));
  }

  const orderCount = toInt(totals.order_count);
  const revenueCents = toCents(totals.revenue);

  const report = {
    generated_at: localDateTime(new Date()),
    cashier: { id: userId, name: user.name },
    period: {
      key: options.periodKey || 'custom',
      start: localDateTime(start),
      end: localDateTime(end),
      days: inclusiveDays(start, end),
    },
    store: {
      name: storeRow ? storeRow.name : null,
      address: storeRow ? storeRow.address : null,
      phone: storeRow ? storeRow.phone : null,
      currency: storeRow ? storeRow.currency : 'MAD',
    },
    kpis: {
      revenue: money(revenueCents),
      order_count: orderCount,
      items_sold: toInt(itemsRow.items_sold),
      average_ticket: money(orderCount > 0 ? Math.round(revenueCents / orderCount) : 0),
      collected: money(pay._collected_cents),
      outstanding: pay.outstanding,
    },
    payments: {
      methods: pay.methods,
      total_collected: pay.total_collected,
      change_given: pay.change_given,
      outstanding: pay.outstanding,
      unpaid: pay.unpaid,
      partial: pay.partial,
    },
    serving: {
      to_serve_total: toInt(servingRow.to_serve_total),
      served_in_period: toInt(servedRow.served_in_period),
    },
    products,
    orders,
    orders_truncated: ordersTruncated,
  };
  report.integrity = checkIntegrity(report, pay._collected_cents);
  return report;
}

function checkIntegrity(report, collectedCents) {
  const revenueCents = toCents(report.kpis.revenue);
  const checks = {
    revenue_split: collectedCents + toCents(report.payments.outstanding) === revenueCents,
    products_items:
      report.products.length >= MAX_PRODUCTS ||
      report.products.reduce((s, p) => s + p.quantity, 0) === report.kpis.items_sold,
  };
  if (report.orders && !report.orders_truncated) {
    checks.orders_count = report.orders.length === report.kpis.order_count;
    checks.orders_revenue =
      report.orders.reduce((s, o) => s + toCents(o.total), 0) === revenueCents;
  }
  const failed = Object.entries(checks)
    .filter(([, ok]) => !ok)
    .map(([name]) => name);
  return { ok: failed.length === 0, failed };
}

/**
 * GET /reports/my-sales. `user` MUST be req.user (verified JWT): the report
 * is computed for `user.id` and nobody else. All reads share one read-only
 * REPEATABLE READ snapshot, so the screen, the KPIs and the printed report
 * can never disagree.
 */
async function myReport(storeId, user, { period, from, to, includeOrders } = {}) {
  const range = resolveOrThrow(period, from, to);
  const report = await withReadSnapshot((conn) =>
    buildMyReport(conn, storeId, user, range, { periodKey: period, includeOrders })
  );
  if (!report.integrity.ok) {
    // eslint-disable-next-line no-console
    console.warn('[reports] cashier report integrity check failed:', report.integrity.failed.join(', '));
  }
  return report;
}

module.exports = {
  myReport,
  myOrders,
  // exported for tests
  buildMyReport,
  orderFilter,
  checkIntegrity,
  MAX_ORDERS_LIST,
};
