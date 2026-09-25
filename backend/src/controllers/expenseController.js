const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const ApiError = require('../utils/ApiError');
const expenseService = require('../services/expenseService');
const { expenseReceiptUrl } = require('../middleware/upload');

const list = asyncHandler(async (req, res) => {
  const result = await expenseService.list(req.user.storeId, req.query);
  ok(res, result);
});

const feed = asyncHandler(async (req, res) => {
  const result = await expenseService.feed(req.user.storeId, req.query);
  ok(res, result);
});

const getOne = asyncHandler(async (req, res) => {
  const expense = await expenseService.getById(req.user.storeId, req.params.id);
  ok(res, { expense });
});

const create = asyncHandler(async (req, res) => {
  const { expense, wasDuplicate } = await expenseService.create(
    req.user.storeId,
    req.user.id,
    req.body
  );
  if (wasDuplicate) return ok(res, { expense, was_duplicate: true });
  created(res, { expense, was_duplicate: false });
});

const update = asyncHandler(async (req, res) => {
  const expense = await expenseService.update(req.user.storeId, req.params.id, req.body);
  ok(res, { expense });
});

const remove = asyncHandler(async (req, res) => {
  await expenseService.remove(req.user.storeId, req.params.id);
  ok(res, { deleted: true });
});

const monthlyReport = asyncHandler(async (req, res) => {
  const year = parseInt(req.query.year, 10);
  const month = parseInt(req.query.month, 10);
  const result = await expenseService.monthlyReport(req.user.storeId, year, month);
  ok(res, result);
});

const recurringSuggestions = asyncHandler(async (req, res) => {
  const year = parseInt(req.query.year, 10);
  const month = parseInt(req.query.month, 10);
  const suggestions = await expenseService.recurringSuggestions(req.user.storeId, year, month);
  ok(res, { suggestions });
});

const listCategories = asyncHandler(async (req, res) => {
  const categories = await expenseService.listCategories(req.user.storeId, req.query);
  ok(res, { categories });
});

const createCategory = asyncHandler(async (req, res) => {
  const category = await expenseService.createCategory(req.user.storeId, req.body);
  created(res, { category });
});

const updateCategory = asyncHandler(async (req, res) => {
  const category = await expenseService.updateCategory(req.user.storeId, req.params.id, req.body);
  ok(res, { category });
});

const deactivateCategory = asyncHandler(async (req, res) => {
  await expenseService.deactivateCategory(req.user.storeId, req.params.id);
  ok(res, { deactivated: true });
});

// Existence check runs BEFORE multer parses the multipart body (see
// expenseRoutes.js), so a bad/foreign expense id never gets a receipt
// file written to disk for nothing — mirrors productRoutes' image
// upload guard.
const uploadReceipt = asyncHandler(async (req, res) => {
  if (!req.file) throw ApiError.badRequest('No receipt file was uploaded', 'NO_FILE');
  const expense = await expenseService.setReceipt(
    req.user.storeId,
    req.params.id,
    expenseReceiptUrl(req.file.filename)
  );
  ok(res, { expense });
});

const removeReceipt = asyncHandler(async (req, res) => {
  const expense = await expenseService.removeReceipt(req.user.storeId, req.params.id);
  ok(res, { expense });
});

module.exports = {
  list,
  getOne,
  create,
  update,
  remove,
  monthlyReport,
  recurringSuggestions,
  listCategories,
  createCategory,
  updateCategory,
  deactivateCategory,
  uploadReceipt,
  removeReceipt,
  feed,
};
