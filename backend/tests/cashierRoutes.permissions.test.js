process.env.NODE_ENV = 'test';
process.env.DB_NAME = 'test_db';
process.env.DB_USER = 'test_user';
process.env.JWT_SECRET = 'test-secret-key-for-jwt-signing-in-tests';

jest.mock('../src/config/db');
jest.mock('../src/repositories/userRepository');
jest.mock('../src/services/cashierReportService');
jest.mock('../src/services/saleService');
jest.mock('../src/services/reportOverviewService');
jest.mock('../src/services/reportService');
jest.mock('../src/services/supplierService');
jest.mock('../src/services/ingredientService');
jest.mock('../src/services/expenseService');

const request = require('supertest');
const jwt = require('jsonwebtoken');
const userRepository = require('../src/repositories/userRepository');
const cashierReportService = require('../src/services/cashierReportService');
const saleService = require('../src/services/saleService');
const reportOverviewService = require('../src/services/reportOverviewService');
const supplierService = require('../src/services/supplierService');
const ingredientService = require('../src/services/ingredientService');
const expenseService = require('../src/services/expenseService');
const { hasPermission } = require('../src/middleware/authorize');
const app = require('../src/server');

const USERS = {
  cashier: { id: 'c-1', store_id: 's-1', role: 'cashier', name: 'Ahmed', email: 'a@x', is_active: 1 },
  manager: { id: 'm-1', store_id: 's-1', role: 'manager', name: 'Manu', email: 'm@x', is_active: 1 },
  admin: { id: 'ad-1', store_id: 's-1', role: 'admin', name: 'Boss', email: 'b@x', is_active: 1 },
};
const auth = (role) => ({
  Authorization: `Bearer ${jwt.sign({ sub: USERS[role].id }, process.env.JWT_SECRET)}`,
});
const UUID = '22222222-2222-4222-8222-222222222222';

beforeEach(() => {
  jest.clearAllMocks();
  userRepository.findById.mockImplementation(async (id) =>
    Object.values(USERS).find((u) => u.id === id) || null
  );
  cashierReportService.myReport.mockResolvedValue({ ok: true });
  cashierReportService.myOrders.mockResolvedValue({ items: [], total: 0, page: 1, pageSize: 50 });
  saleService.serveSale.mockResolvedValue({ sale: { id: UUID }, alreadyApplied: false });
  saleService.reprintSale.mockResolvedValue({ sale: { id: UUID } });
});

describe('permission map', () => {
  test('only the cashier holds the personal-report / serve permissions', () => {
    expect(hasPermission('cashier', 'sales.serve')).toBe(true);
    expect(hasPermission('cashier', 'reports.view_own')).toBe(true);
    for (const role of ['admin', 'manager']) {
      expect(hasPermission(role, 'sales.serve')).toBe(false);
      expect(hasPermission(role, 'reports.view_own')).toBe(false);
    }
  });
  test('the cashier has NO admin permission', () => {
    for (const p of ['reports.view', 'products.manage', 'users.manage', 'expenses.manage', 'inventory.manage', 'suppliers.manage', 'store.configure']) {
      expect(hasPermission('cashier', p)).toBe(false);
    }
  });
});

