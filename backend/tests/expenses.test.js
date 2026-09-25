process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');
jest.mock('../src/repositories/expenseRepository');
jest.mock('../src/repositories/expenseCategoryRepository');
jest.mock('../src/repositories/inventoryRepository');
jest.mock('../src/repositories/productRepository');
jest.mock('../src/repositories/supplierRepository');
jest.mock('../src/middleware/upload', () => ({
  deleteExpenseReceiptFile: jest.fn(),
}));

const { withTransaction } = require('../src/config/db');
const expenseRepository = require('../src/repositories/expenseRepository');
const expenseCategoryRepository = require('../src/repositories/expenseCategoryRepository');
const inventoryRepository = require('../src/repositories/inventoryRepository');
const productRepository = require('../src/repositories/productRepository');
const supplierRepository = require('../src/repositories/supplierRepository');
const expenseService = require('../src/services/expenseService');

const STORE_ID = 'store-1';
const USER_ID = 'user-1';
const FAKE_CONN = {};

const COFFEE_CATEGORY = {
  id: 'cat-cafe',
  store_id: STORE_ID,
  name: 'Café',
  expense_type: 'APPROVISIONNEMENT',
};

const COFFEE_PRODUCT = {
  id: 'prod-cafe',
  store_id: STORE_ID,
  name: 'Café en grain',
  stock_quantity: 50,
};

function baseSupplyInput(overrides = {}) {
  return {
    client_operation_id: 'op-1111',
    category_id: COFFEE_CATEGORY.id,
    description: 'Café en kg',
    quantity: 15,
    unit: 'kg',
    unit_price: 85,
    supplier_name: 'Al Amal',
    occurred_at: '2026-09-12',
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  withTransaction.mockImplementation((work) => work(FAKE_CONN));
  expenseRepository.findByClientOperationId.mockResolvedValue(null);
  expenseCategoryRepository.findById.mockResolvedValue(COFFEE_CATEGORY);
  productRepository.findByIdForUpdate.mockResolvedValue(COFFEE_PRODUCT);
  productRepository.adjustStock.mockResolvedValue(true);
  productRepository.clampedAdjustStock.mockResolvedValue({ applied: 0, clamped: false });
  inventoryRepository.insertMovement.mockResolvedValue(undefined);
  inventoryRepository.findLatestForReference.mockResolvedValue(null);
  supplierRepository.findById.mockResolvedValue({ id: 'sup-1', name: 'Al Amal SARL' });
  expenseRepository.create.mockResolvedValue(undefined);
  expenseRepository.update.mockResolvedValue(true);
  expenseRepository.remove.mockResolvedValue(true);
  expenseRepository.findById.mockResolvedValue({ id: 'expense-1' });
});

describe('expenseService.create — exact decimal totals (spec §2 / §23)', () => {
  test('15 kg × 85 DH = 1275.00, never a floating-point-drifted value', async () => {
    await expenseService.create(STORE_ID, USER_ID, baseSupplyInput());

    expect(expenseRepository.create).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      USER_ID,
      expect.objectContaining({ amount: '1275.00' })
    );
  });

  test('30 kg × 12 DH = 360.00', async () => {
    await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput({ quantity: 30, unit_price: 12 })
    );
    expect(expenseRepository.create).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      USER_ID,
      expect.objectContaining({ amount: '360.00' })
    );
  });

  test('20 packs × 18 DH = 360.00', async () => {
    await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput({ quantity: 20, unit: 'pack', unit_price: 18 })
    );
    expect(expenseRepository.create).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      USER_ID,
      expect.objectContaining({ amount: '360.00' })
    );
  });

  test('a fixed charge with a plain amount (no quantity) is stored as-is', async () => {
    await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput({ quantity: undefined, unit: undefined, unit_price: undefined, amount: 1850 })
    );
    expect(expenseRepository.create).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      USER_ID,
      expect.objectContaining({ amount: 1850, quantity: null, unit: null })
    );
  });
});

describe('expenseService.create — idempotency (offline sync retries)', () => {
  test('returns the existing expense unchanged when client_operation_id was already processed', async () => {
    const existing = { id: 'expense-existing', amount: '1275.00' };
    expenseRepository.findByClientOperationId.mockResolvedValue(existing);

    const { expense, wasDuplicate } = await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput()
    );

    expect(wasDuplicate).toBe(true);
    expect(expense).toBe(existing);
    expect(expenseRepository.create).not.toHaveBeenCalled();
    expect(productRepository.adjustStock).not.toHaveBeenCalled();
  });
});

