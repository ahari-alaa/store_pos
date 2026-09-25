const express = require('express');
const controller = require('../controllers/adminCashierSettlementController');
const validate = require('../middleware/validate');
const {
  settlementIdParam,
  adminSettlementsQuery,
  cancelSettlement,
} = require('../validators/cashierSettlementValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

/**
 * "Paiements caissiers" / "Règlements caissiers" — admin/manager only
 * (spec §22-§23, §26, §33). A cashier role never has
 * 'cashier_settlements.view'/'manage' (see authorize.js), so every route
 * here is refused for a cashier regardless of what the Flutter UI shows.
 *
 * Mounted at /admin/cashier-settlements.
 */
const router = express.Router();

router.use(requireAuth);

router.get(
  '/',
  requirePermission('cashier_settlements.view'),
  validate(adminSettlementsQuery, 'query'),
  controller.list
);
router.get(
  '/:id',
  requirePermission('cashier_settlements.view'),
  validate(settlementIdParam, 'params'),
  controller.getById
);
// "MARQUER COMME PAYÉ" — spec §23.
router.post(
  '/:id/mark-paid',
  requirePermission('cashier_settlements.manage'),
  validate(settlementIdParam, 'params'),
  controller.markPaid
);
// Cancellation keeps full history (spec §33) — never deletes.
router.post(
  '/:id/cancel',
  requirePermission('cashier_settlements.manage'),
  validate(settlementIdParam, 'params'),
  validate(cancelSettlement),
  controller.cancel
);
// "RÉIMPRIMER UNE COPIE" — admin-only duplicate (spec §26).
router.post(
  '/:id/reprint',
  requirePermission('cashier_settlements.manage'),
  validate(settlementIdParam, 'params'),
  controller.reprint
);

module.exports = router;
