const { pool } = require('../config/db');
const ApiError = require('../utils/ApiError');
const saleRepository = require('../repositories/saleRepository');
const userRepository = require('../repositories/userRepository');
const ingredientService = require('./ingredientService');

// Parses a `from`/`to` boundary the way the rest of this app already
// treats timestamps: as NAIVE LOCAL time (see reportValidators.js's
// localDateTime note — `occurred_at` is stored with no timezone
// conversion). Two shapes need care because `new Date(str)` reads them
// differently from what a shop manager means:
//   - a bare date ('2026-09-18') is parsed by JS as UTC midnight, which
//     in a UTC+1 shop is 01:00 local — and used as a `to` boundary it
//     silently drops the whole last day. Here a date-only `from` means
//     00:00:00 local and a date-only `to` means 23:59:59.999 local.
//   - 'YYYY-MM-DD HH:mm:ss' / 'YYYY-MM-DDTHH:mm:ss' are built explicitly
//     from their components instead of relying on engine-specific parsing.
// Anything else (an ISO string with 'Z' or an offset) keeps the original
// `new Date(value)` behaviour.
function parseBoundary(value, isEnd) {
  if (value instanceof Date) return value;
  const text = String(value).trim();

  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (dateOnly) {
    const [y, m, d] = [Number(dateOnly[1]), Number(dateOnly[2]), Number(dateOnly[3])];
    return isEnd ? new Date(y, m - 1, d, 23, 59, 59, 999) : new Date(y, m - 1, d, 0, 0, 0, 0);
  }

  const dateTime = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(text);
  if (dateTime) {
    const n = dateTime.slice(1).map(Number);
    return new Date(n[0], n[1] - 1, n[2], n[3], n[4], n[5], isEnd ? 999 : 0);
  }

  return new Date(text);
}

function dateRangeOrDefault(from, to) {
  const end = to ? parseBoundary(to, true) : new Date();
  const start = from ? parseBoundary(from, false) : new Date(end.getTime() - 30 * 24 * 60 * 60 * 1000);
  return { start, end };
}

function startOfDay(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

function endOfDay(date) {
  const d = new Date(date);
  d.setHours(23, 59, 59, 999);
  return d;
}

// Monday-start week, matching the rest of the app's "week" concept
// (dashboardCashierRanking's original resolvePeriod already used this
// convention for 'week' — kept identical here). Uses calendar-day
// arithmetic (setDate) rather than subtracting N*24h of milliseconds, so
// a clock change inside the week (the shop's local timezone can shift by
// an hour) can never push the boundary to 23:00 of the previous day.
function startOfWeek(date) {
  const day = date.getDay();
  const diffToMonday = (day + 6) % 7;
  const d = new Date(date);
  d.setDate(d.getDate() - diffToMonday);
  return startOfDay(d);
}

// =====================================================================
// Shared period resolution — the single source of truth for every named
// period used across Accueil/Dashboard AND the Rapports screen (spec
// §4: Aujourd'hui / Hier / Cette semaine / Semaine précédente / Ce mois /
// Mois précédent / custom range). Every endpoint below calls THIS
// function so "cette semaine" (for example) can never mean two different
// date ranges depending on which screen asked for it (spec §25: no
// duplicated business logic).
// =====================================================================
function resolveRange(period, from, to) {
  const now = new Date();
  switch (period) {
    case 'today':
      return { start: startOfDay(now), end: endOfDay(now) };
    case 'yesterday': {
      const y = new Date(now);
      y.setDate(y.getDate() - 1);
      return { start: startOfDay(y), end: endOfDay(y) };
    }
    case 'week':
      return { start: startOfWeek(now), end: endOfDay(now) };
    case 'last_week': {
      const lastWeekStart = startOfWeek(now);
      lastWeekStart.setDate(lastWeekStart.getDate() - 7);
      const lastWeekEnd = new Date(lastWeekStart);
      lastWeekEnd.setDate(lastWeekEnd.getDate() + 6);
      return { start: lastWeekStart, end: endOfDay(lastWeekEnd) };
    }
    case 'month':
      return { start: new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0), end: endOfDay(now) };
    case 'last_month': {
      const start = new Date(now.getFullYear(), now.getMonth() - 1, 1, 0, 0, 0, 0);
      const end = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999);
      return { start, end };
    }
    case 'custom':
      return dateRangeOrDefault(from, to);
    default:
      // No/unknown period name: fall back to the legacy from/to (or
      // 30-day default) contract every endpoint originally had.
      return dateRangeOrDefault(from, to);
  }
}

