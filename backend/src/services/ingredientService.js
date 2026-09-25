const { v4: uuidv4 } = require('uuid');
const { withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const ingredientRepository = require('../repositories/ingredientRepository');
const ingredientMovementRepository = require('../repositories/ingredientMovementRepository');
const expenseRepository = require('../repositories/expenseRepository');
const recipeRepository = require('../repositories/recipeRepository');
const { convertQuantity } = require('../utils/unitConversion');

// MySQL's FK error code when a DELETE is blocked by ON DELETE RESTRICT
// (see fk_product_ingredients_ingredient / fk_ingredient_movements_ingredient
// in migrations/008_ingredient_delete_integrity.sql). Kept as a
// defense-in-depth backstop — the explicit checks in `remove` below
// should always catch these cases first and return a precise, friendly
// error before the DB ever gets a chance to reject the DELETE.
const ER_ROW_IS_REFERENCED_2 = 1451;

async function list(storeId, query = {}) {
  const rows = await ingredientRepository.list(storeId, {
    search: query.search,
    isActive: query.is_active,
  });
  return rows.map(withStatus);
}

function withStatus(ingredient) {
  const stock = Number(ingredient.stock_quantity);
  const min = Number(ingredient.min_stock);
  let status = 'normal';
  if (stock <= 0) status = 'rupture';
  else if (stock <= min) status = 'faible';
  return { ...ingredient, status };
}

async function getById(storeId, id) {
  const ingredient = await ingredientRepository.findById(storeId, id);
  if (!ingredient) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');
  return withStatus(ingredient);
}

async function create(storeId, input) {
  const id = input.id || uuidv4();
  const created = await ingredientRepository.create(storeId, { ...input, id });
  return withStatus(created);
}

async function update(storeId, id, input) {
  const updated = await ingredientRepository.update(storeId, id, input);
  if (!updated) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');
  return withStatus(updated);
}

/**
 * Delete for a supply/ingredient (spec §1–§5).
 *
 * "Supprimer" on an ingredient must always succeed from the user's point
 * of view — it is never blocked by recipe usage anymore. Instead, in a
 * SINGLE atomic transaction:
 *
 *  1. Verify the ingredient exists (locked with FOR UPDATE so a
 *     concurrent write can't race the decision below).
 *  2. Remove EVERY product_ingredients row referencing it — the
 *     ingredient disappears from every recipe that used it (spec §1).
 *  3. Check whether it has historical stock-movement or expense
 *     references. History (purchases, sale consumption, adjustments,
 *     damage) must never be destroyed (spec §2):
 *       - No history  -> hard DELETE the ingredients row.
 *       - Has history -> UPDATE is_active = 0 instead (soft delete); the
 *         row and all its historical references stay intact, but it
 *         behaves as deleted everywhere in the active app (spec §21).
 *
 * If any step fails, the whole transaction rolls back — there is no
 * state where recipe lines are gone but the ingredient delete/deactivate
 * didn't happen, or vice versa (spec §3).
 */
async function remove(storeId, id) {
  const ingredient = await ingredientRepository.findById(storeId, id);
  if (!ingredient) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');

  return withTransaction(async (conn) => {
    // Row lock: makes the exists-check and the delete/deactivate decision
    // atomic with respect to any other writer touching this ingredient.
    const locked = await ingredientRepository.findByIdForUpdate(conn, storeId, id);
    if (!locked) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');

    // Step 1: strip this ingredient out of every product recipe that
    // references it, in every product, before deciding what to do with
    // the ingredient row itself (spec §1/§4).
    await recipeRepository.deleteAllRecipeLinesForIngredientTx(conn, storeId, id);

    // Step 2: does deleting the row destroy auditable history?
    const [hasMovementHistory, hasExpenseReference] = await Promise.all([
      ingredientMovementRepository.hasHistoryTx(conn, storeId, id),
      expenseRepository.hasIngredientReferenceTx(conn, storeId, id),
    ]);

    if (hasMovementHistory || hasExpenseReference) {
      // Step 3a: history must be preserved -> deactivate instead of
      // deleting (spec §2/§3). The ingredient row, and everything that
      // still points at it, is untouched.
      const deactivated = await ingredientRepository.softDeleteTx(conn, storeId, id);
      if (!deactivated) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');
      return { id, deleted: false, deactivated: true };
    }

    // Step 3b: no history at all -> safe to physically delete.
    let deleted;
    try {
      deleted = await ingredientRepository.hardDeleteTx(conn, storeId, id);
    } catch (error) {
      if (error && error.errno === ER_ROW_IS_REFERENCED_2) {
        // Should not happen given the checks above and the recipe-line
        // cleanup that just ran in this same transaction — but if some
        // other reference this code doesn't know about yet still exists,
        // refuse safely rather than let a raw SQL error reach the client.
        // Throwing here rolls back the recipe-line deletion too, so
        // nothing is left half-done.
        throw ApiError.conflict(
          `Impossible de supprimer "${ingredient.name}" car il est encore référencé ailleurs.`,
          'INGREDIENT_DELETE_FAILED'
        );
      }
      throw error;
    }
    if (!deleted) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');
    return { id, deleted: true, deactivated: false };
  });
}

/** "Désactiver" — the safe alternative to a blocked delete. The
 * ingredient disappears from active supply/recipe selection but every
 * existing recipe line, sale, and stock movement keeps pointing at it
 * (spec §13). */
async function deactivate(storeId, id) {
  const deactivated = await ingredientRepository.softDelete(storeId, id);
  if (!deactivated) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');
  return getById(storeId, id);
}

/**
 * Manual stock entry (Stocks des ingrédients → "Nouveau stock" / restock
 * after a supplier delivery). Positive quantity = purchase/adjustment in,
 * negative = damage/adjustment out. Blocks going below zero, same
 * guarantee as product stock adjustments.
 */
async function addMovement(storeId, ingredientId, input) {
  const ingredient = await ingredientRepository.findById(storeId, ingredientId);
  if (!ingredient) throw ApiError.notFound('Ingredient not found', 'INGREDIENT_NOT_FOUND');

  const movementId = uuidv4();

  await withTransaction(async (conn) => {
    const success = await ingredientRepository.adjustStock(
      conn,
      storeId,
      ingredientId,
      input.quantity_delta
    );
    if (!success) {
      throw ApiError.conflict(
        `Not enough stock for "${ingredient.name}"`,
        'INSUFFICIENT_INGREDIENT_STOCK'
      );
    }
    await ingredientMovementRepository.insertMovement(conn, storeId, {
      id: movementId,
      ingredientId,
      quantityDelta: input.quantity_delta,
      movementType: input.movement_type,
      referenceId: input.reference_id,
      note: input.note,
    });
  });

  return getById(storeId, ingredientId);
}

async function movements(storeId, ingredientId, query = {}) {
  return ingredientMovementRepository.listForIngredient(storeId, ingredientId, {
    page: Math.max(1, Number.parseInt(query?.page, 10) || 1),
    pageSize: Math.max(1, Number.parseInt(query?.page_size, 10) || 50),
  });
}

async function lowStock(storeId) {
  const rows = await ingredientRepository.lowStock(storeId);
  return rows.map(withStatus);
}

function round3(n) {
  return Math.round((n + Number.EPSILON) * 1000) / 1000;
}

/**
 * Auto-consumption: deducts the recipe's ingredients for one unit of
 * `productId` sold, `quantity` times. Called from inside saleService's
 * existing sale transaction (same `conn`), right after product stock is
 * adjusted for that line item — mirrors "Consommation automatique" on the
 * dashboard mock.
 *
 * Two things have to happen for every recipe line BEFORE any stock is
 * touched:
 *  1. Unit conversion (spec §13): a recipe line can be authored in a unit
 *     different from the ingredient's own storage unit (e.g. a recipe in
 *     grams for an ingredient stocked in kg) — recipeService already
 *     guards that the two units are compatible when the recipe is
 *     authored, so this only ever converts within the same family.
 *  2. Availability check (spec §6/§7/§19): the required quantity (already
 *     converted, already multiplied by the quantity sold) must not exceed
 *     the ingredient's current stock. `findByIdForUpdate` takes the same
 *     row lock the product-stock check already takes in
 *     saleService.createSale, so two sales racing for the same supply
 *     can't both pass the check and overdraw it.
 *
 * If ANY line is short, this throws and writes nothing for that line —
 * and because saleService.createSale calls this from inside its own
 * `withTransaction`, the whole sale (product stock, sale/sale_items rows,
 * any ingredient lines already deducted for earlier cart items) is rolled
 * back with it. No partial sale, no partial inventory movement, ever
 * (spec §6 test 3). This is also what makes multi-item aggregation (spec
 * §14) come out correct automatically: two cart lines that share an
 * ingredient are consumed sequentially against the same row inside the
 * same transaction, so the second line's check sees the stock already
 * reduced by the first.
 *
 * Returns the list of consumption lines applied, for an optional
 * receipt/audit trail.
 */
async function consumeForSale(conn, storeId, { productId, productName, quantity, saleId }) {
  const recipe = await recipeRepository.listForProductTx(conn, storeId, productId);
  const applied = [];
  for (const line of recipe) {
    const requiredInStorageUnit = round3(
      convertQuantity(Number(line.quantity) * quantity, line.unit || line.ingredient_unit, line.ingredient_unit)
    );

    const ingredient = await ingredientRepository.findByIdForUpdate(conn, storeId, line.ingredient_id);
    const available = ingredient ? Number(ingredient.stock_quantity) : 0;
    // Never report a negative "available" quantity to the cashier — a
    // legacy/negative stock value (spec §7) should read as "0 available",
    // not as a confusing negative number.
    const availableForDisplay = Math.max(0, available);

    const buildMessage = () =>
      `Impossible de vendre ${productName || productId} : ingrédient insuffisant — ${line.ingredient_name}. ` +
      `Stock disponible : ${availableForDisplay} ${line.ingredient_unit}, nécessaire : ${requiredInStorageUnit} ${line.ingredient_unit}.`;

    if (!ingredient || available + 1e-9 < requiredInStorageUnit) {
      throw ApiError.conflict(buildMessage(), 'INSUFFICIENT_INGREDIENT_STOCK', {
        product_id: productId,
        ingredient_id: line.ingredient_id,
        ingredient_name: line.ingredient_name,
        available: availableForDisplay,
        required: requiredInStorageUnit,
        unit: line.ingredient_unit,
      });
    }

    const delta = -requiredInStorageUnit;
    const success = await ingredientRepository.adjustStock(conn, storeId, line.ingredient_id, delta);
    if (!success) {
      // Guards against a race the row lock above should already prevent —
      // kept as defense in depth, same pattern as productRepository.adjustStock.
      throw ApiError.conflict(buildMessage(), 'INSUFFICIENT_INGREDIENT_STOCK', {
        product_id: productId,
        ingredient_id: line.ingredient_id,
        ingredient_name: line.ingredient_name,
        available: availableForDisplay,
        required: requiredInStorageUnit,
        unit: line.ingredient_unit,
      });
    }

    const movementId = uuidv4();
    await ingredientMovementRepository.insertMovement(conn, storeId, {
      id: movementId,
      ingredientId: line.ingredient_id,
      quantityDelta: delta,
      movementType: 'SALE_CONSUMPTION',
      referenceId: saleId,
    });
    applied.push({
      ingredient_id: line.ingredient_id,
      ingredient_name: line.ingredient_name,
      unit: line.ingredient_unit,
      quantity_delta: delta,
    });
  }
  return applied;
}

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
  consumeForSale,
  deactivate,
};
