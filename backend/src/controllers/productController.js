const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const productService = require('../services/productService');
const { productImageUrl } = require('../middleware/upload');
const ApiError = require('../utils/ApiError');

// A cashier needs the catalogue to ring up sales (name, price, stock, image)
// but not what the store PAYS for it: the purchase `cost` is management
// data, so it is removed from cashier responses on the server (hiding it in
// the Flutter UI alone would leave it readable through the API).
function forRole(role, product) {
  if (role !== 'cashier' || !product) return product;
  const { cost, ...rest } = product; // eslint-disable-line no-unused-vars
  return rest;
}

const list = asyncHandler(async (req, res) => {
  const result = await productService.list(req.user.storeId, req.query);
  ok(res, { ...result, items: result.items.map((p) => forRole(req.user.role, p)) });
});

const getById = asyncHandler(async (req, res) => {
  const product = await productService.getById(req.user.storeId, req.params.id);
  ok(res, { product: forRole(req.user.role, product) });
});

const create = asyncHandler(async (req, res) => {
  const product = await productService.create(req.user.storeId, req.body);
  created(res, { product });
});

const update = asyncHandler(async (req, res) => {
  const product = await productService.update(req.user.storeId, req.params.id, req.body);
  ok(res, { product });
});

const remove = asyncHandler(async (req, res) => {
  const result = await productService.remove(req.user.storeId, req.params.id);
  ok(res, result);
});

// multer's fileFilter rejection and "no file sent" are both plain request
// errors, not a fact about the product — kept here rather than in
// productService, which only deals with already-validated data.
const uploadImage = asyncHandler(async (req, res) => {
  if (!req.file) {
    throw ApiError.badRequest('No image file was uploaded', 'NO_FILE');
  }
  const product = await productService.setImage(
    req.user.storeId,
    req.params.id,
    productImageUrl(req.file.filename)
  );
  ok(res, { product });
});

// Runs BEFORE the multer middleware in the route chain, so a bad/foreign
// product id is rejected before anything is written to disk.
const ensureProductExists = asyncHandler(async (req, res, next) => {
  await productService.assertExists(req.user.storeId, req.params.id);
  next();
});

const removeImage = asyncHandler(async (req, res) => {
  const product = await productService.removeImage(req.user.storeId, req.params.id);
  ok(res, { product });
});

module.exports = {
  list,
  getById,
  create,
  update,
  remove,
  uploadImage,
  removeImage,
  ensureProductExists,
};
