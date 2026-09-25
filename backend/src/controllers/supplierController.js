const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const supplierService = require('../services/supplierService');

const list = asyncHandler(async (req, res) => {
  const result = await supplierService.list(req.user.storeId, req.query);
  ok(res, result);
});

const getById = asyncHandler(async (req, res) => {
  const supplier = await supplierService.getById(req.user.storeId, req.params.id);
  ok(res, { supplier });
});

const create = asyncHandler(async (req, res) => {
  const supplier = await supplierService.create(req.user.storeId, req.body);
  created(res, { supplier });
});

const update = asyncHandler(async (req, res) => {
  const supplier = await supplierService.update(req.user.storeId, req.params.id, req.body);
  ok(res, { supplier });
});

const remove = asyncHandler(async (req, res) => {
  await supplierService.remove(req.user.storeId, req.params.id);
  ok(res, { deleted: true });
});

module.exports = { list, getById, create, update, remove };
