process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');
jest.mock('../src/repositories/ingredientRepository');
jest.mock('../src/repositories/ingredientMovementRepository');
jest.mock('../src/repositories/expenseRepository');
jest.mock('../src/repositories/recipeRepository');

const { withTransaction } = require('../src/config/db');
const ingredientRepository = require('../src/repositories/ingredientRepository');
const ingredientMovementRepository = require('../src/repositories/ingredientMovementRepository');
const expenseRepository = require('../src/repositories/expenseRepository');
const recipeRepository = require('../src/repositories/recipeRepository');
const ingredientService = require('../src/services/ingredientService');

const STORE_ID = 'store-1';
const FAKE_CONN = {};

const CAFE = {
  id: 'ing-cafe',
  store_id: STORE_ID,
  name: 'café',
  unit: 'kg',
  stock_quantity: '0.000',
  min_stock: '1.000',
  cost_per_unit: '85.0000',
  is_active: 1,
};

beforeEach(() => {
  jest.clearAllMocks();
  // withTransaction just runs the callback with a stand-in connection —
  // the same object flows through to every mocked repository call so we
  // can assert on it if needed. Mirrors the pattern used in
  // sales.test.js / expenses.test.js.
  withTransaction.mockImplementation((work) => work(FAKE_CONN));

  ingredientRepository.findById.mockResolvedValue(CAFE);
  ingredientRepository.findByIdForUpdate.mockResolvedValue(CAFE);
  recipeRepository.listProductsUsingIngredient.mockResolvedValue([]);
  recipeRepository.deleteAllRecipeLinesForIngredientTx.mockResolvedValue(0);
  ingredientMovementRepository.hasHistory.mockResolvedValue(false);
  ingredientMovementRepository.hasHistoryTx.mockResolvedValue(false);
  expenseRepository.hasIngredientReference.mockResolvedValue(false);
  expenseRepository.hasIngredientReferenceTx.mockResolvedValue(false);
  ingredientRepository.hardDelete.mockResolvedValue(true);
  ingredientRepository.hardDeleteTx.mockResolvedValue(true);
  ingredientRepository.softDelete.mockResolvedValue(true);
  ingredientRepository.softDeleteTx.mockResolvedValue(true);
});

describe('ingredientService.remove — spec §1–§5, §17 — deletion is never blocked', () => {
  test('TEST 9: an ingredient used by 3 products has all 3 recipe lines removed, and the products themselves are untouched', async () => {
    recipeRepository.listProductsUsingIngredient.mockResolvedValue([
      { product_id: 'p1', product_name: 'CAFE AMERICAIN', quantity: '25.000', unit: 'g' },
      { product_id: 'p2', product_name: 'CAPPUCCINO', quantity: '15.000', unit: 'g' },
      { product_id: 'p3', product_name: 'EXPRESS', quantity: '10.000', unit: 'g' },
    ]);

    const result = await ingredientService.remove(STORE_ID, CAFE.id);

    // The recipe-line cleanup must run inside the SAME transaction
    // connection, before the delete/deactivate decision.
    expect(recipeRepository.deleteAllRecipeLinesForIngredientTx).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      CAFE.id
    );
    // Deletion itself must never be blocked by recipe usage anymore —
    // productService/recipeRepository are never asked to remove the
    // product rows, only the product_ingredients rows.
    expect(result.deleted).toBe(true);
  });

  test('TEST 11: an ingredient with NO history at all is hard-deleted after its recipe lines are stripped', async () => {
    const result = await ingredientService.remove(STORE_ID, CAFE.id);

    expect(recipeRepository.deleteAllRecipeLinesForIngredientTx).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      CAFE.id
    );
    expect(ingredientRepository.hardDeleteTx).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, CAFE.id);
    expect(ingredientRepository.softDeleteTx).not.toHaveBeenCalled();
    expect(result).toEqual({ id: CAFE.id, deleted: true, deactivated: false });
  });

  test('TEST 10: an ingredient WITH stock-movement history is deactivated (not hard-deleted), and the history is left untouched', async () => {
    ingredientMovementRepository.hasHistoryTx.mockResolvedValue(true);

    const result = await ingredientService.remove(STORE_ID, CAFE.id);

    expect(recipeRepository.deleteAllRecipeLinesForIngredientTx).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      CAFE.id
    );
    expect(ingredientRepository.softDeleteTx).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, CAFE.id);
    expect(ingredientRepository.hardDeleteTx).not.toHaveBeenCalled();
    expect(result).toEqual({ id: CAFE.id, deleted: false, deactivated: true });
  });

  test('an ingredient referenced only by an expense record (no movement row) is also deactivated instead of deleted', async () => {
    expenseRepository.hasIngredientReferenceTx.mockResolvedValue(true);

    const result = await ingredientService.remove(STORE_ID, CAFE.id);

    expect(ingredientRepository.softDeleteTx).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, CAFE.id);
    expect(result.deactivated).toBe(true);
  });

  test('recipe lines are removed even when the ingredient ALSO has history (both happen, in the same transaction)', async () => {
    recipeRepository.listProductsUsingIngredient.mockResolvedValue([
      { product_id: 'p1', product_name: 'CAFE AMERICAIN', quantity: '25.000', unit: 'g' },
    ]);
    ingredientMovementRepository.hasHistoryTx.mockResolvedValue(true);

    const result = await ingredientService.remove(STORE_ID, CAFE.id);

    expect(recipeRepository.deleteAllRecipeLinesForIngredientTx).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      CAFE.id
    );
    expect(ingredientRepository.softDeleteTx).toHaveBeenCalled();
    expect(result.deactivated).toBe(true);
  });

  test('the whole operation runs inside ONE transaction (spec §3)', async () => {
    await ingredientService.remove(STORE_ID, CAFE.id);
    expect(withTransaction).toHaveBeenCalledTimes(1);
  });

  test('if the hard delete step fails mid-transaction, withTransaction rolls back everything (recipe cleanup included)', async () => {
    const boom = new Error('connection lost');
    ingredientRepository.hardDeleteTx.mockRejectedValue(boom);

    await expect(ingredientService.remove(STORE_ID, CAFE.id)).rejects.toThrow('connection lost');
    // withTransaction (mocked here as a pass-through) is what's
    // responsible for the rollback in production — this asserts the
    // service propagates the failure instead of swallowing it, which is
    // what lets withTransaction's real rollback logic kick in.
  });

  test('throws INGREDIENT_NOT_FOUND for an unknown id without starting a transaction', async () => {
    ingredientRepository.findById.mockResolvedValue(null);

    await expect(ingredientService.remove(STORE_ID, 'missing')).rejects.toMatchObject({
      code: 'INGREDIENT_NOT_FOUND',
    });
    expect(withTransaction).not.toHaveBeenCalled();
  });

  test('a stray FK violation from the DB (defense in depth) is converted into a clean conflict, not a raw SQL error', async () => {
    const fkError = new Error('Cannot delete or update a parent row');
    fkError.errno = 1451;
    ingredientRepository.hardDeleteTx.mockRejectedValue(fkError);

    await expect(ingredientService.remove(STORE_ID, CAFE.id)).rejects.toMatchObject({
      code: 'INGREDIENT_DELETE_FAILED',
      statusCode: 409,
    });
  });
});

