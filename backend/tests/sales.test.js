process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');
jest.mock('../src/repositories/saleRepository');
jest.mock('../src/repositories/paymentRepository');
jest.mock('../src/repositories/productRepository');
jest.mock('../src/repositories/inventoryRepository');
jest.mock('../src/repositories/recipeRepository');
jest.mock('../src/repositories/ingredientRepository');
jest.mock('../src/repositories/ingredientMovementRepository');

const { withTransaction } = require('../src/config/db');
const saleRepository = require('../src/repositories/saleRepository');
const paymentRepository = require('../src/repositories/paymentRepository');
const productRepository = require('../src/repositories/productRepository');
const inventoryRepository = require('../src/repositories/inventoryRepository');
const recipeRepository = require('../src/repositories/recipeRepository');
const ingredientRepository = require('../src/repositories/ingredientRepository');
const ingredientMovementRepository = require('../src/repositories/ingredientMovementRepository');
const saleService = require('../src/services/saleService');

const STORE_ID = 'store-1';
const USER_ID = 'user-1';
const FAKE_CONN = {};

const PRODUCT = {
  id: 'prod-1',
  name: 'Bottled Water',
  price: '5.00',
  is_active: 1,
  stock_quantity: 10,
};

function baseSaleInput(overrides = {}) {
  return {
    client_operation_id: 'op-aaaa-1111',
    items: [{ product_id: PRODUCT.id, quantity: 2, unit_price: 5.0 }],
    payments: [{ amount: 10.0, payment_method: 'CASH' }],
    discount_total: 0,
    tax_total: 0,
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  // withTransaction just runs the callback with a stand-in connection —
  // the same object flows through to every mocked repository call so we
  // can assert on it if needed.
  withTransaction.mockImplementation((work) => work(FAKE_CONN));
  // Default: the product being sold has no recipe configured, so
  // ingredientService.consumeForSale is a no-op — matches every existing
  // test in this file, which predate the recipe/auto-consumption feature
  // and never set up a recipe. Tests that DO care about recipe
  // consumption override this per-test.
  recipeRepository.listForProductTx.mockResolvedValue([]);
});

describe('saleService.createSale — idempotency', () => {
  test('returns the existing sale unchanged when client_operation_id was already processed', async () => {
    const existingSale = { id: 'sale-existing', total: '10.00' };
    saleRepository.findByClientOperationId.mockResolvedValue({ id: 'sale-existing' });
    saleRepository.findById.mockResolvedValue(existingSale);

    const { sale, wasDuplicate } = await saleService.createSale(
      STORE_ID,
      USER_ID,
      baseSaleInput()
    );

    expect(wasDuplicate).toBe(true);
    expect(sale).toBe(existingSale);
    // Must NOT touch stock or insert anything a second time.
    expect(productRepository.adjustStock).not.toHaveBeenCalled();
    expect(saleRepository.insertSale).not.toHaveBeenCalled();
  });

  test('a second push of the same client_operation_id never creates a second sale row', async () => {
    // First call: genuinely new.
    saleRepository.findByClientOperationId.mockResolvedValueOnce(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);
    productRepository.adjustStock.mockResolvedValue(true);
    saleRepository.findById.mockResolvedValue({ id: 'sale-1', total: '10.00' });

    await saleService.createSale(STORE_ID, USER_ID, baseSaleInput());
    expect(saleRepository.insertSale).toHaveBeenCalledTimes(1);

    // Second call with the SAME client_operation_id: repository now reports
    // it as already existing (simulating the row the first call inserted).
    saleRepository.findByClientOperationId.mockResolvedValueOnce({ id: 'sale-1' });
    await saleService.createSale(STORE_ID, USER_ID, baseSaleInput());

    // insertSale should still have been called exactly once in total.
    expect(saleRepository.insertSale).toHaveBeenCalledTimes(1);
  });
});

