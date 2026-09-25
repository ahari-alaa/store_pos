const express = require('express');
const controller = require('../controllers/cashierSettlementController');
const validate = require('../middleware/validate');
const {
  createSettlement,
  settlementIdParam,
  mySettlementsQuery,
} = require('../validators/cashierSettlementValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

/**
 * The cashier's OWN work-payment justificatifs (spec §1-§21). Every
 * handler resolves the cashier from req.user — see
 * cashierSettlementController.js and cashierSettlementService.js.
 *
 * Mounted at /cashier-settlements, BEFORE the admin router
 * (adminCashierSettlementRoutes, mounted at /admin/cashier-settlements),
 * so the two never collide.
 */
const router = express.Router();

router.use(requireAuth, requirePermission('cashier_settlements.manage_own'));

// "Commandes à justifier" — spec §18.
router.get('/eligible-orders', controller.eligibleOrders);
// KPI header (Commandes réalisées / déjà justifiées / disponibles / à payer) — spec §28.
router.get('/my-summary', controller.mySummary);
// "Commandes déjà justifiées", grouped by settlement — spec §18.
router.get('/my', validate(mySettlementsQuery, 'query'), controller.mySettlements);

// "IMPRIMER LE JUSTIFICATIF" — spec §6.
router.post('/', validate(createSettlement), controller.create);

router.get('/:id', validate(settlementIdParam, 'params'), controller.getById);
// "VOIR LE JUSTIFICATIF" — never "RÉIMPRIMER" (spec §20/§21: no cashier
// reprint route exists anywhere in this file).
router.get('/:id/proof', validate(settlementIdParam, 'params'), controller.proof);

module.exports = router;
