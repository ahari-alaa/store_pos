const ApiError = require('../utils/ApiError');
const recipeRepository = require('../repositories/recipeRepository');
const productRepository = require('../repositories/productRepository');
const ingredientRepository = require('../repositories/ingredientRepository');
const { convertQuantity, isCompatible } = require('../utils/unitConversion');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * Possible production / yield for one recipe line (spec §13/§14):
 *   possible_units = floor(available_stock / quantity_required_per_unit)
 * Stock and the recipe quantity are normalized to the same unit first
 * (spec §8) — a line entered in `g` against an ingredient stocked in
 * `kg` is converted before dividing, never compared raw.
 *
 * Clamped to a minimum of 0 (spec §13/§14): stock_quantity itself can
 * never go negative going forward (ingredientRepository.adjustStock
 * enforces that atomically), but this stays defensive against any
 * legacy/negative value so the UI can never show something like
 * "-17000 units" again — negative stock always means "can't produce
 * any", never "produces a negative amount".
 */
function lineYield(line) {
  const stock = Number(line.ingredient_stock);
  const requiredInIngredientUnit = convertQuantity(
    Number(line.quantity),
    line.unit || line.ingredient_unit,
    line.ingredient_unit
  );
  if (requiredInIngredientUnit <= 0) return Infinity;
  return Math.max(0, Math.floor(stock / requiredInIngredientUnit));
}

/** Adds `possible_production` (min across all recipe lines) and
 * `limiting_ingredient` to a recipe response — the panel from spec §6/§27. */
function withYield(lines) {
  if (lines.length === 0) {
    return { possible_production: 0, limiting_ingredient: null };
  }
  let min = Infinity;
  let limiting = null;
  for (const line of lines) {
    const yieldForLine = lineYield(line);
    if (yieldForLine < min) {
      min = yieldForLine;
      limiting = line.ingredient_name;
    }
  }
  return {
    possible_production: Number.isFinite(min) ? min : 0,
    limiting_ingredient: limiting,
  };
}

function lineCost(line) {
  const qtyInIngredientUnit = convertQuantity(
    Number(line.quantity),
    line.unit || line.ingredient_unit,
    line.ingredient_unit
  );
  return qtyInIngredientUnit * Number(line.cost_per_unit);
}

/** Recipe lines + the "Coût de la recette" panel shown in Modifier le
 * produit: total ingredient cost, margin vs. sale price, margin %, plus
 * the possible-production / supply-availability numbers for the Product
 * Detail panel. */
async function getForProduct(storeId, productId) {
  const product = await productRepository.findById(storeId, productId);
  if (!product) throw ApiError.notFound('Product not found', 'PRODUCT_NOT_FOUND');

  const lines = await recipeRepository.listForProduct(storeId, productId);
  const ingredientsCost = round2(lines.reduce((sum, l) => sum + lineCost(l), 0));
  const price = Number(product.price);
  const margin = round2(price - ingredientsCost);
  const marginPercent = price > 0 ? Math.round((margin / price) * 100) : 0;
  const { possible_production, limiting_ingredient } = withYield(lines);

  return {
    product_id: productId,
    lines: lines.map((l) => ({
      ...l,
      possible_production: lineYield(l) === Infinity ? null : lineYield(l),
      line_cost: round2(lineCost(l)),
    })),
    ingredients_cost: ingredientsCost,
    sale_price: price,
    margin,
    margin_percent: marginPercent,
    possible_production,
    limiting_ingredient,
  };
}

async function assertValidLine(storeId, ingredientId, unit) {
  const ingredient = await ingredientRepository.findById(storeId, ingredientId);
  if (!ingredient) {
    throw ApiError.badRequest(`Ingredient ${ingredientId} not found in this store`, 'INVALID_INGREDIENT');
  }
  if (unit && !isCompatible(unit, ingredient.unit)) {
    throw ApiError.badRequest(
      `Recipe unit "${unit}" is not compatible with "${ingredient.name}"'s stock unit ("${ingredient.unit}")`,
      'INCOMPATIBLE_UNIT'
    );
  }
  return ingredient;
}

/** Replaces the whole recipe for a product. `lines` = [{ingredient_id, quantity, unit}]. */
async function setForProduct(storeId, productId, lines) {
  const product = await productRepository.findById(storeId, productId);
  if (!product) throw ApiError.notFound('Product not found', 'PRODUCT_NOT_FOUND');

  for (const line of lines) {
    await assertValidLine(storeId, line.ingredient_id, line.unit);
  }

  await recipeRepository.replaceForProduct(storeId, productId, lines);
  return getForProduct(storeId, productId);
}

/** Adds ONE supply to the recipe ("+ Add supply"). */
async function addLine(storeId, productId, { ingredientId, quantity, unit }) {
  const product = await productRepository.findById(storeId, productId);
  if (!product) throw ApiError.notFound('Product not found', 'PRODUCT_NOT_FOUND');
  await assertValidLine(storeId, ingredientId, unit);

  try {
    await recipeRepository.addLine(storeId, productId, { ingredientId, quantity, unit });
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      throw ApiError.conflict(
        'This supply is already on the recipe — edit it instead of adding it again.',
        'RECIPE_LINE_EXISTS'
      );
    }
    throw err;
  }
  return getForProduct(storeId, productId);
}

/** Updates the quantity/unit of ONE existing recipe line ("Edit recipe supply"). */
async function updateLine(storeId, productId, ingredientId, { quantity, unit }) {
  await assertValidLine(storeId, ingredientId, unit);
  const updated = await recipeRepository.updateLine(storeId, productId, ingredientId, { quantity, unit });
  if (!updated) throw ApiError.notFound('Recipe line not found', 'RECIPE_LINE_NOT_FOUND');
  return getForProduct(storeId, productId);
}

async function removeLine(storeId, productId, ingredientId) {
  const removed = await recipeRepository.removeLine(storeId, productId, ingredientId);
  if (!removed) throw ApiError.notFound('Recipe line not found', 'RECIPE_LINE_NOT_FOUND');
  return getForProduct(storeId, productId);
}

/** "Used in" list for the Supply Detail screen (spec §23). */
async function productsUsingIngredient(storeId, ingredientId) {
  const ingredient = await ingredientRepository.findById(storeId, ingredientId);
  if (!ingredient) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');
  return recipeRepository.listProductsUsingIngredient(storeId, ingredientId);
}

module.exports = {
  getForProduct,
  setForProduct,
  addLine,
  updateLine,
  removeLine,
  productsUsingIngredient,
};