// Kept as a thin alias: this is the exact function name/signature the
// original Dashboard endpoints were written against.
function resolvePeriod(period, from, to) {
  return resolveRange(period, from, to);
}

function percentOf(part, total) {
  const p = Number(part);
  const t = Number(total);
  if (!t) return 0;
  return Math.round((p / t) * 1000) / 10;
}

async function salesSummary(storeId, { period, from, to } = {}) {
  const { start, end } = period ? resolveRange(period, from, to) : dateRangeOrDefault(from, to);

  const [[totals]] = await pool.query(
    `SELECT
        COUNT(*)                    AS sale_count,
        COALESCE(SUM(total), 0)     AS total_revenue,
        COALESCE(SUM(discount_total), 0) AS total_discount,
        COALESCE(SUM(tax_total), 0) AS total_tax,
        COALESCE(AVG(total), 0)     AS average_sale
     FROM sales
     WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'`,
    [storeId, start, end]
  );

  const [byDay] = await pool.query(
    `SELECT DATE(occurred_at) AS day, COUNT(*) AS sale_count, COALESCE(SUM(total), 0) AS revenue
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'
      GROUP BY DATE(occurred_at)
      ORDER BY day ASC`,
    [storeId, start, end]
  );

  // Payment Analysis (Rapports §9) — every real payment method present in
  // this store's data, each with its amount, share of the total, and how
  // many transactions used it. Never a hard-coded CASH/CARD list: a store
  // that has only ever taken CASH gets back exactly one row.
  const [byPaymentMethodRaw] = await pool.query(
    `SELECT p.payment_method, COUNT(*) AS tx_count, COALESCE(SUM(p.amount), 0) AS amount
       FROM payments p
       JOIN sales s ON s.id = p.sale_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ?
      GROUP BY p.payment_method
      ORDER BY amount DESC`,
    [storeId, start, end]
  );
  const totalPaymentAmount = byPaymentMethodRaw.reduce((sum, row) => sum + Number(row.amount), 0);
  const byPaymentMethod = byPaymentMethodRaw.map((row) => ({
    payment_method: row.payment_method,
    amount: String(row.amount),
    transaction_count: Number(row.tx_count) || 0,
    percent: percentOf(row.amount, totalPaymentAmount),
  }));

  // Sales Summary (Rapports §8) — real sale_status/payment_status values
  // only (see migrations/001_init.sql), never an invented "pending"
  // bucket for sale_status.
  const [[statusRow]] = await pool.query(
    `SELECT
        COUNT(*) AS total_count,
        SUM(CASE WHEN sale_status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed_count,
        SUM(CASE WHEN sale_status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled_count,
        SUM(CASE WHEN sale_status = 'REFUNDED'  THEN 1 ELSE 0 END) AS refunded_sale_count,
        SUM(CASE WHEN payment_status = 'PAID'            THEN 1 ELSE 0 END) AS paid_count,
        SUM(CASE WHEN payment_status = 'PENDING'         THEN 1 ELSE 0 END) AS not_paid_count,
        SUM(CASE WHEN payment_status = 'PARTIALLY_PAID'  THEN 1 ELSE 0 END) AS partially_paid_count,
        SUM(CASE WHEN payment_status = 'REFUNDED'        THEN 1 ELSE 0 END) AS refunded_payment_count
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ?`,
    [storeId, start, end]
  );

  return {
    range: { from: start, to: end },
    totals,
    by_day: byDay,
    by_payment_method: byPaymentMethod,
    status_summary: {
      total: Number(statusRow.total_count) || 0,
      completed: Number(statusRow.completed_count) || 0,
      cancelled: Number(statusRow.cancelled_count) || 0,
      refunded_sales: Number(statusRow.refunded_sale_count) || 0,
      paid: Number(statusRow.paid_count) || 0,
      not_paid: Number(statusRow.not_paid_count) || 0,
      partially_paid: Number(statusRow.partially_paid_count) || 0,
      refunded_payments: Number(statusRow.refunded_payment_count) || 0,
    },
  };
}

