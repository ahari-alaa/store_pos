const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const ingredientService = require('../services/ingredientService');
const recipeService = require('../services/recipeService');

const list = asyncHandler(async (req, res) => {
  const ingredients = await ingredientService.list(req.user.storeId, req.query);
  ok(res, { ingredients });
});

const getById = asyncHandler(async (req, res) => {
  const ingredient = await ingredientService.getById(req.user.storeId, req.params.id);
  ok(res, { ingredient });
});

const create = asyncHandler(async (req, res) => {
  const ingredient = await ingredientService.create(req.user.storeId, req.body);
  created(res, { ingredient });
});

const update = asyncHandler(async (req, res) => {
  const ingredient = await ingredientService.update(req.user.storeId, req.params.id, req.body);
  ok(res, { ingredient });
});

const remove = asyncHandler(async (req, res) => {
  const result = await ingredientService.remove(req.user.storeId, req.params.id);
  ok(res, result);
});

// "Désactiver" (spec §13) — the safe fallback offered by the UI when a
// hard delete is blocked because the ingredient is in use or has history.
const deactivate = asyncHandler(async (req, res) => {
  const ingredient = await ingredientService.deactivate(req.user.storeId, req.params.id);
  ok(res, { ingredient });
});

const addMovement = asyncHandler(async (req, res) => {
  const ingredient = await ingredientService.addMovement(
    req.user.storeId,
    req.params.id,
    req.body
  );
  created(res, { ingredient });
});

const movements = asyncHandler(async (req, res) => {
  const rows = await ingredientService.movements(req.user.storeId, req.params.id, req.query);
  ok(res, { movements: rows });
});

const lowStock = asyncHandler(async (req, res) => {
  const ingredients = await ingredientService.lowStock(req.user.storeId);
  ok(res, { ingredients });
});

// "Used in" list for the Supply Detail screen (spec §23) — which products'
// recipes consume this ingredient, and how much per unit.
const usedInProducts = asyncHandler(async (req, res) => {
  const products = await recipeService.productsUsingIngredient(req.user.storeId, req.params.id);
  ok(res, { products });
});

module.exports = {
  list,
  getById,
  create,
  update,
  remove,
  deactivate,
  addMovement,
  movements,
  lowStock,
  usedInProducts,
};
