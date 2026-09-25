process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/repositories/syncRepository');
jest.mock('../src/services/saleService');
jest.mock('../src/services/expenseService');
jest.mock('../src/services/inventoryService');

const syncRepository = require('../src/repositories/syncRepository');
const saleService = require('../src/services/saleService');
const expenseService = require('../src/services/expenseService');
const syncService = require('../src/services/syncService');

const STORE_ID = 'store-1';
const CASHIER = { id: 'user-cashier', role: 'cashier' };
const MANAGER = { id: 'user-manager', role: 'manager' };

function saleOperation(overrides = {}) {
  return {
    operation_id: 'op-1',
    entity_type: 'sale',
    entity_id: 'sale-local-1',
    operation_type: 'create',
    client_created_at: new Date().toISOString(),
    payload: {
      client_operation_id: '11111111-1111-4111-8111-111111111111',
      items: [{ product_id: '55555555-5555-4555-8555-555555555555', quantity: 1, unit_price: 5 }],
      payments: [{ amount: 5, payment_method: 'CASH' }],
    },
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  syncRepository.findByOperationId.mockResolvedValue(null);
  syncRepository.record.mockResolvedValue(undefined);
});

describe('syncService.pushOperations — idempotency', () => {
  test('an operation_id already recorded on the server is reported as duplicate and never re-applied', async () => {
    syncRepository.findByOperationId.mockResolvedValue({
      operation_id: 'op-1',
      entity_id: 'sale-local-1',
    });

    const { results, summary } = await syncService.pushOperations(STORE_ID, MANAGER, [
      saleOperation(),
    ]);

    expect(results[0].status).toBe('duplicate');
    expect(summary.duplicate).toBe(1);
    expect(saleService.createSale).not.toHaveBeenCalled();
  });
});

describe('syncService.pushOperations — authorization', () => {
  test('a cashier cannot push an expense operation through sync (server-side enforcement)', async () => {
    const op = {
      operation_id: 'op-2',
      entity_type: 'expense',
      entity_id: 'expense-local-1',
      operation_type: 'create',
      client_created_at: new Date().toISOString(),
      payload: {
        client_operation_id: '22222222-2222-4222-8222-222222222222',
        amount: 20,
        category: 'Supplies',
      },
    };

    const { results, summary } = await syncService.pushOperations(STORE_ID, CASHIER, [op]);

    expect(results[0].status).toBe('failed');
    expect(results[0].error).toBe('PERMISSION_DENIED');
    expect(summary.failed).toBe(1);
    expect(expenseService.create).not.toHaveBeenCalled();
  });

  test('a manager CAN push an expense operation through sync', async () => {
    expenseService.create.mockResolvedValue({ expense: { id: 'expense-1' }, wasDuplicate: false });
    const op = {
      operation_id: 'op-3',
      entity_type: 'expense',
      entity_id: 'expense-local-2',
      operation_type: 'create',
      client_created_at: new Date().toISOString(),
      payload: { client_operation_id: '33333333-3333-4333-8333-333333333333', amount: 20, category: 'Supplies' },
    };

    const { results } = await syncService.pushOperations(STORE_ID, MANAGER, [op]);

    expect(results[0].status).toBe('applied');
    expect(expenseService.create).toHaveBeenCalledWith(STORE_ID, MANAGER.id, expect.objectContaining({
      amount: 20,
      category: 'Supplies',
    }));
  });
});

describe('syncService.pushOperations — partial batch failure', () => {
  test('one failing operation does not block the others in the same batch', async () => {
    saleService.createSale
      .mockResolvedValueOnce({ sale: { id: 'sale-ok' }, wasDuplicate: false })
      .mockRejectedValueOnce(new Error('boom'));

    const goodOp = saleOperation({ operation_id: 'op-good' });
    const badOp = saleOperation({ operation_id: 'op-bad', payload: { ...saleOperation().payload, client_operation_id: '44444444-4444-4444-8444-444444444444' } });

    const { results, summary } = await syncService.pushOperations(STORE_ID, MANAGER, [
      goodOp,
      badOp,
    ]);

    expect(results).toHaveLength(2);
    expect(results[0].status).toBe('applied');
    expect(results[1].status).toBe('failed');
    expect(summary).toEqual({ applied: 1, duplicate: 0, failed: 1 });
  });

  test('an unsupported entity_type is recorded as failed rather than crashing the batch', async () => {
    const { results } = await syncService.pushOperations(STORE_ID, MANAGER, [
      { ...saleOperation(), entity_type: 'unknown_thing' },
    ]);

    expect(results[0].status).toBe('failed');
    expect(syncRepository.record).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ status: 'failed' })
    );
  });
});