async function topProducts(storeId, { period, from, to, limit = 10 } = {}) {
  const { start, end } = period ? resolveRange(period, from, to) : dateRangeOrDefault(from, to);
  const [rows] = await pool.query(
    `SELECT si.product_id, p.name, SUM(si.quantity) AS quantity_sold,
            SUM(si.subtotal) AS revenue
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
       JOIN products p ON p.id = si.product_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY si.product_id, p.name
      ORDER BY quantity_sold DESC
      LIMIT ?`,
    [storeId, start, end, limit]
  );
  return rows;
}

async function expensesSummary(storeId, { period, from, to } = {}) {
  const { start, end } = period ? resolveRange(period, from, to) : dateRangeOrDefault(from, to);
  const [[totals]] = await pool.query(
    `SELECT COUNT(*) AS expense_count, COALESCE(SUM(amount), 0) AS total_amount
       FROM expenses
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ?`,
    [storeId, start, end]
  );
  const [byCategory] = await pool.query(
    `SELECT category, COALESCE(SUM(amount), 0) AS amount, COUNT(*) AS count
       FROM expenses
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ?
      GROUP BY category
      ORDER BY amount DESC`,
    [storeId, start, end]
  );
  return { range: { from: start, to: end }, totals, by_category: byCategory };
}

/**
 * Snapshot (not period-based — stock has no "date range", only "now") of
 * every active product at/under `threshold` units. `status` follows the
 * exact same 'rupture' (0 units) / 'faible' (<= threshold) vocabulary
 * ingredientService.withStatus already uses, so the Rapports Stock
 * section and the Ingredients screen never disagree on what those two
 * words mean.
 */
async function lowStock(storeId, { threshold = 5 } = {}) {
  const [rows] = await pool.query(
    `SELECT id, name, stock_quantity, category
       FROM products
      WHERE store_id = ? AND is_active = 1 AND stock_quantity <= ?
      ORDER BY stock_quantity ASC`,
    [storeId, threshold]
  );
  return rows.map((row) => ({
    ...row,
    status: Number(row.stock_quantity) <= 0 ? 'rupture' : 'faible',
  }));
}

/**
 * "État du stock" (Rapports §14) — products AND ingredients that are low
 * or out of stock, in one call. Reuses [lowStock] (products) and the
 * already-existing ingredientService.lowStock (which already computes the
 * identical rupture/faible status) rather than re-implementing either
 * query (spec §25).
 */
async function stockReport(storeId, { threshold = 5 } = {}) {
  const [products, ingredients] = await Promise.all([
    lowStock(storeId, { threshold }),
    ingredientService.lowStock(storeId),
  ]);
  const countByStatus = (list) => ({
    rupture: list.filter((item) => item.status === 'rupture').length,
    faible: list.filter((item) => item.status === 'faible').length,
  });
  return {
    threshold,
    products,
    ingredients,
    products_summary: countByStatus(products),
    ingredients_summary: countByStatus(ingredients),
  };
}

function toSummary(row) {
  const orders = Number(row.order_count) || 0;
  const totalSales = row.total_sales != null ? Number(row.total_sales) : 0;
  return {
    orders,
    total_sales: row.total_sales != null ? String(row.total_sales) : '0.00',
    items_sold: Number(row.items_sold) || 0,
    // Derived from THIS report's own total_sales/orders (the paid-amount
    // total, capped per sale — see PAID_AMOUNT_JOIN), not a fresh
    // AVG(s.total) query, so "ticket moyen" here always agrees with the
    // "CA" figure shown right next to it (spec §11).
    average_ticket: orders > 0 ? (totalSales / orders).toFixed(2) : '0.00',
    paid_orders: Number(row.paid_count) || 0,
    not_paid_orders: Number(row.not_paid_count) || 0,
    partially_paid_orders: Number(row.partially_paid_count) || 0,
  };
}

