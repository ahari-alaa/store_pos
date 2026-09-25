const { pool } = require('../config/db');
const ApiError = require('../utils/ApiError');
const reportService = require('./reportService');

/**
 * Rapports — ONE consistent report payload.
 *
 * The Rapports screen, the PDF, the Excel export and the Print button all
 * render the object built here, so "dashboard = PDF" holds by construction
 * (they are the same numbers) rather than by two code paths hoping to
 * agree. Nothing in this file writes to the database.
 *
 * What is counted (kept identical to the existing report endpoints —
 * reportService.dashboardOverview / topProducts / dashboardCashierRanking):
 *
 *  - "Vente" / "commande"  = a `sales` row with sale_status = 'COMPLETED'
 *                            whose `occurred_at` falls in the period.
 *                            CANCELLED / REFUNDED sales are never counted
 *                            as sales or revenue (they are only counted in
 *                            `alerts.cancelled` / `alerts.refunded`).
 *  - "Chiffre d'affaires"  = SUM(sales.total) of those sales (TTC, after
 *                            discounts). Unpaid and partially paid sales
 *                            are real sales, so they ARE included — this is
 *                            the meaning the app already gives to revenue.
 *  - "Encaissé"            = money actually applied to those sales,
 *                            SUM(LEAST(paid, total)). Change handed back to
 *                            the customer is not revenue and not cash kept.
 *  - "Reste à encaisser"   = revenue - encaissé (unpaid + partial balances).
 *                            So: CA = Encaissé + Reste à encaisser, always.
 *  - Period membership     = `sales.occurred_at` (the business timestamp),
 *                            never created_at and never "now".
 *
 * Timestamps in the response are NAIVE LOCAL 'YYYY-MM-DD HH:mm:ss' strings
 * (no 'Z'), like `occurred_at` everywhere else in this app. Sending JS Date
 * objects would serialise to UTC ISO strings and shift every hour label in
 * a UTC+1 shop.
 *
 * All the reads run inside ONE read-only REPEATABLE READ transaction, so a
 * sale rung up while the report is being computed can never appear in the
 * hourly table but not in the KPI total.
 */

const TOP_PRODUCTS_LIMIT = 10;
const STOCK_THRESHOLD = 5;
const DEFAULT_RECENT_LIMIT = 10;
// Hard ceiling for the optional full sales list (PDF/Excel "Ventes").
const MAX_SALES_LIST = 5000;

const COMPLETED = "sale_status = 'COMPLETED'";
const IN_PERIOD = 'store_id = ? AND occurred_at BETWEEN ? AND ?';

// ---------------------------------------------------------------------
// Small helpers — money is handled in integer cents so sums, differences
// and percentages never pick up floating-point noise.
// ---------------------------------------------------------------------

function toCents(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100);
}

