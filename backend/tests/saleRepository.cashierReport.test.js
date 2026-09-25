process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');

const { pool } = require('../src/config/db');
const saleRepository = require('../src/repositories/saleRepository');

beforeEach(() => {
  jest.clearAllMocks();
});

describe('saleRepository.cashierSalesSummary', () => {
  test('binds store_id, user_id and the from/to range as query parameters', async () => {
    pool.query.mockResolvedValue([
      [{ order_count: 5, total_sales: '470.00', paid_count: 3, not_paid_count: 1, partially_paid_count: 1 }],
    ]);

    const row = await saleRepository.cashierSalesSummary(
      'store-1',
      'cashier-1',
      '2026-09-13 00:00:00',
      '2026-09-13 23:59:59'
    );

    expect(row).toEqual({
      order_count: 5,
      total_sales: '470.00',
      paid_count: 3,
      not_paid_count: 1,
      partially_paid_count: 1,
    });

    const [sql, params] = pool.query.mock.calls[0];
    expect(params).toEqual(['store-1', 'cashier-1', '2026-09-13 00:00:00', '2026-09-13 23:59:59']);
    // Must filter by BOTH store_id and user_id — dropping either would
    // either leak another store's data or another cashier's orders.
    expect(sql).toMatch(/s\.store_id = \?/);
    expect(sql).toMatch(/s\.user_id = \?/);
    expect(sql).toMatch(/s\.occurred_at BETWEEN \? AND \?/);
  });
});

describe('saleRepository.cashierSalesByDay', () => {
  test('groups by DATE(occurred_at) and orders ascending, scoped the same way as the summary', async () => {
    pool.query.mockResolvedValue([
      [
        { day: '2026-09-01', order_count: 32, total_sales: '3850.00', paid_count: 31, not_paid_count: 1, partially_paid_count: 0 },
      ],
    ]);

    const rows = await saleRepository.cashierSalesByDay(
      'store-1',
      'cashier-1',
      '2026-09-01 00:00:00',
      '2026-09-30 23:59:59'
    );

    expect(rows).toHaveLength(1);
    expect(rows[0].day).toBe('2026-09-01');

    const [sql, params] = pool.query.mock.calls[0];
    expect(params).toEqual(['store-1', 'cashier-1', '2026-09-01 00:00:00', '2026-09-30 23:59:59']);
    expect(sql).toMatch(/s\.store_id = \?/);
    expect(sql).toMatch(/s\.user_id = \?/);
    expect(sql).toMatch(/GROUP BY DATE\(s\.occurred_at\)/);
    expect(sql).toMatch(/ORDER BY day ASC/);
  });
});
