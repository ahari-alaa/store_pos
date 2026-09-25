process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/repositories/recipeRepository');
jest.mock('../src/repositories/productRepository');
jest.mock('../src/repositories/ingredientRepository');

const recipeRepository = require('../src/repositories/recipeRepository');
const productRepository = require('../src/repositories/productRepository');
const recipeService = require('../src/services/recipeService');

const STORE_ID = 'store-1';
const PRODUCT_ID = 'prod-cafe-americain';

const PRODUCT = {
  id: PRODUCT_ID,
  store_id: STORE_ID,
  name: 'CAFE AMERICAIN',
  price: '15.00',
};

function line(overrides = {}) {
  return {
    id: 'line-1',
    product_id: PRODUCT_ID,
    ingredient_id: 'ing-cafe',
    quantity: '25.000',
    unit: 'g',
    ingredient_name: 'café',
    ingredient_unit: 'kg',
    ingredient_stock: '0.000',
    ingredient_min_stock: '1.000',
    cost_per_unit: '85.0000',
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  productRepository.findById.mockResolvedValue(PRODUCT);
});

describe('recipeService.getForProduct — possible_production can never be negative (spec §13/§14)', () => {
  test('TEST 7: ingredient stock = 0 -> possible production = 0, product marked unavailable', async () => {
    recipeRepository.listForProduct.mockResolvedValue([line({ ingredient_stock: '0.000' })]);

    const result = await recipeService.getForProduct(STORE_ID, PRODUCT_ID);

    expect(result.possible_production).toBe(0);
    expect(result.limiting_ingredient).toBe('café');
  });

  test('TEST 8: legacy NEGATIVE stock (e.g. -425 kg) must clamp possible production to 0, never a negative number', async () => {
    recipeRepository.listForProduct.mockResolvedValue([
      line({ ingredient_stock: '-425.000', quantity: '25.000', unit: 'g' }),
    ]);

    const result = await recipeService.getForProduct(STORE_ID, PRODUCT_ID);

    expect(result.possible_production).toBe(0);
    expect(result.possible_production).toBeGreaterThanOrEqual(0);
    expect(result.lines[0].possible_production).toBe(0);
  });

  test('sufficient stock yields a positive, correctly-converted possible production', async () => {
    // 1 kg stock, 25 g required per unit -> 1000g / 25g = 40 units.
    recipeRepository.listForProduct.mockResolvedValue([
      line({ ingredient_stock: '1.000', quantity: '25.000', unit: 'g' }),
    ]);

    const result = await recipeService.getForProduct(STORE_ID, PRODUCT_ID);

    expect(result.possible_production).toBe(40);
  });

  test('the limiting ingredient across multiple lines is the one with the lowest yield, and yield is never negative', async () => {
    recipeRepository.listForProduct.mockResolvedValue([
      line({
        id: 'l1',
        ingredient_id: 'ing-cafe',
        ingredient_name: 'café',
        ingredient_stock: '1.000',
        quantity: '25.000',
        unit: 'g',
      }), // 40 possible
      line({
        id: 'l2',
        ingredient_id: 'ing-milk',
        ingredient_name: 'milk',
        ingredient_stock: '-5.000',
        ingredient_unit: 'l',
        quantity: '150.000',
        unit: 'ml',
      }), // negative stock -> clamps to 0
    ]);

    const result = await recipeService.getForProduct(STORE_ID, PRODUCT_ID);

    expect(result.possible_production).toBe(0);
    expect(result.limiting_ingredient).toBe('milk');
  });

  test('a recipe with no lines at all has possible production 0, not Infinity', async () => {
    recipeRepository.listForProduct.mockResolvedValue([]);

    const result = await recipeService.getForProduct(STORE_ID, PRODUCT_ID);

    expect(result.possible_production).toBe(0);
    expect(result.limiting_ingredient).toBeNull();
  });
});