describe('saleService.createSale — validation', () => {
  test('rejects a sale referencing a product that does not exist in this store', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(null);

    await expect(saleService.createSale(STORE_ID, USER_ID, baseSaleInput())).rejects.toMatchObject(
      { code: 'INVALID_PRODUCT' }
    );
  });

  test('rejects a sale whose payments do not cover the total', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);

    const input = baseSaleInput({ payments: [{ amount: 1.0, payment_method: 'CASH' }] });

    await expect(saleService.createSale(STORE_ID, USER_ID, input)).rejects.toMatchObject({
      code: 'INSUFFICIENT_PAYMENT',
    });
    expect(saleRepository.insertSale).not.toHaveBeenCalled();
  });

  test('rejects the sale when stock would go negative, and writes nothing', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);
    // adjustStock's conditional UPDATE reports 0 affected rows -> false
    productRepository.adjustStock.mockResolvedValue(false);

    await expect(saleService.createSale(STORE_ID, USER_ID, baseSaleInput())).rejects.toMatchObject(
      { code: 'INSUFFICIENT_STOCK' }
    );
    expect(inventoryRepository.insertMovement).not.toHaveBeenCalled();
  });

  test('a successful sale writes items, payments, and one SALE inventory movement per line', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);
    productRepository.adjustStock.mockResolvedValue(true);
    saleRepository.findById.mockResolvedValue({ id: 'sale-1', total: '10.00' });

    const { wasDuplicate } = await saleService.createSale(STORE_ID, USER_ID, baseSaleInput());

    expect(wasDuplicate).toBe(false);
    expect(saleRepository.insertSale).toHaveBeenCalledTimes(1);
    expect(saleRepository.insertSaleItems).toHaveBeenCalledTimes(1);
    expect(paymentRepository.insertPayments).toHaveBeenCalledTimes(1);
    expect(inventoryRepository.insertMovement).toHaveBeenCalledTimes(1);
    expect(inventoryRepository.insertMovement).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({ movementType: 'SALE', quantityDelta: -2 })
    );
  });
});

describe('saleService.createSale — "Give receipt without paying" (unpaid sales)', () => {
  test('an EMPTY payments array creates a real sale marked PENDING ("NOT PAID"), not an error', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);
    productRepository.adjustStock.mockResolvedValue(true);
    saleRepository.findById.mockResolvedValue({ id: 'sale-1', total: '10.00', payment_status: 'PENDING' });

    const input = baseSaleInput({ payments: [] });
    const { sale, wasDuplicate } = await saleService.createSale(STORE_ID, USER_ID, input);

    expect(wasDuplicate).toBe(false);
    expect(sale.payment_status).toBe('PENDING');
    // The sale + its items + its stock deduction are still real and
    // written normally — only the payment step is skipped.
    expect(saleRepository.insertSale).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({ paymentStatus: 'PENDING' })
    );
    expect(saleRepository.insertSaleItems).toHaveBeenCalledTimes(1);
    expect(inventoryRepository.insertMovement).toHaveBeenCalledTimes(1);
    // No payment rows, and definitely no fake/synthesized payment data.
    // (The sale id is a freshly generated uuid, not the mocked findById
    // result's id, so match it structurally rather than hardcoding one.)
    expect(paymentRepository.insertPayments).toHaveBeenCalledWith(
      FAKE_CONN,
      expect.any(String),
      USER_ID,
      []
    );
  });

  test('paying an existing PENDING sale later updates the SAME row instead of creating a new sale', async () => {
    const existingSale = { id: 'sale-1', total: '10.00', payment_status: 'PENDING' };
    saleRepository.findByIdForUpdate.mockResolvedValue(existingSale);
    paymentRepository.findByClientOperationId.mockResolvedValue(null);
    paymentRepository.sumBySale.mockResolvedValue(10.0);
    saleRepository.findById.mockResolvedValue({ ...existingSale, payment_status: 'PAID' });

    const { sale, wasDuplicate } = await saleService.addPayment(STORE_ID, USER_ID, {
      client_operation_id: 'pay-op-1',
      sale_id: 'sale-1',
      amount: 10.0,
      payment_method: 'CASH',
    });

    expect(wasDuplicate).toBe(false);
    expect(sale.payment_status).toBe('PAID');
    // Exactly one sale row ever existed — addPayment must never insert a
    // second sale (spec §6/§9/§20: duplicate protection).
    expect(saleRepository.insertSale).not.toHaveBeenCalled();
    expect(saleRepository.updatePaymentStatus).toHaveBeenCalledWith(FAKE_CONN, 'sale-1', 'PAID');
  });
});

