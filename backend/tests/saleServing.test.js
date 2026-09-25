process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');
jest.mock('../src/repositories/saleRepository');
jest.mock('../src/repositories/syncRepository');
jest.mock('../src/repositories/paymentRepository');
jest.mock('../src/repositories/productRepository');
jest.mock('../src/repositories/inventoryRepository');
jest.mock('../src/repositories/recipeRepository');
jest.mock('../src/repositories/ingredientRepository');
jest.mock('../src/repositories/ingredientMovementRepository');

const { withTransaction } = require('../src/config/db');
const saleRepository = require('../src/repositories/saleRepository');
const syncRepository = require('../src/repositories/syncRepository');
const saleService = require('../src/services/saleService');

const STORE = 'store-1';
const ME = { id: 'cashier-1', role: 'cashier' };
const CONN = {};
const OP = '11111111-1111-4111-8111-111111111111';

const sale = (o = {}) => ({
  id: 'sale-1',
  user_id: ME.id,
  sale_status: 'COMPLETED',
  served_at: null,
  ...o,
});

beforeEach(() => {
  jest.clearAllMocks();
  withTransaction.mockImplementation((work) => work(CONN));
  saleRepository.findById.mockResolvedValue({ id: 'sale-1' });
  saleRepository.markServed.mockResolvedValue(true);
  saleRepository.markReprinted.mockResolvedValue(true);
  syncRepository.findByOperationId.mockResolvedValue(null);
});

describe('saleService.serveSale', () => {
  test('serves the order for the AUTHENTICATED user, with a server-side timestamp', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale());
    const out = await saleService.serveSale(STORE, ME, 'sale-1');

    expect(out.alreadyApplied).toBe(false);
    expect(saleRepository.markServed).toHaveBeenCalledTimes(1);
    const [conn, store, saleId, userId, servedAt] = saleRepository.markServed.mock.calls[0];
    expect([conn, store, saleId, userId]).toEqual([CONN, STORE, 'sale-1', ME.id]);
    expect(servedAt).toBeInstanceOf(Date);
    // no operation id sent -> nothing recorded
    expect(syncRepository.record).not.toHaveBeenCalled();
  });

  test('unknown sale -> 404 and nothing is written', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(null);
    await expect(saleService.serveSale(STORE, ME, 'nope')).rejects.toMatchObject({
      statusCode: 404,
      code: 'SALE_NOT_FOUND',
    });
    expect(saleRepository.markServed).not.toHaveBeenCalled();
  });

  test("another cashier's order -> 403 and nothing is written", async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ user_id: 'someone-else' }));
    await expect(saleService.serveSale(STORE, ME, 'sale-1')).rejects.toMatchObject({
      statusCode: 403,
    });
    expect(saleRepository.markServed).not.toHaveBeenCalled();
  });

  test('already served -> 409 with the spec message, served_at never rewritten', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ served_at: '2026-09-18 14:35:00' }));
    await expect(saleService.serveSale(STORE, ME, 'sale-1')).rejects.toMatchObject({
      statusCode: 409,
      code: 'SALE_ALREADY_SERVED',
      message: 'Cette commande a déjà été servie.',
    });
    expect(saleRepository.markServed).not.toHaveBeenCalled();
  });

  test('losing the atomic race (0 rows affected) is reported as already served', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale());
    saleRepository.markServed.mockResolvedValue(false);
    await expect(saleService.serveSale(STORE, ME, 'sale-1')).rejects.toMatchObject({
      code: 'SALE_ALREADY_SERVED',
    });
    expect(syncRepository.record).not.toHaveBeenCalled();
  });

  test.each(['CANCELLED', 'REFUNDED'])('a %s order cannot be served', async (status) => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ sale_status: status }));
    await expect(saleService.serveSale(STORE, ME, 'sale-1')).rejects.toMatchObject({
      code: 'SALE_NOT_SERVABLE',
    });
    expect(saleRepository.markServed).not.toHaveBeenCalled();
  });

  test('does not depend on / change the payment status (unpaid orders can be served)', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ payment_status: 'PENDING' }));
    await saleService.serveSale(STORE, ME, 'sale-1');
    expect(saleRepository.markServed).toHaveBeenCalled();
    expect(saleRepository.updatePaymentStatus).not.toHaveBeenCalled();
  });

  test('records the operation id once, atomically with the serve', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale());
    await saleService.serveSale(STORE, ME, 'sale-1', { clientOperationId: OP });
    expect(syncRepository.record).toHaveBeenCalledTimes(1);
    expect(syncRepository.record.mock.calls[0][0]).toBe(CONN); // same transaction
    expect(syncRepository.record.mock.calls[0][1]).toMatchObject({
      operationId: OP,
      entityType: 'sale_served',
      entityId: 'sale-1',
      status: 'applied',
    });
  });

  test('a retry with the same operation id is a success and creates no second event', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ served_at: '2026-09-18 14:35:00' }));
    syncRepository.findByOperationId.mockResolvedValue({ entity_type: 'sale_served', entity_id: 'sale-1' });
    const out = await saleService.serveSale(STORE, ME, 'sale-1', { clientOperationId: OP });
    expect(out.alreadyApplied).toBe(true);
    expect(saleRepository.markServed).not.toHaveBeenCalled();
    expect(syncRepository.record).not.toHaveBeenCalled();
  });

  test('an operation id already used for something else is refused', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale());
    syncRepository.findByOperationId.mockResolvedValue({ entity_type: 'sale', entity_id: 'other' });
    await expect(
      saleService.serveSale(STORE, ME, 'sale-1', { clientOperationId: OP })
    ).rejects.toMatchObject({ code: 'OPERATION_ID_REUSED' });
    expect(saleRepository.markServed).not.toHaveBeenCalled();
  });

  test('never deletes or edits sales/items/payments (only the serving repo call is used)', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale());
    await saleService.serveSale(STORE, ME, 'sale-1');
    const used = Object.entries(saleRepository)
      .filter(([, fn]) => jest.isMockFunction(fn) && fn.mock.calls.length > 0)
      .map(([name]) => name)
      .sort();
    expect(used).toEqual(['findById', 'findByIdForUpdate', 'markServed']);
  });
});

