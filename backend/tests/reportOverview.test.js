process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db', () => ({
  pool: { query: jest.fn(), getConnection: jest.fn() },
  withTransaction: jest.fn(),
}));
jest.mock('../src/repositories/saleRepository', () => ({}));
jest.mock('../src/repositories/userRepository', () => ({}));
jest.mock('../src/services/ingredientService', () => ({
  lowStock: jest.fn().mockResolvedValue([]),
}));

const overviewService = require('../src/services/reportOverviewService');

const STORE_ID = 'store-1';
const RANGE = {
  start: new Date(2026, 8, 17, 0, 0, 0, 0),
  end: new Date(2026, 8, 18, 23, 59, 59, 999),
};

/**
 * A fake connection that answers each of buildOverview's queries with rows
 * shaped exactly as mysql2 returns them (DECIMAL -> string, COUNT -> number).
 * Routed by a distinctive fragment of each statement.
 */
function fakeDb(overrides = {}) {
  const routes = {
    'FROM stores': [{ name: 'Café Test', address: '1 rue X', phone: '0600', currency: 'MAD' }],
    'tax_total), 0)': [{ sale_count: 6, revenue: '265.00', tax_total: '9.00', discount_total: '2.00' }],
    'GROUP BY s.user_id': [
      { cashier_id: 'u1', items_sold: '8' },
      { cashier_id: 'u2', items_sold: '3' },
    ],
    'AS items_sold': [{ items_sold: '11' }],
    'HOUR(occurred_at)': [
      { hour_of_day: 8, orders: 2, revenue: '80.00' },
      { hour_of_day: 12, orders: 2, revenue: '135.00' },
      { hour_of_day: 13, orders: 1, revenue: '40.00' },
      { hour_of_day: 23, orders: 1, revenue: '10.00' },
    ],
    DATE_FORMAT: [
      { bucket: '2026-09-17', revenue: '155.00', sale_count: 3 },
      { bucket: '2026-09-18', revenue: '110.00', sale_count: 3 },
    ],
    'GROUP BY p.payment_method': [
      { method: 'CASH', tx_count: 4, amount: '170.00' },
      { method: 'CARD', tx_count: 1, amount: '30.00' },
    ],
    change_given: [
      {
        collected: '150.00',
        outstanding: '115.00',
        change_given: '50.00',
        unpaid_count: '1',
        unpaid_amount: '75.00',
        partial_count: '1',
        partial_remaining: '40.00',
      },
    ],
    'GROUP BY u.id': [
      { cashier_id: 'u1', cashier_name: 'Ahmed', role: 'cashier', sale_count: 4, revenue: '175.00' },
      { cashier_id: 'u2', cashier_name: 'Sara', role: 'cashier', sale_count: 2, revenue: '90.00' },
    ],
    'GROUP BY si.product_id': [
      { product_id: 'p1', name: 'Café', quantity: '7', revenue: '150.00' },
      { product_id: 'p2', name: 'Jus', quantity: '4', revenue: '115.00' },
    ],
    'FROM expenses': [
      { category: 'Café', amount: '200.00', expense_count: 2 },
      { category: 'Électricité', amount: '50.00', expense_count: 1 },
    ],
    'GROUP BY sale_status': [{ sale_status: 'COMPLETED', c: 6 }, { sale_status: 'CANCELLED', c: 1 }],
    'SELECT s.id, s.user_id': [],
    ...overrides,
  };
  return {
    query: jest.fn(async (sql) => {
      const key = Object.keys(routes).find((needle) => sql.includes(needle));
      if (!key) throw new Error(`Unrouted query in test: ${sql.slice(0, 80)}`);
      const rows = routes[key];
      // stores/totals/items/settlement are single-row reads: `const [[row]]`
      return [rows];
    }),
  };
}