/**
 * Cashier activity report backing the Cashiers screen's "Sales Report"
 * (Day/Month) AND the Rapports screen's cashier-detail drill-down (spec
 * §11) — see reportRoutes GET /reports/cashier-sales.
 *
 * Multi-store security (spec section 5/9): `cashier_id` is only looked up
 * WITHIN `storeId` (the authenticated admin/manager's own store, from
 * req.user.storeId — never taken from the request). An admin from one
 * store can never pull another store's cashier data this way, and a
 * cashier id that doesn't belong to this store is reported as not found,
 * not silently ignored.
 *
 * `group_by: 'day'` adds the daily breakdown used by the Month report /
 * Rapports cashier detail's "Sales by day" table; the Day report only
 * needs the summary, so it's omitted by default to avoid an unnecessary
 * query.
 *
 * Accepts EITHER a named `period` (Rapports) OR an explicit `from`/`to`
 * range (the Cashiers screen's original contract, which computes exact
 * boundaries client-side via LocalDateRange) — reportValidators enforces
 * that at least one is present.
 */
async function cashierSalesReport(
  storeId,
  { cashier_id: cashierId, period, from, to, group_by: groupBy }
) {
  const cashier = await userRepository.findByIdForStore(storeId, cashierId);
  if (!cashier) {
    throw ApiError.notFound('Cashier not found in this store', 'CASHIER_NOT_FOUND');
  }

  // Two ways in: an explicit from/to range (the Cashiers screen's
  // original contract — computed client-side via LocalDateRange, passed
  // straight through untouched) OR a named `period` (Rapports), resolved
  // here to concrete boundaries. Only the `period` path goes through
  // [resolveRange] — the legacy from/to path is passed to the
  // repository exactly as received, unchanged from before this file
  // gained period support.
  const rangeFrom = period ? resolveRange(period, from, to).start : from;
  const rangeTo = period ? resolveRange(period, from, to).end : to;

  const summaryRow = await saleRepository.cashierSalesSummary(storeId, cashierId, rangeFrom, rangeTo);

  // Payment breakdown for THIS cashier (Rapports §11: "Payment
  // breakdown — show how this cashier's transactions were paid"), same
  // amount/count/percent shape as the store-wide one in [salesSummary]
  // so the UI widget can be shared between the two screens.
  const paymentRows = await saleRepository.cashierPaymentBreakdown(
    storeId,
    cashierId,
    rangeFrom,
    rangeTo
  );
  const totalPaymentAmount = paymentRows.reduce((sum, row) => sum + Number(row.amount), 0);
  const paymentBreakdown = paymentRows.map((row) => ({
    payment_method: row.payment_method,
    amount: String(row.amount),
    transaction_count: Number(row.tx_count) || 0,
    percent: percentOf(row.amount, totalPaymentAmount),
  }));

  const result = {
    cashier: {
      id: cashier.id,
      name: cashier.name,
      email: cashier.email,
      role: cashier.role,
      is_active: !!cashier.is_active,
    },
    period: { from: rangeFrom, to: rangeTo },
    summary: toSummary(summaryRow),
    payment_breakdown: paymentBreakdown,
  };

  if (groupBy === 'day') {
    const dayRows = await saleRepository.cashierSalesByDay(storeId, cashierId, rangeFrom, rangeTo);
    result.days = dayRows.map((row) => ({
      date: row.day,
      ...toSummary(row),
    }));
  }

  return result;
}

function percentChange(current, previous) {
  const c = Number(current);
  const p = Number(previous);
  if (p === 0) return c === 0 ? 0 : 100;
  return Math.round(((c - p) / p) * 1000) / 10;
}

/**
 * Dashboard summary (Accueil → Tableau de bord mock): today's KPI tiles
 * (ventes/commandes/ticket moyen/dépenses, each with a "% vs hier"
 * comparison), the 7-day sales line chart, the top-selling products list,
 * and low-stock alerts across both products and ingredients.
 */
