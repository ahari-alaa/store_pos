const Joi = require('joi');

// Accepts either a plain date ('2026-09-01') or a naive local datetime
// ('2026-09-01 00:00:00' / '2026-09-01T00:00:00') — deliberately NOT
// `Joi.string().isoDate()` with a 'Z'/offset suffix, because `occurred_at`
// is stored (and everywhere else in this app, read back) as a naive local
// timestamp with no timezone conversion applied (see saleService.createSale
// and Sale.occurredAt on the Flutter side). Accepting the same shape here
// keeps the report's day boundaries lined up with how a sale is actually
// classified into a calendar day elsewhere in the app (spec section 15).
const localDateTime = Joi.string().pattern(
  /^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}:\d{2})?$/
);

// ---------------------------------------------------------------------
// Shared "period" vocabulary for the whole Reports module (Rapports +
// Accueil/Dashboard). A single named period covers every quick filter
// the Rapports screen's spec asks for (Aujourd'hui / Hier / Cette semaine /
// Semaine précédente / Ce mois / Mois précédent); 'custom' is the escape
// hatch for an explicit [from, to] range picked on the date pickers.
// Kept as ONE enum (instead of a Rapports-only copy) so every endpoint
// below — old and new — resolves periods identically (reportService.js
// resolveRange), never two slightly different definitions of "this week".
// ---------------------------------------------------------------------
const REPORT_PERIODS = ['today', 'yesterday', 'week', 'last_week', 'month', 'last_month', 'custom'];

const cashierSalesQuery = Joi.object({
  cashier_id: Joi.string().uuid().required(),
  // Either a named period, or an explicit from/to range — reportService
  // enforces that at least one of the two is usable (falls back to
  // requiring from/to when period is omitted, matching this endpoint's
  // original contract used by the Cashiers screen's Day/Month report).
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  from: localDateTime.optional(),
  to: localDateTime.optional(),
  // 'day' returns a daily breakdown alongside the summary (Month report);
  // omitted entirely for the Day report, which only needs the summary.
  group_by: Joi.string().valid('day').optional(),
}).custom((value, helpers) => {
  if (!value.period && (!value.from || !value.to)) {
    return helpers.error('any.invalid');
  }
  if (value.period === 'custom' && (!value.from || !value.to)) {
    return helpers.error('any.invalid');
  }
  return value;
}, 'period-or-range').messages({
  'any.invalid': '"from" and "to" are required when "period" is omitted or "custom"',
});

// --- Accueil / Dashboard AND Rapports (see reportService.js#resolveRange) ---
//
// The same schema now backs both the Dashboard's period selector (which
// only ever sends 'today' | 'week' | 'month') and the new Rapports
// screen's full quick-period bar plus its custom date range — one
// contract, so a period never resolves differently depending on which
// screen asked for it.

const dashboardPeriodQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).default('today'),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
});

const dashboardRevenueQuery = Joi.object({
  // 'auto' (default when a period/range is supplied) picks hourly/daily/
  // monthly buckets from the span of the resolved range (spec §7). An
  // explicit day/week/month keeps the legacy fixed rolling-window
  // behaviour the Dashboard's Jour/Semaine/Mois toggle already relies on.
  granularity: Joi.string().valid('day', 'week', 'month', 'auto').default('day'),
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
});

const dashboardRecentSalesQuery = Joi.object({
  limit: Joi.number().integer().min(1).max(50).default(10),
});

const dashboardArticlesQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).default('today'),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  limit: Joi.number().integer().min(1).max(50).default(8),
});

// --- Rapports-specific reads (reuse the same period vocabulary) ---

// GET /reports/sales — Sales Summary + Payment Analysis (Rapports §8/§9).
// `period` is optional so the endpoint's original from/to-only contract
// keeps working unchanged for any existing caller; Rapports always sends
// a period (or 'custom' + from/to).
const salesSummaryQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
});

const topProductsQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  limit: Joi.number().integer().min(1).max(100).optional(),
});

const expensesQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
});

const stockQuery = Joi.object({
  threshold: Joi.number().integer().min(0).optional(),
});

// GET /reports/overview — the ONE payload behind the Rapports screen, its
// PDF, its Excel export and its Print button. Same period vocabulary as
// every other endpoint here (resolved by reportService.resolveRange).
// `include_sales` additionally returns the full sales list of the period
// (capped server-side) for the PDF/Excel "Ventes" sections; the screen
// itself never asks for it.
const overviewQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).default('today'),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  include_sales: Joi.boolean().default(false),
  recent_limit: Joi.number().integer().min(1).max(50).default(10),
});

// --- Cashier's personal report / order queue (cashierReportService.js) ---
//
// SECURITY: there is intentionally NO cashier_id / user_id field here. The
// cashier is always req.user.id. (`validate()` strips unknown keys, so a
// `?cashier_id=` sent by a client is discarded before it reaches a handler.)
const myReportQuery = Joi.object({
  period: Joi.string().valid(...REPORT_PERIODS).default('today'),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  // Full list of the period's orders, for the printed report only.
  include_orders: Joi.boolean().default(false),
});

const myOrdersQuery = Joi.object({
  // Optional: no period = no date bound (what the "À servir" queue wants).
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  from: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  to: localDateTime.when('period', { is: 'custom', then: Joi.required(), otherwise: Joi.optional() }),
  serve_status: Joi.string().valid('all', 'to_serve', 'served').default('all'),
  // UNPAID = PENDING + PARTIALLY_PAID ("Non payées").
  payment_status: Joi.string().valid('PENDING', 'PARTIALLY_PAID', 'PAID', 'UNPAID').optional(),
  search: Joi.string().max(40).allow('', null).optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(100).default(50),
});

module.exports = {
  REPORT_PERIODS,
  myReportQuery,
  myOrdersQuery,
  cashierSalesQuery,
  dashboardPeriodQuery,
  dashboardRevenueQuery,
  dashboardRecentSalesQuery,
  dashboardArticlesQuery,
  salesSummaryQuery,
  topProductsQuery,
  expensesQuery,
  stockQuery,
  overviewQuery,
};