describe('reportOverviewService.buildOverview', () => {
  test('KPIs, hourly table, payments and cashiers all add up to the same revenue', async () => {
    const report = await overviewService.buildOverview(fakeDb(), STORE_ID, RANGE, { periodKey: 'custom' });

    expect(report.kpis).toEqual({
      revenue: '265.00',
      sale_count: 6,
      items_sold: 11,
      average_ticket: '44.17',
      expenses: '250.00',
      estimated_result: '15.00',
    });
    expect(report.orders_by_hour.total).toEqual({ orders: 6, revenue: '265.00' });
    expect(report.payments.total_collected).toBe('150.00');
    expect(report.payments.outstanding).toBe('115.00');
    expect(report.integrity).toEqual({ ok: true, failed: [] });
  });

  test('the hourly table has 24 zero-filled rows keyed by the sale hour', async () => {
    const report = await overviewService.buildOverview(fakeDb(), STORE_ID, RANGE, {});
    const hours = report.orders_by_hour.hours;

    expect(hours).toHaveLength(24);
    expect(hours[8]).toEqual({ hour: 8, label: '08:00 - 09:00', orders: 2, revenue: '80.00' });
    expect(hours[23].label).toBe('23:00 - 00:00');
    expect(hours[3]).toEqual({ hour: 3, label: '03:00 - 04:00', orders: 0, revenue: '0.00' });
  });

  test('change handed back is taken out of cash, so the drawer holds only what was kept', async () => {
    const report = await overviewService.buildOverview(fakeDb(), STORE_ID, RANGE, {});
    const cash = report.payments.methods.find((m) => m.method === 'CASH');
    const card = report.payments.methods.find((m) => m.method === 'CARD');

    expect(cash).toEqual({ method: 'CASH', amount: '120.00', count: 4, percent: 80, in_drawer: '120.00' });
    expect(card).toEqual({ method: 'CARD', amount: '30.00', count: 1, percent: 20, in_drawer: '0.00' });
    expect(report.payments.in_drawer).toBe('120.00');
    expect(report.payments.change_given).toBe('50.00');
  });

  test('cashier rows merge item counts and compute the average ticket from cents', async () => {
    const report = await overviewService.buildOverview(fakeDb(), STORE_ID, RANGE, {});
    expect(report.cashiers.map((c) => [c.name, c.sale_count, c.items_sold, c.revenue, c.average_ticket])).toEqual([
      ['Ahmed', 4, 8, '175.00', '43.75'],
      ['Sara', 2, 3, '90.00', '45.00'],
    ]);
  });

  test('expenses carry a percentage per category', async () => {
    const report = await overviewService.buildOverview(fakeDb(), STORE_ID, RANGE, {});
    expect(report.expenses.by_category.map((c) => [c.category, c.amount, c.percent])).toEqual([
      ['Café', '200.00', 80],
      ['Électricité', '50.00', 20],
    ]);
  });

  test('only counts sales the caller asked for: every query is scoped to the store and period', async () => {
    const db = fakeDb();
    await overviewService.buildOverview(db, STORE_ID, RANGE, {});
    const salesQueries = db.query.mock.calls.filter(([sql]) => /FROM sales|JOIN sales/.test(sql));

    expect(salesQueries.length > 5).toBe(true);
    salesQueries.forEach(([, params]) => {
      expect(params[0]).toBe(STORE_ID);
      expect(params[1]).toBe(RANGE.start);
      expect(params[2]).toBe(RANGE.end);
    });
  });

  test('flags an integrity failure instead of showing two different totals silently', async () => {
    const db = fakeDb({
      'HOUR(occurred_at)': [{ hour_of_day: 8, orders: 2, revenue: '80.00' }],
    });
    const report = await overviewService.buildOverview(db, STORE_ID, RANGE, {});

    expect(report.integrity.ok).toBe(false);
    expect(report.integrity.failed).toEqual(['hourly_orders', 'hourly_revenue']);
  });

  test('a period with no sales gives zeros, an empty hourly total and no payment rows', async () => {
    const db = fakeDb({
      'tax_total), 0)': [{ sale_count: 0, revenue: '0.00', tax_total: '0.00', discount_total: '0.00' }],
      'AS items_sold': [{ items_sold: '0' }],
      'GROUP BY s.user_id': [],
      'HOUR(occurred_at)': [],
      DATE_FORMAT: [],
      'GROUP BY p.payment_method': [],
      change_given: [
        {
          collected: '0.00',
          outstanding: '0.00',
          change_given: '0.00',
          unpaid_count: '0',
          unpaid_amount: '0.00',
          partial_count: '0',
          partial_remaining: '0.00',
        },
      ],
      'GROUP BY u.id': [],
      'GROUP BY si.product_id': [],
      'FROM expenses': [],
      'GROUP BY sale_status': [],
    });
    const report = await overviewService.buildOverview(db, STORE_ID, RANGE, {});

    expect(report.kpis.sale_count).toBe(0);
    expect(report.kpis.average_ticket).toBe('0.00');
    expect(report.orders_by_hour.total).toEqual({ orders: 0, revenue: '0.00' });
    expect(report.payments.methods).toEqual([]);
    expect(report.cashiers).toEqual([]);
    expect(report.integrity.ok).toBe(true);
  });

  test('the full sales list is only fetched when asked for, and is capped', async () => {
    const withoutList = await overviewService.buildOverview(fakeDb(), STORE_ID, RANGE, {});
    expect(withoutList.sales).toBeNull();

    const rows = Array.from({ length: overviewService.MAX_SALES_LIST + 1 }, (_, i) => ({
      id: `s${i}`,
      user_id: 'u1',
      cashier_name: 'Ahmed',
      subtotal: '1.00',
      discount_total: '0.00',
      tax_total: '0.00',
      total: '1.00',
      payment_status: 'PAID',
      sale_status: 'COMPLETED',
      occurred_at: '2026-09-17 10:00:00',
      items_count: 1,
      paid_amount: '1.00',
      payment_method_count: 1,
      last_payment_method: 'CASH',
    }));
    const withList = await overviewService.buildOverview(
      fakeDb({ 'SELECT s.id, s.user_id': rows }),
      STORE_ID,
      RANGE,
      { includeSales: true }
    );
    expect(withList.sales).toHaveLength(overviewService.MAX_SALES_LIST);
    expect(withList.sales_truncated).toBe(true);
  });
});