async function dashboard(storeId) {
  const now = new Date();
  const todayStart = startOfDay(now);
  const todayEnd = endOfDay(now);
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStart = startOfDay(yesterday);
  const yesterdayEnd = endOfDay(yesterday);
  const sevenDaysAgo = startOfDay(new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000));

  const [[todayTotals]] = await pool.query(
    `SELECT COUNT(*) AS order_count, COALESCE(SUM(total), 0) AS total_sales,
            COALESCE(AVG(total), 0) AS average_ticket
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'`,
    [storeId, todayStart, todayEnd]
  );

  const [[yesterdayTotals]] = await pool.query(
    `SELECT COUNT(*) AS order_count, COALESCE(SUM(total), 0) AS total_sales
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'`,
    [storeId, yesterdayStart, yesterdayEnd]
  );

  const [[todayExpenses]] = await pool.query(
    `SELECT COALESCE(SUM(amount), 0) AS total_amount
       FROM expenses WHERE store_id = ? AND occurred_at BETWEEN ? AND ?`,
    [storeId, todayStart, todayEnd]
  );

  const [[yesterdayExpenses]] = await pool.query(
    `SELECT COALESCE(SUM(amount), 0) AS total_amount
       FROM expenses WHERE store_id = ? AND occurred_at BETWEEN ? AND ?`,
    [storeId, yesterdayStart, yesterdayEnd]
  );

  const [byDay] = await pool.query(
    `SELECT DATE(occurred_at) AS day, COALESCE(SUM(total), 0) AS revenue
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'
      GROUP BY DATE(occurred_at)
      ORDER BY day ASC`,
    [storeId, sevenDaysAgo, todayEnd]
  );

  const topProductsRows = await topProducts(storeId, {
    from: sevenDaysAgo.toISOString(),
    to: todayEnd.toISOString(),
    limit: 5,
  });

  const lowStockProducts = await lowStock(storeId, { threshold: 5 });
  const lowStockIngredients = await ingredientService.lowStock(storeId);

  return {
    today: {
      total_sales: String(todayTotals.total_sales),
      order_count: Number(todayTotals.order_count),
      average_ticket: Number(todayTotals.average_ticket).toFixed(2),
      total_expenses: String(todayExpenses.total_amount),
      vs_yesterday: {
        total_sales_percent: percentChange(todayTotals.total_sales, yesterdayTotals.total_sales),
        order_count_percent: percentChange(todayTotals.order_count, yesterdayTotals.order_count),
        total_expenses_percent: percentChange(
          todayExpenses.total_amount,
          yesterdayExpenses.total_amount
        ),
      },
    },
    sales_last_7_days: byDay,
    top_products: topProductsRows,
    low_stock_products: lowStockProducts,
    low_stock_ingredients: lowStockIngredients,
  };
}

// =====================================================================
// Accueil / Dashboard (period-aware) AND Rapports — KPIs, cashier
// ranking, sales status breakdown, revenue chart series and recent
// sales. All resolve their date range through [resolveRange] above, so
// the exact same "period" name always means the exact same [start, end]
// no matter which screen is asking (spec §25).
// =====================================================================

/**
 * KPI cards: revenue / number of sales / items sold / average sale for
 * the selected period. `sale_status = 'COMPLETED'` matches every other
 * revenue aggregate in this file (salesSummary/dashboard/topProducts) —
 * cancelled/refunded sales never count toward revenue.
 */
async function dashboardOverview(storeId, period, from, to) {
  const { start, end } = resolvePeriod(period, from, to);

  const [[totals]] = await pool.query(
    `SELECT COUNT(*) AS sale_count, COALESCE(SUM(total), 0) AS total_revenue,
            COALESCE(AVG(total), 0) AS average_sale
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'`,
    [storeId, start, end]
  );

  const [[itemsRow]] = await pool.query(
    `SELECT COALESCE(SUM(si.quantity), 0) AS items_sold
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'`,
    [storeId, start, end]
  );

  return {
    period,
    range: { from: start, to: end },
    total_revenue: String(totals.total_revenue),
    sale_count: Number(totals.sale_count) || 0,
    items_sold: Number(itemsRow.items_sold) || 0,
    average_sale: Number(totals.average_sale).toFixed(2),
  };
}

/**
 * "Meilleur caissier" / Rapports "Performance des caissiers" — every
 * cashier/manager/admin who logged at least one completed sale in the
 * period, ranked by revenue. Reads directly off `sales.user_id` /
 * `users` (spec §12: no hard-coded cashier), so a store with a single
 * cashier still returns a one-row ranking rather than special-cased
 * "best cashier" logic.
 */