describe('expenseService.create — category resolution', () => {
  test('throws when neither category_id nor category/expense_type is given', async () => {
    await expect(
      expenseService.create(STORE_ID, USER_ID, baseSupplyInput({ category_id: undefined }))
    ).rejects.toMatchObject({ code: 'CATEGORY_REQUIRED' });
  });

  test('accepts a free-text category + expense_type (backward compatible path)', async () => {
    await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput({
        category_id: undefined,
        category: 'Électricité',
        expense_type: 'CHARGE_FIXE',
        quantity: undefined,
        unit: undefined,
        unit_price: undefined,
        amount: 1850,
      })
    );
    expect(expenseRepository.create).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      USER_ID,
      expect.objectContaining({
        category: 'Électricité',
        expenseType: 'CHARGE_FIXE',
        categoryId: null,
      })
    );
  });

  test('rejects an unknown category_id', async () => {
    expenseCategoryRepository.findById.mockResolvedValue(null);
    await expect(expenseService.create(STORE_ID, USER_ID, baseSupplyInput())).rejects.toMatchObject(
      { code: 'INVALID_CATEGORY' }
    );
  });
});

describe('expenseService.create — inventory linkage (spec §14)', () => {
  test('affects_inventory + product_id records a PURCHASE movement and increments stock', async () => {
    await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput({ affects_inventory: true, product_id: COFFEE_PRODUCT.id })
    );

    expect(productRepository.adjustStock).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      COFFEE_PRODUCT.id,
      15
    );
    expect(inventoryRepository.insertMovement).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({ productId: COFFEE_PRODUCT.id, movementType: 'PURCHASE', quantityDelta: 15 })
    );
  });

  test('electricity (no product_id) never touches inventory', async () => {
    await expenseService.create(
      STORE_ID,
      USER_ID,
      baseSupplyInput({
        category_id: undefined,
        category: 'Électricité',
        expense_type: 'CHARGE_FIXE',
        quantity: undefined,
        unit: undefined,
        unit_price: undefined,
        amount: 1850,
        affects_inventory: false,
      })
    );
    expect(productRepository.adjustStock).not.toHaveBeenCalled();
    expect(inventoryRepository.insertMovement).not.toHaveBeenCalled();
  });

  test('rejects affects_inventory=true without a product_id', async () => {
    await expect(
      expenseService.create(
        STORE_ID,
        USER_ID,
        baseSupplyInput({ affects_inventory: true, product_id: undefined })
      )
    ).rejects.toMatchObject({ code: 'PRODUCT_REQUIRED' });
  });
});

describe('expenseService.update', () => {
  const CURRENT = {
    id: 'expense-1',
    store_id: STORE_ID,
    category: 'Café',
    category_id: COFFEE_CATEGORY.id,
    expense_type: 'APPROVISIONNEMENT',
    description: 'Café en kg',
    amount: '1275.00',
    quantity: '15.000',
    unit: 'kg',
    unit_price: '85.00',
    supplier_id: null,
    supplier_name: 'Al Amal',
    notes: null,
    product_id: COFFEE_PRODUCT.id,
    affects_inventory: 1,
    is_recurring: 0,
    recurring_day: null,
    occurred_at: new Date('2026-09-12'),
    receipt_url: null,
  };

  beforeEach(() => {
    expenseRepository.findById.mockResolvedValue(CURRENT);
    inventoryRepository.findLatestForReference.mockResolvedValue({
      product_id: COFFEE_PRODUCT.id,
      quantity_delta: 15,
    });
    // Reversal of the old 15 kg purchase movement (spec: reversal is now
    // clamped at zero rather than force-subtracted — see
    // productRepository.clampedAdjustStock / expenseService.reverseInventoryMovement).
    // Nothing has been sold from it yet in this scenario, so the full
    // amount reverses cleanly.
    productRepository.clampedAdjustStock.mockResolvedValue({ applied: -15, clamped: false });
  });

  test('recalculates the total when quantity changes, and reconciles inventory (reverse + reapply)', async () => {
    await expenseService.update(STORE_ID, 'expense-1', { quantity: 20 });

    // Old movement reversed (via the clamped reversal path):
    expect(productRepository.clampedAdjustStock).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      COFFEE_PRODUCT.id,
      -15
    );
    // New movement applied for the updated quantity:
    expect(productRepository.adjustStock).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, COFFEE_PRODUCT.id, 20);
    expect(expenseRepository.update).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      'expense-1',
      expect.objectContaining({ amount: '1700.00', quantity: 20 })
    );
  });

  test('an amount-only edit does not touch inventory', async () => {
    await expenseService.update(STORE_ID, 'expense-1', { amount: 1300 });
    expect(productRepository.adjustStock).not.toHaveBeenCalled();
    expect(productRepository.clampedAdjustStock).not.toHaveBeenCalled();
  });

  test('reversal is clamped at zero instead of going negative if the purchase was already partly sold', async () => {
    // Only 10 kg of the original 15 kg purchase is still in stock — the
    // rest was already sold. Reversing the full 15 kg would drive stock
    // to -5; it must instead clamp to 0.
    productRepository.clampedAdjustStock.mockResolvedValue({ applied: -10, clamped: true });

    await expenseService.update(STORE_ID, 'expense-1', { quantity: 20 });

    expect(productRepository.clampedAdjustStock).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      COFFEE_PRODUCT.id,
      -15
    );
    // The ADJUSTMENT movement logged for the reversal reflects what was
    // ACTUALLY applied (-10, clamped), not the requested -15.
    expect(inventoryRepository.insertMovement).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      expect.objectContaining({
        productId: COFFEE_PRODUCT.id,
        movementType: 'ADJUSTMENT',
        quantityDelta: -10,
      })
    );
  });
});