describe('saleService.createSale — recipe / ingredient auto-consumption', () => {
  // Café Americain: 10 g of Coffee (stocked in kg) + 1 unit of Cup (same
  // unit both sides) per cup sold.
  const COFFEE = { id: 'ing-coffee', name: 'Coffee', unit: 'kg', stock_quantity: '5.000' };
  const CUP = { id: 'ing-cup', name: 'Cup', unit: 'unit', stock_quantity: '100.000' };
  const RECIPE = [
    {
      ingredient_id: COFFEE.id,
      quantity: '10',
      unit: 'g',
      ingredient_name: COFFEE.name,
      ingredient_unit: COFFEE.unit,
    },
    {
      ingredient_id: CUP.id,
      quantity: '1',
      unit: null,
      ingredient_name: CUP.name,
      ingredient_unit: CUP.unit,
    },
  ];

  function ingredientById(id) {
    return { COFFEE, CUP }[id === COFFEE.id ? 'COFFEE' : 'CUP'];
  }

  beforeEach(() => {
    recipeRepository.listForProductTx.mockResolvedValue(RECIPE);
    ingredientRepository.findByIdForUpdate.mockImplementation((_conn, _storeId, id) =>
      Promise.resolve(ingredientById(id))
    );
    ingredientRepository.adjustStock.mockResolvedValue(true);
  });

  test('converts the recipe unit into the ingredient storage unit before deducting (spec §13)', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);
    productRepository.adjustStock.mockResolvedValue(true);
    saleRepository.findById.mockResolvedValue({ id: 'sale-1', total: '10.00' });

    // baseSaleInput sells quantity 2 of the product.
    await saleService.createSale(STORE_ID, USER_ID, baseSaleInput());

    // 10 g/unit * 2 units = 20 g = 0.02 kg, converted into Coffee's own
    // storage unit (kg) — NOT deducted as a raw "20" against a kg stock.
    expect(ingredientRepository.adjustStock).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      COFFEE.id,
      -0.02
    );
    expect(ingredientRepository.adjustStock).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, CUP.id, -2);
    expect(ingredientMovementRepository.insertMovement).toHaveBeenCalledTimes(2);
    expect(ingredientMovementRepository.insertMovement).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({
        ingredientId: COFFEE.id,
        quantityDelta: -0.02,
        movementType: 'SALE_CONSUMPTION',
        referenceId: expect.any(String),
      })
    );
  });

  test('rejects the WHOLE sale when a recipe supply is short, with no partial writes (spec §6/§7/§19, TEST 3)', async () => {
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    productRepository.findByIdForUpdate.mockResolvedValue(PRODUCT);
    productRepository.adjustStock.mockResolvedValue(true);

    // Cup is out of stock: 2 required, 0 available.
    ingredientRepository.findByIdForUpdate.mockImplementation((_conn, _storeId, id) =>
      Promise.resolve(id === CUP.id ? { ...CUP, stock_quantity: '0' } : COFFEE)
    );

    await expect(saleService.createSale(STORE_ID, USER_ID, baseSaleInput())).rejects.toMatchObject({
      code: 'INSUFFICIENT_INGREDIENT_STOCK',
    });

    // The sale row itself was written earlier in the same transaction,
    // but since consumeForSale threw, withTransaction's catch block calls
    // conn.rollback() (see src/config/db.js) before the error propagates,
    // so nothing written here actually persists. No ingredient movement
    // is ever inserted for the failed line or for lines after it.
    expect(ingredientMovementRepository.insertMovement).not.toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({ ingredientId: CUP.id })
    );
  });

  test('aggregates consumption of a shared ingredient across multiple cart lines (spec §14, TEST 6)', async () => {
    // Two products, both using Coffee: 3x Café Americain (10 g each) +
    // 2x Cappuccino (15 g each) => 30 g + 30 g = 60 g = 0.06 kg total.
    const CAPPUCCINO = { id: 'prod-2', name: 'Cappuccino', price: '6.00', is_active: 1, stock_quantity: 10 };
    productRepository.findByIdForUpdate.mockImplementation((_conn, _storeId, id) =>
      Promise.resolve(id === PRODUCT.id ? PRODUCT : CAPPUCCINO)
    );
    productRepository.adjustStock.mockResolvedValue(true);
    saleRepository.findByClientOperationId.mockResolvedValue(null);
    saleRepository.findById.mockResolvedValue({ id: 'sale-1', total: '27.00' });

    recipeRepository.listForProductTx.mockImplementation((_conn, _storeId, productId) => {
      if (productId === PRODUCT.id) {
        return Promise.resolve([
          { ingredient_id: COFFEE.id, quantity: '10', unit: 'g', ingredient_name: COFFEE.name, ingredient_unit: COFFEE.unit },
        ]);
      }
      return Promise.resolve([
        { ingredient_id: COFFEE.id, quantity: '15', unit: 'g', ingredient_name: COFFEE.name, ingredient_unit: COFFEE.unit },
      ]);
    });

    const input = baseSaleInput({
      items: [
        { product_id: PRODUCT.id, quantity: 3, unit_price: 5.0 },
        { product_id: CAPPUCCINO.id, quantity: 2, unit_price: 6.0 },
      ],
      payments: [{ amount: 27.0, payment_method: 'CASH' }],
    });

    await saleService.createSale(STORE_ID, USER_ID, input);

    // Two separate deductions against the SAME ingredient row, sequential
    // within the one transaction — 0.03 kg then 0.03 kg, adding up to the
    // full 0.06 kg (60 g) the cart actually requires. Never one combined
    // call, but never a duplicate/incorrect amount either.
    const coffeeCalls = ingredientRepository.adjustStock.mock.calls.filter((c) => c[2] === COFFEE.id);
    expect(coffeeCalls).toHaveLength(2);
    const totalDeducted = coffeeCalls.reduce((sum, c) => sum + c[3], 0);
    expect(totalDeducted).toBeCloseTo(-0.06, 6);
  });
});