async function dashboardCashierRanking(storeId, period, from, to) {
  const { start, end } = resolvePeriod(period, from, to);

  // items_sold (spec: "Ventes par caissier" needs orders/articles/total,
  // not just orders/total) is computed via a correlated subquery rather
  // than joining sale_items directly onto the outer query, so a sale
  // with several line items isn't double-counted by the outer
  // GROUP BY/COUNT(*) — the same reason cashierSalesSummary's
  // PAID_AMOUNT_JOIN in saleRepository.js uses a derived table instead
  // of a direct join.
  const [rows] = await pool.query(
    `SELECT u.id AS cashier_id, u.name AS cashier_name, u.role,
            COUNT(*) AS sale_count,
            COALESCE(SUM(s.total), 0) AS total_sales,
            COALESCE(AVG(s.total), 0) AS average_sale,
            COALESCE((
              SELECT SUM(si.quantity)
                FROM sale_items si
               WHERE si.sale_id IN (
                 SELECT id FROM sales s2
                  WHERE s2.store_id = s.store_id AND s2.user_id = s.user_id
                    AND s2.occurred_at BETWEEN ? AND ? AND s2.sale_status = 'COMPLETED'
               )
            ), 0) AS items_sold
       FROM sales s
       JOIN users u ON u.id = s.user_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY u.id, u.name, u.role
      ORDER BY total_sales DESC`,
    [start, end, storeId, start, end]
  );

  return {
    period,
    range: { from: start, to: end },
    cashiers: rows.map((row) => ({
      cashier_id: row.cashier_id,
      cashier_name: row.cashier_name,
      role: row.role,
      sale_count: Number(row.sale_count) || 0,
      items_sold: Number(row.items_sold) || 0,
      total_sales: String(row.total_sales),
      average_sale: Number(row.average_sale).toFixed(2),
    })),
  };
}

/**
 * "Articles vendus aujourd'hui" / "المنتجات المباعة اليوم" / Rapports
 * "Articles les plus vendus" — per-product units sold in the selected
 * period (spec §5/§12: SUM(sale_items.quantity) per product, never the
 * number of sale/order rows). Shares [resolveRange] with the other
 * period-aware sections so it always lines up with the KPI cards and
 * cashier ranking above it. Capped to the top `limit` products by
 * quantity — the Flutter widget shows a compact bar/list (spec §9) with
 * a "Voir plus" link rather than an unbounded list.
 */
async function dashboardArticlesSold(storeId, period, from, to, limit = 8) {
  const { start, end } = resolvePeriod(period, from, to);

  const [rows] = await pool.query(
    `SELECT si.product_id, p.name,
            SUM(si.quantity) AS quantity_sold,
            COALESCE(SUM(si.subtotal), 0) AS revenue
       FROM sale_items si
       JOIN sales s ON s.id = si.sale_id
       JOIN products p ON p.id = si.product_id
      WHERE s.store_id = ? AND s.occurred_at BETWEEN ? AND ? AND s.sale_status = 'COMPLETED'
      GROUP BY si.product_id, p.name
      ORDER BY quantity_sold DESC
      LIMIT ?`,
    [storeId, start, end, limit]
  );

  return {
    period,
    range: { from: start, to: end },
    articles: rows.map((row) => ({
      product_id: row.product_id,
      name: row.name,
      quantity_sold: Number(row.quantity_sold) || 0,
      revenue: String(row.revenue),
    })),
  };
}

/**
 * "Statut des ventes" bar chart. Uses `sales.sale_status` as-is —
 * COMPLETED / CANCELLED / REFUNDED (see migrations/001_init.sql) — with
 * no invented "pending" bucket, since sale_status has no such value in
 * this schema (that concept only exists on `payment_status`, which is
 * covered by [salesSummary]'s `status_summary`, a different chart).
 * Every status the enum defines is always present in the response
 * (zero-filled) so the chart never has to guess whether a missing key
 * means zero or means "not fetched yet".
 */
async function dashboardSalesStatus(storeId, period, from, to) {
  const { start, end } = resolvePeriod(period, from, to);

  const [rows] = await pool.query(
    `SELECT sale_status, COUNT(*) AS count
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ?
      GROUP BY sale_status`,
    [storeId, start, end]
  );

  const counts = { COMPLETED: 0, CANCELLED: 0, REFUNDED: 0 };
  rows.forEach((row) => {
    if (row.sale_status in counts) counts[row.sale_status] = Number(row.count) || 0;
  });

  return {
    period,
    range: { from: start, to: end },
    statuses: Object.entries(counts).map(([status, count]) => ({ status, count })),
  };
}