describe('ingredientService.deactivate — manual "Désactiver" action, independent of delete', () => {
  test('TEST 4: deactivating sets is_active = 0 and returns the updated ingredient', async () => {
    ingredientRepository.findById.mockResolvedValue({ ...CAFE, is_active: 0 });

    const result = await ingredientService.deactivate(STORE_ID, CAFE.id);

    expect(ingredientRepository.softDelete).toHaveBeenCalledWith(STORE_ID, CAFE.id);
    expect(result.is_active).toBe(0);
  });

  test('throws INGREDIENT_NOT_FOUND when the ingredient does not exist', async () => {
    ingredientRepository.softDelete.mockResolvedValue(false);

    await expect(ingredientService.deactivate(STORE_ID, 'missing')).rejects.toMatchObject({
      code: 'INGREDIENT_NOT_FOUND',
    });
  });
});

describe('ingredientService.addMovement — TEST 6: manual adjustment can never push stock below zero', () => {
  test('rejects a reduction that would take stock below zero, and leaves stock unchanged', async () => {
    ingredientRepository.findById.mockResolvedValue({ ...CAFE, stock_quantity: '10.000' });
    ingredientRepository.adjustStock.mockResolvedValue(false); // WHERE clause found nothing to update

    await expect(
      ingredientService.addMovement(STORE_ID, CAFE.id, {
        quantity_delta: -15,
        movement_type: 'ADJUSTMENT',
      })
    ).rejects.toMatchObject({ code: 'INSUFFICIENT_INGREDIENT_STOCK' });

    expect(ingredientMovementRepository.insertMovement).not.toHaveBeenCalled();
  });

  test('a restock (+) is applied and logged as a PURCHASE movement', async () => {
    ingredientRepository.findById.mockResolvedValue({ ...CAFE, stock_quantity: '10.000' });
    ingredientRepository.adjustStock.mockResolvedValue(true);

    await ingredientService.addMovement(STORE_ID, CAFE.id, {
      quantity_delta: 20,
      movement_type: 'PURCHASE',
    });

    expect(ingredientRepository.adjustStock).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, CAFE.id, 20);
    expect(ingredientMovementRepository.insertMovement).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({ quantityDelta: 20, movementType: 'PURCHASE' })
    );
  });
});
