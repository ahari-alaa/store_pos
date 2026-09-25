process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');
jest.mock('../src/repositories/saleRepository');
jest.mock('../src/repositories/userRepository');

const saleRepository = require('../src/repositories/saleRepository');
const userRepository = require('../src/repositories/userRepository');
const reportService = require('../src/services/reportService');

const STORE_ID = 'store-1';
const OTHER_STORE_ID = 'store-2';
const CASHIER_ID = 'cashier-1';

const CASHIER = {
  id: CASHIER_ID,
  store_id: STORE_ID,
  name: 'Alaa',
  email: 'alaa@example.com',
  role: 'cashier',
  is_active: 1,
};

beforeEach(() => {
  jest.clearAllMocks();
  // Rapports §11 payment breakdown — irrelevant to most of the tests
  // below, so default it to "no payments" and let the dedicated
  // describe block further down override it.
  saleRepository.cashierPaymentBreakdown.mockResolvedValue([]);
});

describe('reportService.cashierSalesReport — multi-store security', () => {
  test('rejects a cashier_id that does not belong to the authenticated store', async () => {
    // findByIdForStore is itself store-scoped — from a different store it
    // must behave exactly as if the cashier didn't exist at all, never
    // leaking whether the id is valid in some OTHER store.
    userRepository.findByIdForStore.mockResolvedValue(null);

    await expect(
      reportService.cashierSalesReport(OTHER_STORE_ID, {
        cashier_id: CASHIER_ID,
        from: '2026-09-01 00:00:00',
        to: '2026-09-01 23:59:59',
      })
    ).rejects.toMatchObject({ code: 'CASHIER_NOT_FOUND', statusCode: 404 });

    expect(userRepository.findByIdForStore).toHaveBeenCalledWith(OTHER_STORE_ID, CASHIER_ID);
    // Must never even query sales for a cashier we couldn't confirm
    // belongs to this store.
    expect(saleRepository.cashierSalesSummary).not.toHaveBeenCalled();
  });

  test('scopes the sales query to the authenticated store, not just the cashier id', async () => {
    userRepository.findByIdForStore.mockResolvedValue(CASHIER);
    saleRepository.cashierSalesSummary.mockResolvedValue({
      order_count: 0,
      total_sales: '0.00',
      paid_count: 0,
      not_paid_count: 0,
      partially_paid_count: 0,
    });

    await reportService.cashierSalesReport(STORE_ID, {
      cashier_id: CASHIER_ID,
      from: '2026-09-01 00:00:00',
      to: '2026-09-01 23:59:59',
    });

    expect(saleRepository.cashierSalesSummary).toHaveBeenCalledWith(
      STORE_ID,
      CASHIER_ID,
      '2026-09-01 00:00:00',
      '2026-09-01 23:59:59'
    );
  });
});

describe('reportService.cashierSalesReport — day report (no group_by)', () => {
  test('returns the cashier profile + summary, and never calls the daily-breakdown query', async () => {
    userRepository.findByIdForStore.mockResolvedValue(CASHIER);
    saleRepository.cashierSalesSummary.mockResolvedValue({
      order_count: 5,
      total_sales: '470.00',
      paid_count: 3,
      not_paid_count: 1,
      partially_paid_count: 1,
    });

    const result = await reportService.cashierSalesReport(STORE_ID, {
      cashier_id: CASHIER_ID,
      from: '2026-09-13 00:00:00',
      to: '2026-09-13 23:59:59',
    });

    expect(result.cashier).toEqual({
      id: CASHIER_ID,
      name: 'Alaa',
      email: 'alaa@example.com',
      role: 'cashier',
      is_active: true,
    });
    expect(result.summary).toEqual({
      orders: 5,
      total_sales: '470.00',
      items_sold: 0,
      average_ticket: '94.00',
      paid_orders: 3,
      not_paid_orders: 1,
      partially_paid_orders: 1,
    });
    expect(result.days).toBeUndefined();
    expect(saleRepository.cashierSalesByDay).not.toHaveBeenCalled();
  });
});