describe('saleService.reprintSale', () => {
  test('records the print without touching served state', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ served_at: '2026-09-18 14:35:00' }));
    await saleService.reprintSale(STORE, ME, 'sale-1');
    expect(saleRepository.markReprinted).toHaveBeenCalledTimes(1);
    expect(saleRepository.markServed).not.toHaveBeenCalled();
  });

  test('refuses an order that was never served', async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale());
    await expect(saleService.reprintSale(STORE, ME, 'sale-1')).rejects.toMatchObject({
      statusCode: 409,
      code: 'SALE_NOT_SERVED',
    });
    expect(saleRepository.markReprinted).not.toHaveBeenCalled();
  });

  test("refuses another cashier's order", async () => {
    saleRepository.findByIdForUpdate.mockResolvedValue(sale({ user_id: 'x', served_at: '2026-01-01 10:00:00' }));
    await expect(saleService.reprintSale(STORE, ME, 'sale-1')).rejects.toMatchObject({ statusCode: 403 });
    expect(saleRepository.markReprinted).not.toHaveBeenCalled();
  });
});

describe('saleRepository serving SQL (real module, fake connection)', () => {
  const real = jest.requireActual('../src/repositories/saleRepository');

  test('markServed only claims an UNSERVED, COMPLETED order of the given cashier', async () => {
    const conn = { query: jest.fn().mockResolvedValue([{ affectedRows: 1 }]) };
    const when = new Date('2026-09-18T14:35:00');
    expect(await real.markServed(conn, 'st', 'sa', 'u1', when)).toBe(true);
    const [sql, params] = conn.query.mock.calls[0];
    expect(sql).toMatch(/served_at IS NULL/);
    expect(sql).toMatch(/user_id = \?/);
    expect(sql).toMatch(/sale_status = 'COMPLETED'/);
    expect(sql).not.toMatch(/DELETE/i);
    expect(params).toEqual([when, 'u1', when, 'u1', 'sa', 'st', 'u1']);

    conn.query.mockResolvedValue([{ affectedRows: 0 }]);
    expect(await real.markServed(conn, 'st', 'sa', 'u1', when)).toBe(false);
  });

  test('markReprinted never writes served_at / served_by', async () => {
    const conn = { query: jest.fn().mockResolvedValue([{ affectedRows: 1 }]) };
    await real.markReprinted(conn, 'st', 'sa', 'u1', new Date());
    const [sql] = conn.query.mock.calls[0];
    const setClause = sql.split('WHERE')[0];
    expect(setClause).not.toMatch(/served_at|served_by/);
    expect(sql).toMatch(/served_at IS NOT NULL/);
  });
});