describe('expenseService.remove', () => {
  test('reverses the linked inventory movement before deleting', async () => {
    expenseRepository.findById.mockResolvedValue({
      id: 'expense-1',
      affects_inventory: 1,
      category: 'Café',
      receipt_url: null,
    });
    inventoryRepository.findLatestForReference.mockResolvedValue({
      product_id: COFFEE_PRODUCT.id,
      quantity_delta: 15,
    });
    productRepository.clampedAdjustStock.mockResolvedValue({ applied: -15, clamped: false });

    await expenseService.remove(STORE_ID, 'expense-1');

    expect(productRepository.clampedAdjustStock).toHaveBeenCalledWith(
      FAKE_CONN,
      STORE_ID,
      COFFEE_PRODUCT.id,
      -15
    );
    expect(expenseRepository.remove).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, 'expense-1');
  });

  test('never drives stock negative when the purchased quantity was already fully sold', async () => {
    expenseRepository.findById.mockResolvedValue({
      id: 'expense-1',
      affects_inventory: 1,
      category: 'Café',
      receipt_url: null,
    });
    inventoryRepository.findLatestForReference.mockResolvedValue({
      product_id: COFFEE_PRODUCT.id,
      quantity_delta: 15,
    });
    // Nothing left to take back — the whole purchase was already sold.
    productRepository.clampedAdjustStock.mockResolvedValue({ applied: 0, clamped: true });

    await expenseService.remove(STORE_ID, 'expense-1');

    // No ADJUSTMENT movement is logged when nothing actually changed.
    expect(inventoryRepository.insertMovement).not.toHaveBeenCalled();
    expect(expenseRepository.remove).toHaveBeenCalledWith(FAKE_CONN, STORE_ID, 'expense-1');
  });
});

describe('expenseService.monthlyReport', () => {
  test('shapes totals to match the spec response (summary/counts/categories)', async () => {
    expenseRepository.monthlySummaryByType.mockResolvedValue([
      { expense_type: 'APPROVISIONNEMENT', count: 8, amount: '12480.00' },
      { expense_type: 'CHARGE_FIXE', count: 5, amount: '7570.00' },
      { expense_type: 'AUTRE', count: 3, amount: '1240.00' },
    ]);
    expenseRepository.monthlySummaryByCategory.mockResolvedValue([
      { category: 'Café', expense_type: 'APPROVISIONNEMENT', count: 1, amount: '5100.00' },
    ]);

    const result = await expenseService.monthlyReport(STORE_ID, 2026, 9);

    expect(result.summary).toEqual({
      supplies: '12480.00',
      fixed: '7570.00',
      other: '1240.00',
      total: '21290.00',
    });
    expect(result.count).toBe(16);
    expect(result.categories[0]).toEqual(
      expect.objectContaining({ category: 'Café', amount: '5100.00' })
    );
  });
});
