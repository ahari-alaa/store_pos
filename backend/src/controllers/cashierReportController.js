const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/apiResponse');
const cashierReportService = require('../services/cashierReportService');

// Both handlers pass req.user — the cashier is NEVER read from the request
// body/query/params.
const mySales = asyncHandler(async (req, res) => {
  const result = await cashierReportService.myReport(req.user.storeId, req.user, {
    period: req.query.period,
    from: req.query.from,
    to: req.query.to,
    includeOrders: req.query.include_orders,
  });
  ok(res, result);
});

const myOrders = asyncHandler(async (req, res) => {
  const result = await cashierReportService.myOrders(req.user.storeId, req.user.id, {
    period: req.query.period,
    from: req.query.from,
    to: req.query.to,
    serveStatus: req.query.serve_status,
    paymentStatus: req.query.payment_status,
    search: req.query.search,
    page: req.query.page,
    pageSize: req.query.page_size,
  });
  ok(res, result);
});

module.exports = { mySales, myOrders };
