const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const saleService = require('../services/saleService');

const create = asyncHandler(async (req, res) => {
  const { sale, wasDuplicate } = await saleService.addPayment(req.user.storeId, req.user.id, req.body);
  if (wasDuplicate) return ok(res, { sale, was_duplicate: true });
  created(res, { sale, was_duplicate: false });
});

module.exports = { create };