describe('reportOverviewService.allocateChange', () => {
  test('takes change out of cash first', () => {
    const methods = [
      { method: 'CARD', rawCents: 3000, netCents: 3000 },
      { method: 'CASH', rawCents: 17000, netCents: 17000 },
    ];
    overviewService.allocateChange(methods, 5000);
    expect(methods.find((m) => m.method === 'CASH').netCents).toBe(12000);
    expect(methods.find((m) => m.method === 'CARD').netCents).toBe(3000);
  });

  test('spills to the next method only if cash cannot cover the change', () => {
    const methods = [
      { method: 'CASH', rawCents: 1000, netCents: 1000 },
      { method: 'TRANSFER', rawCents: 5000, netCents: 5000 },
    ];
    overviewService.allocateChange(methods, 2500);
    expect(methods.find((m) => m.method === 'CASH').netCents).toBe(0);
    expect(methods.find((m) => m.method === 'TRANSFER').netCents).toBe(3500);
  });

  test('no change leaves every amount untouched', () => {
    const methods = [{ method: 'CASH', rawCents: 1000, netCents: 1000 }];
    overviewService.allocateChange(methods, 0);
    expect(methods[0].netCents).toBe(1000);
  });
});

describe('reportOverviewService.pickGranularity', () => {
  const day = (d, h = 0) => new Date(2026, 8, d, h, 0, 0, 0);
  test('one day -> hourly, a month -> daily, a year -> monthly', () => {
    expect(overviewService.pickGranularity(day(18), day(18, 23))).toBe('hour');
    expect(overviewService.pickGranularity(day(1), day(30))).toBe('day');
    expect(overviewService.pickGranularity(new Date(2026, 0, 1), day(18))).toBe('month');
  });
});

describe('reportOverviewService.ordersByHour', () => {
  const { pool } = require('../src/config/db');

  test('rejects a range whose start is after its end', async () => {
    await expect(
      overviewService.ordersByHour(STORE_ID, { period: 'custom', from: '2026-09-18', to: '2026-09-17' })
    ).rejects.toMatchObject({ code: 'INVALID_RANGE', statusCode: 400 });
  });

  test('returns the period, the 24 hours and the total', async () => {
    pool.query.mockResolvedValue([[{ hour_of_day: 12, orders: 5, revenue: '250.50' }]]);
    const result = await overviewService.ordersByHour(STORE_ID, {
      period: 'custom',
      from: '2026-09-18',
      to: '2026-09-18',
    });

    expect(result.period).toEqual({
      key: 'custom',
      start: '2026-09-18 00:00:00',
      end: '2026-09-18 23:59:59',
      days: 1,
    });
    expect(result.hours).toHaveLength(24);
    expect(result.hours[12]).toEqual({ hour: 12, label: '12:00 - 13:00', orders: 5, revenue: '250.50' });
    expect(result.total).toEqual({ orders: 5, revenue: '250.50' });
  });
});