function pad2(n) {
  return String(n).padStart(2, '0');
}

function hourBucketKey(date) {
  const d = new Date(date);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:00:00`;
}

function dayBucketKey(date) {
  const d = new Date(date);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

function monthBucketKey(date) {
  const d = new Date(date);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-01`;
}

/**
 * Revenue evolution chart for an arbitrary [start, end] range (Rapports
 * §7), zero-filled so every bucket in the range is present even where
 * there were no sales. `unit` is 'hour' | 'day' | 'month'.
 */
async function revenueSeriesForRange(storeId, start, end, unit) {
  const sqlExpr = {
    hour: "DATE_FORMAT(occurred_at, '%Y-%m-%d %H:00:00')",
    day: 'DATE(occurred_at)',
    month: "DATE_FORMAT(occurred_at, '%Y-%m-01')",
  }[unit];

  const [rows] = await pool.query(
    `SELECT ${sqlExpr} AS bucket_start, COALESCE(SUM(total), 0) AS revenue,
            COUNT(*) AS sale_count
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'
      GROUP BY bucket_start
      ORDER BY bucket_start ASC`,
    [storeId, start, end]
  );

  const keyFn = { hour: hourBucketKey, day: dayBucketKey, month: monthBucketKey }[unit];
  const byKey = new Map(rows.map((r) => [String(r.bucket_start), r]));

  const buckets = [];
  const cursor = new Date(start);
  const stepMs = { hour: 60 * 60 * 1000, day: 24 * 60 * 60 * 1000, month: null }[unit];

  if (unit === 'month') {
    const cur = new Date(start.getFullYear(), start.getMonth(), 1);
    const last = new Date(end.getFullYear(), end.getMonth(), 1);
    while (cur <= last) {
      const key = monthBucketKey(cur);
      const row = byKey.get(key);
      buckets.push({
        bucket_start: new Date(cur),
        revenue: row ? row.revenue : 0,
        sale_count: row ? Number(row.sale_count) : 0,
      });
      cur.setMonth(cur.getMonth() + 1);
    }
    return buckets;
  }

  // hour/day: safety cap so a mis-resolved multi-year custom range never
  // generates an unbounded number of buckets.
  const maxBuckets = 5000;
  let count = 0;
  while (cursor <= end && count < maxBuckets) {
    const key = keyFn(cursor);
    const row = byKey.get(key);
    buckets.push({
      bucket_start: new Date(cursor),
      revenue: row ? row.revenue : 0,
      sale_count: row ? Number(row.sale_count) : 0,
    });
    cursor.setTime(cursor.getTime() + stepMs);
    count += 1;
  }
  return buckets;
}

/**
 * Revenue bar/line chart series.
 *
 * Legacy behaviour (no `period` given — the Dashboard's Jour/Semaine/Mois
 * toggle): fixed rolling windows, exactly as before this change —
 *  - day:   last 7 calendar days
 *  - week:  last 8 ISO-ish weeks (Monday-start), bucketed by week start
 *  - month: last 12 calendar months
 *
 * New behaviour (Rapports §7, `period` given): buckets the SELECTED
 * period's own [start, end] range, auto-picking hourly / daily / monthly
 * grouping from how wide that range is (unless an explicit granularity
 * other than 'auto' is requested) — never a fixed rolling window
 * unrelated to what the manager actually filtered for.
 */
