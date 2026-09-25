const asyncHandler = require('../utils/asyncHandler');
const { ok } = require('../utils/apiResponse');
const recipeService = require('../services/recipeService');

const getForProduct = asyncHandler(async (req, res) => {
  const recipe = await recipeService.getForProduct(req.user.storeId, req.params.id);
  ok(res, { recipe });
});

const setForProduct = asyncHandler(async (req, res) => {
  const recipe = await recipeService.setForProduct(req.user.storeId, req.params.id, req.body.lines);
  ok(res, { recipe });
});

const addLine = asyncHandler(async (req, res) => {
  const recipe = await recipeService.addLine(req.user.storeId, req.params.id, {
    ingredientId: req.body.ingredient_id,
    quantity: req.body.quantity,
    unit: req.body.unit,
  });
  ok(res, { recipe });
});

const updateLine = asyncHandler(async (req, res) => {
  const recipe = await recipeService.updateLine(
    req.user.storeId,
    req.params.id,
    req.params.ingredientId,
    { quantity: req.body.quantity, unit: req.body.unit }
  );
  ok(res, { recipe });
});

const removeLine = asyncHandler(async (req, res) => {
  const recipe = await recipeService.removeLine(
    req.user.storeId,
    req.params.id,
    req.params.ingredientId
  );
  ok(res, { recipe });
});

module.exports = { getForProduct, setForProduct, addLine, updateLine, removeLine };
