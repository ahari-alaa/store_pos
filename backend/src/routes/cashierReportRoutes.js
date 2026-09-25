const express = require('express');
const controller = require('../controllers/cashierReportController');
const validate = require('../middleware/validate');
const { myReportQuery, myOrdersQuery } = require('../validators/reportValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

/**
 * The cashier's PERSONAL report + order queue.
 *
 * Kept in its own router (mounted BEFORE reportRoutes in routes/index.js)
 * because reportRoutes gates everything behind 'reports.view'
 * (admin/manager). Auth is applied per route here, not with router.use, so
 * requests for any other /reports/* path fall through untouched to
 * reportRoutes and are still rejected for a cashier there.
 *
 * Neither endpoint takes a cashier id: the cashier is req.user.id.
 */
const router = express.Router();

router.get(
  '/my-sales',
  requireAuth,
  requirePermission('reports.view_own'),
  validate(myReportQuery, 'query'),
  controller.mySales
);
router.get(
  '/my-orders',
  requireAuth,
  requirePermission('sales.view_own'),
  validate(myOrdersQuery, 'query'),
  controller.myOrders
);

module.exports = router;
