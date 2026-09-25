const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const settlementService = require('../services/cashierSettlementService');

// Every handler below uses req.user (verified JWT) as the cashier. There is
// no route in this file that accepts a cashier id from the client.

const eligibleOrders = asyncHandler(async (req, res) => {
  const result = await settlementService.eligibleOrders(req.user.storeId, req.user.id);
  ok(res, result);
});

const mySummary = asyncHandler(async (req, res) => {
  const result = await settlementService.mySummary(req.user.storeId, req.user.id);
  ok(res, result);
});

const mySettlements = asyncHandler(async (req, res) => {
  const result = await settlementService.mySettlements(req.user.storeId, req.user.id, {
    status: req.query.status,
    page: req.query.page,
    pageSize: req.query.page_size,
  });
  ok(res, result);
});

// "IMPRIMER LE JUSTIFICATIF" — creates the settlement. See
// cashierSettlementService.createSettlement for the transaction/validation
// this wraps (spec §6/§10/§13/§25).
const create = asyncHandler(async (req, res) => {
  const settlement = await settlementService.createSettlement(
    req.user.storeId,
    req.user,
    req.body.sale_ids
  );
  created(res, { settlement });
});

const getById = asyncHandler(async (req, res) => {
  const settlement = await settlementService.getSettlementForCashier(
    req.user.storeId,
    req.user,
    req.params.id
  );
  ok(res, { settlement });
});

// "VOIR LE JUSTIFICATIF" — same payload as getById; kept as a separate,
// explicitly named route so the client never has a "reprint" URL for the
// cashier role to accidentally call (spec §20/§21 — VOIR yes, IMPRIMER no).
const proof = asyncHandler(async (req, res) => {
  const settlement = await settlementService.getSettlementForCashier(
    req.user.storeId,
    req.user,
    req.params.id
  );
  ok(res, { settlement, copy: false });
});

module.exports = { eligibleOrders, mySummary, mySettlements, create, getById, proof };
