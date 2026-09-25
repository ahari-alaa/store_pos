const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/apiResponse');
const syncService = require('../services/syncService');

const push = asyncHandler(async (req, res) => {
  const { results, summary } = await syncService.pushOperations(
    req.user.storeId,
    req.user,
    req.body.operations
  );
  ok(res, { results, summary });
});

const status = asyncHandler(async (req, res) => {
  const result = await syncService.getStatus(req.user.storeId);
  ok(res, result);
});

module.exports = { push, status };