function money(cents) {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

function toInt(value) {
  return Number(value) || 0;
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

function localDate(d) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function localDateTime(d) {
  return `${localDate(d)} ${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

function percent(part, total) {
  if (!total) return 0;
  return Math.round((part / total) * 1000) / 10;
}

function hourLabel(hour) {
  return `${pad2(hour)}:00 - ${pad2((hour + 1) % 24)}:00`;
}

function inclusiveDays(start, end) {
  const s = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const e = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  return Math.round((e.getTime() - s.getTime()) / (24 * 60 * 60 * 1000)) + 1;
}

// ---------------------------------------------------------------------
// Hourly orders (the "COMMANDES PAR HEURE" table)
// ---------------------------------------------------------------------

/**
 * One row per hour of the day (0..23), zero-filled. `HOUR(occurred_at)`
 * is the hour the sale was actually rung up (its stored business time),
 * not the time the report was generated. For a multi-day period the rows
 * are cumulative over the whole period ("how busy is 12:00-13:00 across
 * the selected days").
 */
async function hourlyOrders(db, storeId, start, end) {
  const [rows] = await db.query(
    `SELECT HOUR(occurred_at) AS hour_of_day,
            COUNT(*)                  AS orders,
            COALESCE(SUM(total), 0)   AS revenue
       FROM sales
      WHERE ${IN_PERIOD} AND ${COMPLETED}
      GROUP BY HOUR(occurred_at)
      ORDER BY hour_of_day ASC`,
    [storeId, start, end]
  );

  const byHour = new Map(rows.map((r) => [toInt(r.hour_of_day), r]));
  let totalOrders = 0;
  let totalCents = 0;
  const hours = [];
  for (let h = 0; h < 24; h += 1) {
    const row = byHour.get(h);
    const orders = row ? toInt(row.orders) : 0;
    const cents = row ? toCents(row.revenue) : 0;
    totalOrders += orders;
    totalCents += cents;
    hours.push({ hour: h, label: hourLabel(h), orders, revenue: money(cents) });
  }
  return {
    hours,
    total: { orders: totalOrders, revenue: money(totalCents) },
  };
}

// ---------------------------------------------------------------------
// Revenue chart (bars = CA, line = number of sales)
// ---------------------------------------------------------------------

function pickGranularity(start, end) {
  const spanDays = (end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000);
  if (spanDays <= 1.5) return 'hour';
  if (spanDays <= 35) return 'day';
  return 'month';
}

const BUCKET_SQL = {
  hour: "DATE_FORMAT(occurred_at, '%Y-%m-%d %H:00:00')",
  day: "DATE_FORMAT(occurred_at, '%Y-%m-%d')",
  month: "DATE_FORMAT(occurred_at, '%Y-%m-01')",
};

function bucketKey(d, unit) {
  if (unit === 'hour') return `${localDate(d)} ${pad2(d.getHours())}:00:00`;
  if (unit === 'day') return localDate(d);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-01`;
}

async function revenueSeries(db, storeId, start, end) {
  const unit = pickGranularity(start, end);
  const [rows] = await db.query(
    `SELECT ${BUCKET_SQL[unit]} AS bucket,
            COALESCE(SUM(total), 0) AS revenue,
            COUNT(*)                AS sale_count
       FROM sales
      WHERE ${IN_PERIOD} AND ${COMPLETED}
      GROUP BY bucket
      ORDER BY bucket ASC`,
    [storeId, start, end]
  );
  const byKey = new Map(rows.map((r) => [String(r.bucket), r]));

  // Zero-filled so a quiet day shows as an empty bar, not as a gap that
  // silently shortens the axis. Calendar arithmetic (setHours/setDate/
  // setMonth) keeps a clock change from skipping or repeating a bucket.
  const buckets = [];
  const cursor = new Date(start);
  if (unit === 'day') cursor.setHours(0, 0, 0, 0);
  if (unit === 'hour') cursor.setMinutes(0, 0, 0);
  if (unit === 'month') {
    cursor.setDate(1);
    cursor.setHours(0, 0, 0, 0);
  }

  const MAX_BUCKETS = 5000;
  while (cursor <= end && buckets.length < MAX_BUCKETS) {
    const key = bucketKey(cursor, unit);
    const row = byKey.get(key);
    buckets.push({
      bucket_start: unit === 'hour' ? key : `${key.slice(0, 10)} 00:00:00`,
      revenue: money(row ? toCents(row.revenue) : 0),
      sale_count: row ? toInt(row.sale_count) : 0,
    });
    if (unit === 'hour') cursor.setHours(cursor.getHours() + 1);
    else if (unit === 'day') cursor.setDate(cursor.getDate() + 1);
    else cursor.setMonth(cursor.getMonth() + 1);
  }

  // Hourly view of a single day: drop the idle hours before the first and
  // after the last sale (the shop is not open at 03:00), but keep every
  // hour in between so a quiet hour still shows as zero.
  if (unit === 'hour') {
    const active = buckets
      .map((b, i) => (b.sale_count > 0 ? i : -1))
      .filter((i) => i >= 0);
    if (active.length === 0) return { granularity: unit, buckets: [] };
    return {
      granularity: unit,
      buckets: buckets.slice(active[0], active[active.length - 1] + 1),
    };
  }
  return { granularity: unit, buckets };
}

// ---------------------------------------------------------------------
// Payments (MOYENS DE PAIEMENT)
// ---------------------------------------------------------------------

/**
 * `payments.amount` stores what the cashier typed as "amount received", so
 * a 100 DH note for a 75 DH sale is stored as 100. The 25 DH handed back is
 * not revenue and is not left in the drawer, so it is taken out of the
 * cash line (and only spills to another method in the practically
 * impossible case where a sale was overpaid without enough cash).
 */
function allocateChange(methods, changeCents) {
  let remaining = changeCents;
  const order = [...methods].sort((a, b) => {
    if (a.method === 'CASH') return -1;
    if (b.method === 'CASH') return 1;
    return b.rawCents - a.rawCents;
  });
  for (const m of order) {
    if (remaining <= 0) break;
    const take = Math.min(m.rawCents, remaining);
    m.netCents = m.rawCents - take;
    remaining -= take;
  }
}

async function paymentsReport(db, storeId, start, end) {
  const [methodRows] = await db.query(
    `SELECT p.payment_method AS method,
            COUNT(*)                  AS tx_count,
            COALESCE(SUM(p.amount), 0) AS amount
       FROM payments p
       JOIN sales s ON s.id = p.sale_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY p.payment_method
      ORDER BY amount DESC`,
    [storeId, start, end]
  );

  // Paid amount per sale is a correlated scalar subquery (uses
  // idx_payments_sale) inside a derived table, so a sale with N payment
  // rows is never counted N times by the outer SUM.
  const [[settle]] = await db.query(
    `SELECT COALESCE(SUM(LEAST(x.paid, x.total)), 0)                  AS collected,
            COALESCE(SUM(x.total - LEAST(x.paid, x.total)), 0)        AS outstanding,
            COALESCE(SUM(GREATEST(x.paid - x.total, 0)), 0)           AS change_given,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PENDING' THEN 1 ELSE 0 END), 0) AS unpaid_count,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PENDING'
                              THEN x.total - LEAST(x.paid, x.total) ELSE 0 END), 0)    AS unpaid_amount,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PARTIALLY_PAID' THEN 1 ELSE 0 END), 0) AS partial_count,
            COALESCE(SUM(CASE WHEN x.payment_status = 'PARTIALLY_PAID'
                              THEN x.total - LEAST(x.paid, x.total) ELSE 0 END), 0)    AS partial_remaining
       FROM (
         SELECT s.total, s.payment_status,
                (SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.sale_id = s.id) AS paid
           FROM sales s
          WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
       ) x`,
    [storeId, start, end]
  );

  const methods = methodRows.map((r) => ({
    method: String(r.method),
    count: toInt(r.tx_count),
    rawCents: toCents(r.amount),
    netCents: toCents(r.amount),
  }));
  const changeCents = toCents(settle.change_given);
  allocateChange(methods, changeCents);

  const collectedCents = toCents(settle.collected);
  const totalNet = methods.reduce((sum, m) => sum + m.netCents, 0);
  const cashNet = methods.filter((m) => m.method === 'CASH').reduce((s, m) => s + m.netCents, 0);

  return {
    methods: methods.map((m) => ({
      method: m.method,
      amount: money(m.netCents),
      count: m.count,
      percent: percent(m.netCents, totalNet),
      // Only cash physically sits in the drawer; card/transfer money does not.
      in_drawer: money(m.method === 'CASH' ? m.netCents : 0),
    })),
    total_collected: money(totalNet),
    transactions: methods.reduce((sum, m) => sum + m.count, 0),
    in_drawer: money(cashNet),
    change_given: money(changeCents),
    outstanding: money(toCents(settle.outstanding)),
    unpaid: { count: toInt(settle.unpaid_count), amount: money(toCents(settle.unpaid_amount)) },
    partial: {
      count: toInt(settle.partial_count),
      remaining: money(toCents(settle.partial_remaining)),
    },
    // Authoritative figure computed per sale, used by the consistency check.
    _collected_cents: collectedCents,
  };
}

// ---------------------------------------------------------------------
// Cashiers, products, expenses
// ---------------------------------------------------------------------

async function cashiersReport(db, storeId, start, end) {
  const [rows] = await db.query(
    `SELECT u.id AS cashier_id, u.name AS cashier_name, u.role,
            COUNT(*)                  AS sale_count,
            COALESCE(SUM(s.total), 0) AS revenue
       FROM sales s
       JOIN users u ON u.id = s.user_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY u.id, u.name, u.role
      ORDER BY revenue DESC, u.name ASC`,
    [storeId, start, end]
  );
  // Items are aggregated in their own query (grouped by the sale's user)
  // instead of joining sale_items onto the query above, which would
  // multiply every sale by its number of lines.
  const [itemRows] = await db.query(
    `SELECT s.user_id AS cashier_id, COALESCE(SUM(si.quantity), 0) AS items_sold
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY s.user_id`,
    [storeId, start, end]
  );
  const itemsByCashier = new Map(itemRows.map((r) => [String(r.cashier_id), toInt(r.items_sold)]));

  return rows.map((r) => {
    const count = toInt(r.sale_count);
    const cents = toCents(r.revenue);
    return {
      cashier_id: String(r.cashier_id),
      name: r.cashier_name,
      role: r.role,
      sale_count: count,
      items_sold: itemsByCashier.get(String(r.cashier_id)) || 0,
      revenue: money(cents),
      average_ticket: money(count > 0 ? Math.round(cents / count) : 0),
    };
  });
}

async function topProductsReport(db, storeId, start, end, limit) {
  const [rows] = await db.query(
    `SELECT si.product_id, p.name,
            SUM(si.quantity)             AS quantity,
            COALESCE(SUM(si.subtotal), 0) AS revenue
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
       JOIN products p ON p.id = si.product_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY si.product_id, p.name
      ORDER BY quantity DESC, revenue DESC
      LIMIT ?`,
    [storeId, start, end, limit]
  );
  return rows.map((r) => ({
    product_id: String(r.product_id),
    name: r.name,
    quantity: toInt(r.quantity),
    revenue: money(toCents(r.revenue)),
  }));
}

async function expensesReport(db, storeId, start, end) {
  const [rows] = await db.query(
    `SELECT category, COALESCE(SUM(amount), 0) AS amount, COUNT(*) AS expense_count
       FROM expenses
      WHERE ${IN_PERIOD}
      GROUP BY category
      ORDER BY amount DESC, category ASC`,
    [storeId, start, end]
  );
  const totalCents = rows.reduce((sum, r) => sum + toCents(r.amount), 0);
  return {
    total: money(totalCents),
    count: rows.reduce((sum, r) => sum + toInt(r.expense_count), 0),
    by_category: rows.map((r) => ({
      category: r.category,
      amount: money(toCents(r.amount)),
      count: toInt(r.expense_count),
      percent: percent(toCents(r.amount), totalCents),
    })),
  };
}

// ---------------------------------------------------------------------
// Sales lists (recent sales panel + full list for PDF/Excel)
// ---------------------------------------------------------------------

function saleRow(r) {
  return {
    id: r.id,
    user_id: r.user_id,
    cashier_name: r.cashier_name,
    subtotal: money(toCents(r.subtotal)),
    discount_total: money(toCents(r.discount_total)),
    tax_total: money(toCents(r.tax_total)),
    total: money(toCents(r.total)),
    payment_status: r.payment_status,
    sale_status: r.sale_status,
    occurred_at: String(r.occurred_at),
    note: r.note || null,
    items_count: toInt(r.items_count),
    paid_amount: money(Math.min(toCents(r.paid_amount), toCents(r.total))),
    // Same convention as GET /sales and dashboard-recent-sales: 'MIXED'
    // when several distinct methods were used, null while unpaid.
    payment_method: toInt(r.payment_method_count) > 1 ? 'MIXED' : r.last_payment_method || null,
  };
}

const SALE_LIST_SELECT = `
  SELECT s.id, s.user_id, s.subtotal, s.discount_total, s.tax_total, s.total,
         s.payment_status, s.sale_status, s.note, s.occurred_at,
         u.name AS cashier_name,
         (SELECT COALESCE(SUM(si.quantity), 0) FROM sale_items si WHERE si.sale_id = s.id) AS items_count,
         (SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.sale_id = s.id)        AS paid_amount,
         (SELECT COUNT(DISTINCT p.payment_method) FROM payments p WHERE p.sale_id = s.id)  AS payment_method_count,
         (SELECT p.payment_method FROM payments p WHERE p.sale_id = s.id
           ORDER BY p.created_at DESC LIMIT 1)                                             AS last_payment_method
    FROM sales s
    LEFT JOIN users u ON u.id = s.user_id
   WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ?`;

async function recentSales(db, storeId, start, end, limit) {
  const [rows] = await db.query(
    `${SALE_LIST_SELECT} ORDER BY s.occurred_at DESC, s.created_at DESC LIMIT ?`,
    [storeId, start, end, limit]
  );
  return rows.map(saleRow);
}

async function allSales(db, storeId, start, end) {
  // One extra row tells us whether the cap cut the list short.
  const [rows] = await db.query(
    `${SALE_LIST_SELECT} ORDER BY s.occurred_at ASC, s.created_at ASC LIMIT ?`,
    [storeId, start, end, MAX_SALES_LIST + 1]
  );
  const truncated = rows.length > MAX_SALES_LIST;
  return { sales: rows.slice(0, MAX_SALES_LIST).map(saleRow), truncated };
}

// ---------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------

async function statusCounts(db, storeId, start, end) {
  const [rows] = await db.query(
    `SELECT sale_status, COUNT(*) AS c
       FROM sales
      WHERE ${IN_PERIOD}
      GROUP BY sale_status`,
    [storeId, start, end]
  );
  const out = { COMPLETED: 0, CANCELLED: 0, REFUNDED: 0 };
  rows.forEach((r) => {
    if (r.sale_status in out) out[r.sale_status] = toInt(r.c);
  });
  return out;
}

/**
 * Stock is a snapshot of "now" (no date range), read through the existing
 * reportService.stockReport so this screen and the "État du stock" logic
 * can never disagree about what "rupture" / "faible" mean.
 */
async function stockAlerts(storeId) {
  const report = await reportService.stockReport(storeId, { threshold: STOCK_THRESHOLD });
  const toItem = (kind) => (row) => ({
    kind,
    name: row.name,
    quantity: Number(row.stock_quantity),
    status: row.status,
    unit: kind === 'ingredient' ? row.unit || null : null,
  });
  const items = [
    ...report.products.map(toItem('product')),
    ...report.ingredients.map(toItem('ingredient')),
  ].sort((a, b) => {
    if (a.status !== b.status) return a.status === 'rupture' ? -1 : 1;
    return a.quantity - b.quantity;
  });
  return {
    threshold: report.threshold,
    out_of_stock: report.products_summary.rupture + report.ingredients_summary.rupture,
    low_stock: report.products_summary.faible + report.ingredients_summary.faible,
    items: items.slice(0, 8),
  };
}

// ---------------------------------------------------------------------
// Assembly
// ---------------------------------------------------------------------

/**
 * Builds the whole report from `db` (anything with `.query` — a pooled
 * transaction connection in production, a fake in tests). Pure reads.
 */
async function buildOverview(db, storeId, range, options = {}) {
  const { start, end } = range;
  const recentLimit = options.recentLimit || DEFAULT_RECENT_LIMIT;

  const [[storeRow]] = await db.query(
    'SELECT name, address, phone, currency FROM stores WHERE id = ? LIMIT 1',
    [storeId]
  );

  const [[totals]] = await db.query(
    `SELECT COUNT(*)                        AS sale_count,
            COALESCE(SUM(total), 0)          AS revenue,
            COALESCE(SUM(tax_total), 0)      AS tax_total,
            COALESCE(SUM(discount_total), 0) AS discount_total
       FROM sales
      WHERE ${IN_PERIOD} AND ${COMPLETED}`,
    [storeId, start, end]
  );
  const [[itemsRow]] = await db.query(
    `SELECT COALESCE(SUM(si.quantity), 0) AS items_sold
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'`,
    [storeId, start, end]
  );

  const hourly = await hourlyOrders(db, storeId, start, end);
  const series = await revenueSeries(db, storeId, start, end);
  const payments = await paymentsReport(db, storeId, start, end);
  const cashiers = await cashiersReport(db, storeId, start, end);
  const topProducts = await topProductsReport(db, storeId, start, end, TOP_PRODUCTS_LIMIT);
  const expenses = await expensesReport(db, storeId, start, end);
  const statuses = await statusCounts(db, storeId, start, end);
  const recent = await recentSales(db, storeId, start, end, recentLimit);
  const list = options.includeSales ? await allSales(db, storeId, start, end) : null;

  const saleCount = toInt(totals.sale_count);
  const revenueCents = toCents(totals.revenue);
  const taxCents = toCents(totals.tax_total);
  const expensesCents = toCents(expenses.total);

  const result = {
    generated_at: localDateTime(new Date()),
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
      sale_count: saleCount,
      items_sold: toInt(itemsRow.items_sold),
      average_ticket: money(saleCount > 0 ? Math.round(revenueCents / saleCount) : 0),
      expenses: money(expensesCents),
      estimated_result: money(revenueCents - expensesCents),
    },
    tax: {
      total: money(taxCents),
      revenue_ex_tax: money(revenueCents - taxCents),
      discount_total: money(toCents(totals.discount_total)),
    },
    revenue_series: series,
    orders_by_hour: hourly,
    payments: {
      methods: payments.methods,
      total_collected: payments.total_collected,
      transactions: payments.transactions,
      in_drawer: payments.in_drawer,
      change_given: payments.change_given,
      outstanding: payments.outstanding,
    },
    cashiers,
    top_products: topProducts,
    expenses,
    alerts: {
      unpaid: payments.unpaid,
      partial: payments.partial,
      cancelled: statuses.CANCELLED,
      refunded: statuses.REFUNDED,
      stock: null, // filled by the caller (reads outside the snapshot)
    },
    recent_sales: recent,
    sales: list ? list.sales : null,
    sales_truncated: list ? list.truncated : false,
  };

  result.integrity = checkIntegrity(result, payments._collected_cents);
  return result;
}

/**
 * Cross-checks that the independently-queried sections add up to the same
 * totals. They are all read from one snapshot, so a mismatch means a
 * genuine logic/data problem — surfaced (and logged) instead of silently
 * shown as two different "truths" on one page.
 */
function checkIntegrity(report, collectedCents) {
  const revenueCents = toCents(report.kpis.revenue);
  const sum = (items, pick) => items.reduce((s, i) => s + pick(i), 0);
  const checks = {
    hourly_orders: report.orders_by_hour.total.orders === report.kpis.sale_count,
    hourly_revenue: toCents(report.orders_by_hour.total.revenue) === revenueCents,
    chart_revenue:
      sum(report.revenue_series.buckets, (b) => toCents(b.revenue)) === revenueCents ||
      report.revenue_series.buckets.length === 0,
    cashiers_orders: sum(report.cashiers, (c) => c.sale_count) === report.kpis.sale_count,
    cashiers_revenue: sum(report.cashiers, (c) => toCents(c.revenue)) === revenueCents,
    payments_collected: toCents(report.payments.total_collected) === collectedCents,
    revenue_split:
      collectedCents + toCents(report.payments.outstanding) === revenueCents,
    expenses_total: toCents(report.expenses.total) === toCents(report.kpis.expenses),
  };
  if (report.sales && !report.sales_truncated) {
    checks.sales_list_revenue =
      sum(
        report.sales.filter((s) => s.sale_status === 'COMPLETED'),
        (s) => toCents(s.total)
      ) === revenueCents;
  }
  const failed = Object.entries(checks)
    .filter(([, ok]) => !ok)
    .map(([name]) => name);
  return { ok: failed.length === 0, failed };
}

/**
 * Runs `work(conn)` on a read-only REPEATABLE READ transaction so every
 * query sees the same snapshot of the data.
 */
async function withReadSnapshot(work) {
  const conn = await pool.getConnection();
  try {
    // One-shot: applies to the next transaction only, so the pooled
    // connection's own isolation level is left untouched afterwards.
    await conn.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
    await conn.query('START TRANSACTION READ ONLY');
    try {
      return await work(conn);
    } finally {
      await conn.query('COMMIT');
    }
  } finally {
    conn.release();
  }
}

function resolveOrThrow(period, from, to) {
  const range = reportService.resolveRange(period, from, to);
  if (Number.isNaN(range.start.getTime()) || Number.isNaN(range.end.getTime())) {
    throw ApiError.badRequest('Invalid date range', 'INVALID_RANGE');
  }
  if (range.start.getTime() > range.end.getTime()) {
    throw ApiError.badRequest('"from" must not be after "to"', 'INVALID_RANGE');
  }
  return range;
}

async function reportOverview(storeId, { period, from, to, includeSales, recentLimit } = {}) {
  const range = resolveOrThrow(period, from, to);

  const overview = await withReadSnapshot((conn) =>
    buildOverview(conn, storeId, range, { periodKey: period, includeSales, recentLimit })
  );
  // Stock is a "now" snapshot read outside the sales snapshot. If it fails
  // the rest of the report is still valid, so it degrades to `null`
  // ("stock unavailable") instead of failing the whole page.
  try {
    overview.alerts.stock = await stockAlerts(storeId);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.warn('[reports] stock alerts unavailable:', err.message);
    overview.alerts.stock = null;
  }

  if (!overview.integrity.ok) {
    // eslint-disable-next-line no-console
    console.warn('[reports] integrity check failed:', overview.integrity.failed.join(', '));
  }
  return overview;
}

/**
 * Standalone "orders per hour" report — the same computation the
 * overview embeds, for callers that only need this table.
 */
async function ordersByHour(storeId, { period, from, to } = {}) {
  const range = resolveOrThrow(period, from, to);
  const hourly = await hourlyOrders(pool, storeId, range.start, range.end);
  return {
    period: {
      key: period || 'custom',
      start: localDateTime(range.start),
      end: localDateTime(range.end),
      days: inclusiveDays(range.start, range.end),
    },
    scope: 'cumulative_over_period',
    ...hourly,
  };
}

module.exports = {
  reportOverview,
  ordersByHour,
  // Shared with cashierReportService (the cashier's personal report must
  // count exactly like the admin report: same rules, same helpers).
  resolveOrThrow,
  withReadSnapshot,
  toCents,
  money,
  toInt,
  percent,
  localDateTime,
  inclusiveDays,
  // exported for tests
  buildOverview,
  hourlyOrders,
  allocateChange,
  checkIntegrity,
  pickGranularity,
  MAX_SALES_LIST,
};
