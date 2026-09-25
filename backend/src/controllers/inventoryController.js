const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const inventoryService = require('../services/inventoryService');

const list = asyncHandler(async (req, res) => {
  const movements = await inventoryService.listForStore(req.user.storeId, req.query);
  ok(res, { movements });
});

const listForProduct = asyncHandler(async (req, res) => {
  const movements = await inventoryService.listForProduct(
    req.user.storeId,
    req.params.productId,
    req.query
  );
  ok(res, { movements });
});

const adjust = asyncHandler(async (req, res) => {
  const { movement, wasDuplicate } = await inventoryService.adjust(req.user.storeId, req.body);
  if (wasDuplicate) return ok(res, { movement, was_duplicate: true });
  created(res, { movement, was_duplicate: false });
});

module.exports = { list, listForProduct, adjust };