describe('cashier personal endpoints', () => {
  test('my-sales is computed for req.user, and a client cashier_id is discarded', async () => {
    const res = await request(app)
      .get('/api/reports/my-sales?period=week&cashier_id=someone-else&user_id=someone-else')
      .set(auth('cashier'));
    expect(res.status).toBe(200);
    const [storeId, user, opts] = cashierReportService.myReport.mock.calls[0];
    expect(storeId).toBe('s-1');
    expect(user.id).toBe('c-1'); // from the JWT, never from the query
    expect(JSON.stringify(opts)).not.toMatch(/someone-else/);
  });

  test('my-orders uses req.user.id and forwards the filters', async () => {
    await request(app)
      .get('/api/reports/my-orders?serve_status=to_serve&payment_status=UNPAID&cashier_id=x')
      .set(auth('cashier'));
    const [, userId, opts] = cashierReportService.myOrders.mock.calls[0];
    expect(userId).toBe('c-1');
    expect(opts).toMatchObject({ serveStatus: 'to_serve', paymentStatus: 'UNPAID' });
  });

  test('serve passes req.user and only the idempotency key from the body', async () => {
    const res = await request(app)
      .post(`/api/sales/${UUID}/serve`)
      .set(auth('cashier'))
      .send({ client_operation_id: UUID, served_by: 'evil', served_at: '2000-01-01' });
    expect(res.status).toBe(200);
    const [storeId, user, saleId, opts] = saleService.serveSale.mock.calls[0];
    expect([storeId, user.id, saleId]).toEqual(['s-1', 'c-1', UUID]);
    expect(opts).toEqual({ clientOperationId: UUID });
  });

  test('serve/reprint/my-* are refused for admin and manager (before any service runs)', async () => {
    for (const role of ['admin', 'manager']) {
      expect((await request(app).get('/api/reports/my-sales').set(auth(role))).status).toBe(403);
      expect((await request(app).get('/api/reports/my-orders').set(auth(role))).status).toBe(403);
      expect((await request(app).post(`/api/sales/${UUID}/serve`).set(auth(role)).send({})).status).toBe(403);
      expect((await request(app).post(`/api/sales/${UUID}/reprint`).set(auth(role)).send({})).status).toBe(403);
    }
    expect(cashierReportService.myReport).not.toHaveBeenCalled();
    expect(saleService.serveSale).not.toHaveBeenCalled();
    expect(saleService.reprintSale).not.toHaveBeenCalled();
  });

  test('401 without a token', async () => {
    expect((await request(app).get('/api/reports/my-sales')).status).toBe(401);
    expect((await request(app).post(`/api/sales/${UUID}/serve`).send({})).status).toBe(401);
  });
});

describe('a cashier cannot reach admin-only APIs by typing the URL', () => {
  const blocked = [
    ['get', '/api/reports/overview'],
    ['get', '/api/reports/dashboard'],
    ['get', '/api/reports/cashier-sales'],
    ['get', '/api/reports/top-products'],
    ['get', '/api/expenses'],
    ['post', '/api/expenses'],
    ['get', '/api/suppliers'],
    ['get', `/api/suppliers/${UUID}`],
    ['get', '/api/ingredients'],
    ['get', '/api/ingredients/low-stock'],
    ['get', `/api/ingredients/${UUID}`],
    ['get', `/api/ingredients/${UUID}/movements`],
    ['get', `/api/ingredients/${UUID}/used-in`],
    ['get', '/api/inventory'],
    ['post', '/api/products'],
    ['put', `/api/products/${UUID}`],
    ['delete', `/api/products/${UUID}`],
    ['get', `/api/products/${UUID}/ingredients`],
    ['get', '/api/auth/users'],
    ['post', '/api/auth/users'],
    ['put', `/api/auth/users/${UUID}/pin`],
  ];
  test.each(blocked)('%s %s -> 403', async (method, url) => {
    const res = await request(app)[method](url).set(auth('cashier')).send({});
    expect(res.status).toBe(403);
    expect(reportOverviewService.reportOverview).not.toHaveBeenCalled();
    expect(supplierService.list).not.toHaveBeenCalled();
    expect(ingredientService.list).not.toHaveBeenCalled();
    expect(expenseService.list).not.toHaveBeenCalled();
  });

  test('admin and manager keep access to what was restricted (no regression)', async () => {
    supplierService.list.mockResolvedValue({ items: [], total: 0 });
    for (const role of ['admin', 'manager']) {
      expect((await request(app).get('/api/suppliers').set(auth(role))).status).toBe(200);
    }
  });
});