describe('reportService.cashierSalesReport — month report (group_by=day)', () => {
  test('includes a daily breakdown alongside the summary', async () => {
    userRepository.findByIdForStore.mockResolvedValue(CASHIER);
    saleRepository.cashierSalesSummary.mockResolvedValue({
      order_count: 70,
      total_sales: '8500.00',
      paid_count: 65,
      not_paid_count: 5,
      partially_paid_count: 0,
    });
    saleRepository.cashierSalesByDay.mockResolvedValue([
      {
        day: '2026-09-01',
        order_count: 32,
        total_sales: '3850.00',
        paid_count: 31,
        not_paid_count: 1,
        partially_paid_count: 0,
      },
      {
        day: '2026-09-02',
        order_count: 38,
        total_sales: '4650.00',
        paid_count: 34,
        not_paid_count: 4,
        partially_paid_count: 0,
      },
    ]);

    const result = await reportService.cashierSalesReport(STORE_ID, {
      cashier_id: CASHIER_ID,
      from: '2026-09-01 00:00:00',
      to: '2026-09-30 23:59:59',
      group_by: 'day',
    });

    expect(saleRepository.cashierSalesByDay).toHaveBeenCalledWith(
      STORE_ID,
      CASHIER_ID,
      '2026-09-01 00:00:00',
      '2026-09-30 23:59:59'
    );
    expect(result.days).toEqual([
      {
        date: '2026-09-01',
        orders: 32,
        total_sales: '3850.00',
        items_sold: 0,
        average_ticket: '120.31',
        paid_orders: 31,
        not_paid_orders: 1,
        partially_paid_orders: 0,
      },
      {
        date: '2026-09-02',
        orders: 38,
        total_sales: '4650.00',
        items_sold: 0,
        average_ticket: '122.37',
        paid_orders: 34,
        not_paid_orders: 4,
        partially_paid_orders: 0,
      },
    ]);
    // Daily figures must sum to the same summary totals (no double
    // counting / dropped rows between the two queries).
    const summedOrders = result.days.reduce((sum, d) => sum + d.orders, 0);
    expect(summedOrders).toBe(result.summary.orders);
  });
});

describe('reportService.cashierSalesReport — payment breakdown (Rapports §11)', () => {
  test('computes amount/count/percent per payment method for this cashier only', async () => {
    userRepository.findByIdForStore.mockResolvedValue(CASHIER);
    saleRepository.cashierSalesSummary.mockResolvedValue({
      order_count: 10,
      total_sales: '1000.00',
      paid_count: 10,
      not_paid_count: 0,
      partially_paid_count: 0,
    });
    saleRepository.cashierPaymentBreakdown.mockResolvedValue([
      { payment_method: 'CASH', tx_count: 7, amount: '750.00' },
      { payment_method: 'CARD', tx_count: 3, amount: '250.00' },
    ]);

    const result = await reportService.cashierSalesReport(STORE_ID, {
      cashier_id: CASHIER_ID,
      from: '2026-09-01 00:00:00',
      to: '2026-09-01 23:59:59',
    });

    expect(saleRepository.cashierPaymentBreakdown).toHaveBeenCalledWith(
      STORE_ID,
      CASHIER_ID,
      '2026-09-01 00:00:00',
      '2026-09-01 23:59:59'
    );
    expect(result.payment_breakdown).toEqual([
      { payment_method: 'CASH', amount: '750.00', transaction_count: 7, percent: 75 },
      { payment_method: 'CARD', amount: '250.00', transaction_count: 3, percent: 25 },
    ]);
  });
});

