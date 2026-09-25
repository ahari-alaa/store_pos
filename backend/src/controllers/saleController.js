const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const saleService = require('../services/saleService');
const ApiError = require('../utils/ApiError');

const create = asyncHandler(async (req, res) => {
  const { sale, wasDuplicate } = await saleService.createSale(
    req.user.storeId,
    req.user.id,
    req.body
  );
  // 200 for a de-duplicated retry, 201 for a genuinely new sale — lets the
  // Flutter sync client tell the two apart if it ever needs to.
  if (wasDuplicate) {
    return ok(res, { sale, was_duplicate: true });
  }
  created(res, { sale, was_duplicate: false });
});

const getById = asyncHandler(async (req, res) => {
  const sale = await saleService.getById(req.user.storeId, req.params.id);
  if (req.user.role === 'cashier' && sale.user_id !== req.user.id) {
    throw ApiError.forbidden('You can only view your own sales', 'ROLE_NOT_ALLOWED');
  }
  ok(res, { sale });
});

const list = asyncHandler(async (req, res) => {
  // Cashiers only see their own sales (spec section 9: "View permitted
  // sales"); managers/admins can see the whole store, optionally filtered
  // by user_id via the query string.
  const query = req.user.role === 'cashier' ? { ...req.query, user_id: req.user.id } : req.query;
  const result = await saleService.list(req.user.storeId, query);
  ok(res, result);
});

// The cashier is ALWAYS req.user (verified JWT). There is deliberately no
// body/query field to name another cashier.
const serve = asyncHandler(async (req, res) => {
  const { sale, alreadyApplied } = await saleService.serveSale(
    req.user.storeId,
    req.user,
    req.params.id,
    { clientOperationId: req.body && req.body.client_operation_id }
  );
  ok(res, { sale, already_applied: alreadyApplied });
});

const reprint = asyncHandler(async (req, res) => {
  const { sale } = await saleService.reprintSale(req.user.storeId, req.user, req.params.id);
  ok(res, { sale });
});

module.exports = { create, getById, list, serve, reprint };
