const express = require('express');
const controller = require('../controllers/reportController');
const validate = require('../middleware/validate');
const {
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
} = require('../validators/reportValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

const router = express.Router();

router.use(requireAuth, requirePermission('reports.view'));

// Sales Summary + Payment Analysis (Rapports §8/§9). Accepts either a
// named `period` or the original from/to-only contract.
router.get('/sales', validate(salesSummaryQuery, 'query'), controller.sales);
// Top produits (Rapports §12) / also backs the legacy Dashboard top-5.
router.get('/top-products', validate(topProductsQuery, 'query'), controller.topProducts);
// Dépenses (Rapports §13).
router.get('/expenses', validate(expensesQuery, 'query'), controller.expenses);
// Kept for backward compatibility (products only, default threshold=5).
router.get('/low-stock', validate(stockQuery, 'query'), controller.lowStock);
// État du stock (Rapports §14) — products AND ingredients together.
router.get('/stock', validate(stockQuery, 'query'), controller.stock);

// Cashiers screen → "Sales Report" (Day/Month) AND Rapports → cashier
// detail drill-down (spec §11). `reports.view` already restricts this to
// admin/manager (see authorize.js's ROLE_PERMISSIONS) — a cashier role
// keeps using GET /sales for its own receipts instead.
router.get('/cashier-sales', validate(cashierSalesQuery, 'query'), controller.cashierSales);

// Legacy "today vs yesterday" dashboard summary (kept unchanged).
router.get('/dashboard', controller.dashboard);

// Accueil / Dashboard AND Rapports — period-aware KPIs, cashier ranking,
// sales status chart, revenue chart and recent sales. Kept under
// /reports (this project's existing convention for read-only aggregates)
// rather than a new /dashboard or /rapports prefix — see
// reportService.js's resolveRange for why these are shared rather than
// duplicated per-screen.
router.get(
  '/dashboard-overview',
  validate(dashboardPeriodQuery, 'query'),
  controller.dashboardOverview
);
router.get(
  '/dashboard-cashiers',
  validate(dashboardPeriodQuery, 'query'),
  controller.dashboardCashierRanking
);
// "Articles vendus aujourd'hui" / Rapports "Articles les plus vendus" —
// top products by quantity sold in the selected period (spec §5/§9/§12).
router.get(
  '/dashboard-articles',
  validate(dashboardArticlesQuery, 'query'),
  controller.dashboardArticlesSold
);
router.get(
  '/dashboard-sales-status',
  validate(dashboardPeriodQuery, 'query'),
  controller.dashboardSalesStatus
);
router.get(
  '/dashboard-revenue',
  validate(dashboardRevenueQuery, 'query'),
  controller.dashboardRevenueSeries
);
router.get(
  '/dashboard-recent-sales',
  validate(dashboardRecentSalesQuery, 'query'),
  controller.dashboardRecentSales
);

// Rapports screen / PDF / Excel / Print — ONE consistent payload (KPIs,
// revenue chart, orders per hour, payments, cashiers, products, expenses,
// alerts, recent sales) computed from a single snapshot for one period,
// so every export shows exactly what the screen shows. See
// reportOverviewService.js for the counting rules.
router.get('/overview', validate(overviewQuery, 'query'), controller.overview);
// "Commandes par heure" on its own (same computation the overview embeds).
router.get('/orders-by-hour', validate(dashboardPeriodQuery, 'query'), controller.ordersByHour);

module.exports = router;
