const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/apiResponse');
const settlementService = require('../services/cashierSettlementService');

// "Paiements caissiers" / "Règlements caissiers" (spec §22/§23). Every
// handler is gated by requirePermission('cashier_settlements.view'/'manage')
// in the route file — a cashier role never reaches these.

const list = asyncHandler(async (req, res) => {
  const result = await settlementService.adminList(req.user.storeId, {
    cashierId: req.query.cashier_id,
    status: req.query.status,
    from: req.query.from,
    to: req.query.to,
    page: req.query.page,
    pageSize: req.query.page_size,
  });
  ok(res, result);
});

const getById = asyncHandler(async (req, res) => {
  const settlement = await settlementService.getSettlementForAdmin(req.user.storeId, req.params.id);
  ok(res, { settlement });
});

// "MARQUER COMME PAYÉ" — the cashier's WORK payment, never the customer's
// payment status. `paid_by` is always req.user.id (see service).
const markPaid = asyncHandler(async (req, res) => {
  const settlement = await settlementService.markPaid(req.user.storeId, req.user, req.params.id);
  ok(res, { settlement });
});

const cancel = asyncHandler(async (req, res) => {
  const settlement = await settlementService.cancelSettlement(
    req.user.storeId,
    req.user,
    req.params.id,
    req.body.reason
  );
  ok(res, { settlement });
});

// "RÉIMPRIMER UNE COPIE" — admin-only duplicate (spec §26). The client
// must render this clearly marked COPIE / DUPLICATA.
const reprint = asyncHandler(async (req, res) => {
  const settlement = await settlementService.adminReprint(req.user.storeId, req.user, req.params.id);
  ok(res, { settlement, copy: true });
});

module.exports = { list, getById, markPaid, cancel, reprint };
