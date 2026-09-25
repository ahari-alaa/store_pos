process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');

const { pool } = require('../src/config/db');
const svc = require('../src/services/cashierReportService');

const USER = { id: 'cashier-1', name: 'Ahmed' };
const RANGE = { start: new Date('2026-09-18T00:00:00'), end: new Date('2026-09-18T23:59:59') };

/** Fake db: answers by SQL fragment and records every query. */
function fakeDb(overrides = {}) {
  const calls = [];
  const db = {
    calls,
    query: jest.fn(async (sql, params) => {
      calls.push({ sql, params });
      const table = [
        [/FROM stores/, [[{ name: 'Store', address: null, phone: null, currency: 'MAD' }]]],
        [/COUNT\(\*\) AS order_count/, [[{ order_count: 2, revenue: '58.00' }]]],
        [/AS items_sold/, [[{ items_sold: 5 }]]],
        [/GROUP BY p\.payment_method/, [[{ method: 'CASH', tx_count: 2, amount: '60.00' }]]],
        [/AS collected/, [[{ collected: '58.00', outstanding: '0.00', change_given: '2.00', unpaid_count: 0, unpaid_amount: '0', partial_count: 0, partial_remaining: '0' }]]],
        [/GROUP BY si\.product_id/, [[
          { product_id: 'p1', name: 'Café', quantity: 3, revenue: '30.00' },
          { product_id: 'p2', name: 'Croissant', quantity: 2, revenue: '28.00' },
        ]]],
        [/AS to_serve_total/, [[{ to_serve_total: 1 }]]],
        [/AS served_in_period/, [[{ served_in_period: 1 }]]],
      ];
      for (const [re, out] of table) if (re.test(sql)) return overrides[String(re)] || out;
      throw new Error(`unexpected SQL in test: ${sql.slice(0, 80)}`);
    }),
  };
  return db;
}

describe('cashierReportService.buildMyReport', () => {
  test('EVERY query is scoped to the cashier (s.user_id = ?) and the id is bound', async () => {
    const db = fakeDb();
    await svc.buildMyReport(db, 'store-1', USER, RANGE, {});
    const salesQueries = db.calls.filter((c) => /FROM sales s|JOIN sales s/.test(c.sql));
    expect(salesQueries.length).toBeGreaterThanOrEqual(6);
    for (const { sql, params } of salesQueries) {
      expect(sql).toMatch(/s\.user_id = \?/);
      expect(params).toContain(USER.id);
      expect(sql).toMatch(/sale_status = 'COMPLETED'/);
    }
  });

  test('revenue/product/count figures never depend on serving state', async () => {
    const db = fakeDb();
    await svc.buildMyReport(db, 'store-1', USER, RANGE, {});
    const figures = db.calls.filter((c) =>
      /order_count|items_sold|GROUP BY si\.product_id|AS collected|payment_method/.test(c.sql)
    );
    for (const { sql } of figures) expect(sql).not.toMatch(/served_at|served_by|receipt_printed/);
  });

  test('computes the KPIs from the SQL results (integer-cent maths)', async () => {
    const r = await svc.buildMyReport(fakeDb(), 'store-1', USER, RANGE, {});
    expect(r.kpis).toEqual({
      revenue: '58.00',
      order_count: 2,
      items_sold: 5,
      average_ticket: '29.00',
      collected: '58.00',
      outstanding: '0.00',
    });
    expect(r.products.map((p) => [p.name, p.quantity, p.revenue])).toEqual([
      ['Café', 3, '30.00'],
      ['Croissant', 2, '28.00'],
    ]);
    expect(r.serving).toEqual({ to_serve_total: 1, served_in_period: 1 });
    expect(r.cashier).toEqual({ id: 'cashier-1', name: 'Ahmed' });
    expect(r.integrity.ok).toBe(true);
    expect(r.orders).toBeNull();
  });

  test('average is 0.00 (not NaN) when the cashier sold nothing', async () => {
    const db = fakeDb({
      [String(/COUNT\(\*\) AS order_count/)]: [[{ order_count: 0, revenue: '0' }]],
    });
    const r = await svc.buildMyReport(db, 'store-1', USER, RANGE, {});
    expect(r.kpis.average_ticket).toBe('0.00');
  });
});

describe('cashierReportService.orderFilter / myOrders', () => {
  test('always starts with store + THIS cashier + COMPLETED', () => {
    const { whereSql, params } = svc.orderFilter('st', 'u1', {});
    expect(whereSql).toMatch(/^s\.store_id = \? AND s\.user_id = \? AND s\.sale_status = 'COMPLETED'/);
    expect(params).toEqual(['st', 'u1']);
  });

  test('serve/payment filters map to the right predicates', () => {
    expect(svc.orderFilter('s', 'u', { serveStatus: 'to_serve' }).whereSql).toMatch(/served_at IS NULL/);
    expect(svc.orderFilter('s', 'u', { serveStatus: 'served' }).whereSql).toMatch(/served_at IS NOT NULL/);
    expect(svc.orderFilter('s', 'u', { paymentStatus: 'UNPAID' }).whereSql).toMatch(/IN \('PENDING', 'PARTIALLY_PAID'\)/);
    expect(svc.orderFilter('s', 'u', { paymentStatus: 'PAID' }).params).toEqual(['s', 'u', 'PAID']);
  });

  test('to_serve is oldest-first; the cashier id is bound in both queries', async () => {
    pool.query
      .mockResolvedValueOnce([[]])
      .mockResolvedValueOnce([[{ total: 0 }]]);
    await svc.myOrders('st', 'u1', { serveStatus: 'to_serve' });
    const [listSql, listParams] = pool.query.mock.calls[0];
    expect(listSql).toMatch(/ORDER BY s\.occurred_at ASC/);
    expect(listParams.slice(0, 2)).toEqual(['st', 'u1']);
    expect(pool.query.mock.calls[1][1].slice(0, 2)).toEqual(['st', 'u1']);
  });
});