async function dashboardRevenueSeries(storeId, granularity, period, from, to) {
  if (period) {
    const { start, end } = resolveRange(period, from, to);
    const spanDays = (end.getTime() - start.getTime()) / (24 * 60 * 60 * 1000);

    let unit = granularity && granularity !== 'auto' ? granularity : null;
    if (!unit) {
      if (spanDays <= 1.5) unit = 'hour';
      else if (spanDays <= 35) unit = 'day';
      else unit = 'month';
    }
    // 'week' isn't one of revenueSeriesForRange's units (it only knows
    // hour/day/month) — an explicit 'week' granularity on a custom range
    // is downgraded to 'day' buckets, which is still a faithful, more
    // granular rendering of the same data.
    if (unit === 'week') unit = 'day';

    const buckets = await revenueSeriesForRange(storeId, start, end, unit);
    return { granularity: unit, range: { from: start, to: end }, buckets };
  }

  const now = new Date();

  if (granularity === 'month') {
    const start = new Date(now.getFullYear(), now.getMonth() - 11, 1, 0, 0, 0, 0);
    const [rows] = await pool.query(
      `SELECT DATE_FORMAT(occurred_at, '%Y-%m-01') AS bucket_start,
              COALESCE(SUM(total), 0) AS revenue
         FROM sales
        WHERE store_id = ? AND occurred_at >= ? AND sale_status = 'COMPLETED'
        GROUP BY bucket_start
        ORDER BY bucket_start ASC`,
      [storeId, start]
    );
    return { granularity, buckets: rows };
  }

  if (granularity === 'week') {
    const start = startOfDay(new Date(now.getTime() - 7 * 7 * 24 * 60 * 60 * 1000));
    const [rows] = await pool.query(
      `SELECT DATE(DATE_SUB(occurred_at, INTERVAL WEEKDAY(occurred_at) DAY)) AS bucket_start,
              COALESCE(SUM(total), 0) AS revenue
         FROM sales
        WHERE store_id = ? AND occurred_at >= ? AND sale_status = 'COMPLETED'
        GROUP BY bucket_start
        ORDER BY bucket_start ASC`,
      [storeId, start]
    );
    return { granularity, buckets: rows };
  }

  // day (default): last 7 calendar days, zero-filled so the chart always
  // shows 7 bars even on a brand-new store with no sales yet.
  const start = startOfDay(new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000));
  const [rows] = await pool.query(
    `SELECT DATE(occurred_at) AS bucket_start, COALESCE(SUM(total), 0) AS revenue
       FROM sales
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ? AND sale_status = 'COMPLETED'
      GROUP BY bucket_start
      ORDER BY bucket_start ASC`,
    [storeId, start, endOfDay(now)]
  );
  const byDate = new Map(rows.map((r) => [new Date(r.bucket_start).toDateString(), r.revenue]));
  const buckets = [];
  for (let i = 0; i < 7; i += 1) {
    const d = new Date(start.getTime() + i * 24 * 60 * 60 * 1000);
    buckets.push({ bucket_start: d, revenue: byDate.get(d.toDateString()) ?? 0 });
  }
  return { granularity, buckets };
}

/**
 * "Ventes récentes" list. `payment_method` is the most recent payment
 * row for the sale ('MIXED' when more than one distinct method was
 * used, NULL-safe for a sale that hasn't been paid yet) — payments is a
 * one-to-many table (spec: a sale can have more than one payment row).
 */
async function dashboardRecentSales(storeId, limit) {
  const [rows] = await pool.query(
    `SELECT s.id, s.total, s.sale_status, s.payment_status, s.occurred_at,
            u.name AS cashier_name,
            (SELECT COUNT(DISTINCT payment_method) FROM payments WHERE sale_id = s.id) AS method_count,
            (SELECT payment_method FROM payments WHERE sale_id = s.id ORDER BY created_at DESC LIMIT 1) AS last_payment_method
       FROM sales s
       LEFT JOIN users u ON u.id = s.user_id
      WHERE s.store_id = ?
      ORDER BY s.occurred_at DESC
      LIMIT ?`,
    [storeId, limit]
  );

  return {
    sales: rows.map((row) => ({
      id: row.id,
      total: String(row.total),
      sale_status: row.sale_status,
      payment_status: row.payment_status,
      occurred_at: row.occurred_at,
      cashier_name: row.cashier_name,
      payment_method: Number(row.method_count) > 1 ? 'MIXED' : row.last_payment_method,
    })),
  };
}

module.exports = {
  resolveRange,
  salesSummary,
  topProducts,
  expensesSummary,
  lowStock,
  stockReport,
  cashierSalesReport,
  dashboard,
  dashboardOverview,
  dashboardCashierRanking,
  dashboardArticlesSold,
  dashboardSalesStatus,
  dashboardRevenueSeries,
  dashboardRecentSales,
};
