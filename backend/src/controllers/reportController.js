const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/apiResponse');
const reportService = require('../services/reportService');
const reportOverviewService = require('../services/reportOverviewService');

const sales = asyncHandler(async (req, res) => {
  const result = await reportService.salesSummary(req.user.storeId, req.query);
  ok(res, result);
});

const topProducts = asyncHandler(async (req, res) => {
  const result = await reportService.topProducts(req.user.storeId, {
    ...req.query,
    limit: req.query.limit ? parseInt(req.query.limit, 10) : undefined,
  });
  ok(res, { products: result });
});

const expenses = asyncHandler(async (req, res) => {
  const result = await reportService.expensesSummary(req.user.storeId, req.query);
  ok(res, result);
});

const lowStock = asyncHandler(async (req, res) => {
  const result = await reportService.lowStock(req.user.storeId, {
    threshold: req.query.threshold ? parseInt(req.query.threshold, 10) : undefined,
  });
  ok(res, { products: result });
});

// Rapports §14 "État du stock" — products AND ingredients, low stock and
// out-of-stock, in one response (see reportService.stockReport).
const stock = asyncHandler(async (req, res) => {
  const result = await reportService.stockReport(req.user.storeId, {
    threshold: req.query.threshold ? parseInt(req.query.threshold, 10) : undefined,
  });
  ok(res, result);
});

const cashierSales = asyncHandler(async (req, res) => {
  const result = await reportService.cashierSalesReport(req.user.storeId, req.query);
  ok(res, result);
});

const dashboard = asyncHandler(async (req, res) => {
  const result = await reportService.dashboard(req.user.storeId);
  ok(res, result);
});

// --- Accueil / Dashboard AND Rapports (shared period-aware endpoints) ---

const dashboardOverview = asyncHandler(async (req, res) => {
  const result = await reportService.dashboardOverview(
    req.user.storeId,
    req.query.period,
    req.query.from,
    req.query.to
  );
  ok(res, result);
});

const dashboardCashierRanking = asyncHandler(async (req, res) => {
  const result = await reportService.dashboardCashierRanking(
    req.user.storeId,
    req.query.period,
    req.query.from,
    req.query.to
  );
  ok(res, result);
});

const dashboardArticlesSold = asyncHandler(async (req, res) => {
  const result = await reportService.dashboardArticlesSold(
    req.user.storeId,
    req.query.period,
    req.query.from,
    req.query.to,
    req.query.limit
  );
  ok(res, result);
});

const dashboardSalesStatus = asyncHandler(async (req, res) => {
  const result = await reportService.dashboardSalesStatus(
    req.user.storeId,
    req.query.period,
    req.query.from,
    req.query.to
  );
  ok(res, result);
});

const dashboardRevenueSeries = asyncHandler(async (req, res) => {
  const result = await reportService.dashboardRevenueSeries(
    req.user.storeId,
    req.query.granularity,
    req.query.period,
    req.query.from,
    req.query.to
  );
  ok(res, result);
});

const dashboardRecentSales = asyncHandler(async (req, res) => {
  const result = await reportService.dashboardRecentSales(req.user.storeId, req.query.limit);
  ok(res, result);
});

// --- Rapports: one consistent payload for screen + PDF + Excel ---

const overview = asyncHandler(async (req, res) => {
  const result = await reportOverviewService.reportOverview(req.user.storeId, {
    period: req.query.period,
    from: req.query.from,
    to: req.query.to,
    includeSales: req.query.include_sales,
    recentLimit: req.query.recent_limit,
  });
  ok(res, result);
});

const ordersByHour = asyncHandler(async (req, res) => {
  const result = await reportOverviewService.ordersByHour(req.user.storeId, {
    period: req.query.period,
    from: req.query.from,
    to: req.query.to,
  });
  ok(res, result);
});

module.exports = {
  overview,
  ordersByHour,
  sales,
  topProducts,
  expenses,
  lowStock,
  stock,
  cashierSales,
  dashboard,
  dashboardOverview,
  dashboardCashierRanking,
  dashboardArticlesSold,
  dashboardSalesStatus,
  dashboardRevenueSeries,
  dashboardRecentSales,
};