describe('reportService.cashierSalesReport — named period (Rapports)', () => {
  test('resolves "today" to a concrete range and passes it (not the string "today") to the repository', async () => {
    userRepository.findByIdForStore.mockResolvedValue(CASHIER);
    saleRepository.cashierSalesSummary.mockResolvedValue({
      order_count: 1,
      total_sales: '50.00',
      paid_count: 1,
      not_paid_count: 0,
      partially_paid_count: 0,
    });

    await reportService.cashierSalesReport(STORE_ID, {
      cashier_id: CASHIER_ID,
      period: 'today',
    });

    const [, , calledFrom, calledTo] = saleRepository.cashierSalesSummary.mock.calls[0];
    expect(calledFrom).toBeInstanceOf(Date);
    expect(calledTo).toBeInstanceOf(Date);
    expect(calledFrom.getTime()).toBeLessThanOrEqual(calledTo.getTime());
  });
});

describe('reportService.resolveRange — Rapports quick periods', () => {
  test('"yesterday" is the full previous calendar day', () => {
    const { start, end } = reportService.resolveRange('yesterday');
    const now = new Date();
    const expectedDay = new Date(now);
    expectedDay.setDate(expectedDay.getDate() - 1);
    expect(start.getDate()).toBe(expectedDay.getDate());
    expect(start.getHours()).toBe(0);
    expect(end.getHours()).toBe(23);
    expect(end.getTime() - start.getTime()).toBeLessThan(24 * 60 * 60 * 1000);
  });

  test('"week" starts on Monday', () => {
    const { start } = reportService.resolveRange('week');
    // getDay(): 0 = Sunday, 1 = Monday, ...
    expect(start.getDay()).toBe(1);
    expect(start.getHours()).toBe(0);
  });

  test('"last_week" ends the instant before this week starts', () => {
    const thisWeek = reportService.resolveRange('week');
    const lastWeek = reportService.resolveRange('last_week');
    expect(lastWeek.end.getTime()).toBeLessThan(thisWeek.start.getTime());
    // Whole calendar days, not raw milliseconds: a clock change inside the
    // week makes it 167h or 169h long, which is still exactly 7 days.
    const days = Math.round((thisWeek.start.getTime() - lastWeek.start.getTime()) / (24 * 60 * 60 * 1000));
    expect(days).toBe(7);
    expect(lastWeek.start.getHours()).toBe(0);
    expect(lastWeek.start.getDay()).toBe(1);
  });

  test('"last_month" is the full previous calendar month', () => {
    const now = new Date();
    const { start, end } = reportService.resolveRange('last_month');
    expect(start.getDate()).toBe(1);
    expect(end.getMonth()).toBe(start.getMonth());
    // last_month never bleeds into the current month
    expect(start.getMonth()).not.toBe(now.getMonth() === 0 ? -1 : now.getMonth());
  });

  test('"custom" requires the caller-supplied from/to (falls back to the 30-day default when absent)', () => {
    const { start, end } = reportService.resolveRange('custom', '2026-01-01', '2026-01-31');
    expect(start.getFullYear()).toBe(2026);
    expect(end.getDate()).toBe(31);
  });

  test('"custom" date-only boundaries are LOCAL midnight / end-of-day (the last day is included)', () => {
    const { start, end } = reportService.resolveRange('custom', '2026-09-01', '2026-09-18');
    expect([start.getFullYear(), start.getMonth(), start.getDate()]).toEqual([2026, 8, 1]);
    expect([start.getHours(), start.getMinutes(), start.getSeconds()]).toEqual([0, 0, 0]);
    expect([end.getFullYear(), end.getMonth(), end.getDate()]).toEqual([2026, 8, 18]);
    expect([end.getHours(), end.getMinutes(), end.getSeconds()]).toEqual([23, 59, 59]);
  });

  test('"custom" naive datetimes keep their exact local wall-clock time', () => {
    const { start, end } = reportService.resolveRange(
      'custom',
      '2026-09-01T00:00:00',
      '2026-09-18 23:59:59'
    );
    expect([start.getDate(), start.getHours()]).toEqual([1, 0]);
    expect([end.getDate(), end.getHours(), end.getMinutes(), end.getSeconds()]).toEqual([18, 23, 59, 59]);
  });
});
