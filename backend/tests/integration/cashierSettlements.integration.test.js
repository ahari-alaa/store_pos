/**
 * END-TO-END test of the cashier work-payment / settlement feature
 * (migration 014, cashierSettlementService/Repository/Controllers) against
 * a REAL MySQL database and the REAL Express app — same setup as
 * cashierServing.integration.test.js.
 *
 * Skipped unless INTEGRATION_DB=1.
 *
 *   INTEGRATION_DB=1 DB_HOST=127.0.0.1 DB_USER=... DB_PASSWORD=... DB_NAME=store_pos_test \
 *     npx jest tests/integration/cashierSettlements --runInBand
 */
const RUN = process.env.INTEGRATION_DB === '1';
const d = RUN ? describe : describe.skip;

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = process.env.JWT_SECRET || 'integration-test-secret';
process.env.DB_NAME = process.env.DB_NAME || 'store_pos_test';
process.env.DB_USER = process.env.DB_USER || 'test_user';

const { v4: uuid } = require('uuid');
const jwt = require('jsonwebtoken');
const request = require('supertest');

let app;
let pool;

const ids = {
  store: uuid(),
  admin: uuid(),
  manager: uuid(),
  cashierA: uuid(),
  cashierB: uuid(),
  cafe: uuid(),
  croissant: uuid(),
};
const tokens = {};

function tokenFor(userId, role) {
  return jwt.sign({ sub: userId, store_id: ids.store, role }, process.env.JWT_SECRET, {
    expiresIn: '1h',
  });
}

const as = (who) => ({ Authorization: `Bearer ${tokens[who]}` });

async function sell(who, lines, { occurredAt } = {}) {
  const items = lines.map(([product, quantity, price]) => ({
    product_id: product,
    quantity,
    unit_price: price,
  }));
  const total = items.reduce((s, i) => s + i.quantity * i.unit_price, 0);
  const res = await request(app)
    .post('/api/sales')
    .set(as(who))
    .send({
      client_operation_id: uuid(),
      items,
      payments: [{ amount: total, payment_method: 'CASH' }],
      ...(occurredAt ? { occurred_at: occurredAt.toISOString() } : {}),
    });
  expect(res.status).toBeLessThan(300);
  return res.body.data.sale;
}

d('cashier settlements (real MySQL, real app)', () => {
  beforeAll(async () => {
    ({ pool } = require('../../src/config/db'));
    app = require('../../src/server');

    await pool.query('INSERT INTO stores (id, name, currency) VALUES (?, ?, ?)', [
      ids.store,
      'Settlement Integration Store',
      'MAD',
    ]);
    const mkUser = (id, name, role) =>
      pool.query(
        'INSERT INTO users (id, store_id, name, email, password_hash, role) VALUES (?,?,?,?,?,?)',
        [id, ids.store, name, `${id}@it.test`, 'x', role]
      );
    await mkUser(ids.admin, 'Admin', 'admin');
    await mkUser(ids.manager, 'Manager', 'manager');
    await mkUser(ids.cashierA, 'Ahmed', 'cashier');
    await mkUser(ids.cashierB, 'Cashier B', 'cashier');
    const mkProduct = (id, name, price, cost) =>
      pool.query(
        'INSERT INTO products (id, store_id, name, price, cost, stock_quantity) VALUES (?,?,?,?,?,?)',
        [id, ids.store, name, price, cost, 10000]
      );
    await mkProduct(ids.cafe, 'Café Americain', '10.00', '3.00');
    await mkProduct(ids.croissant, 'Croissant', '8.00', '2.50');

    tokens.admin = tokenFor(ids.admin, 'admin');
    tokens.manager = tokenFor(ids.manager, 'manager');
    tokens.a = tokenFor(ids.cashierA, 'cashier');
    tokens.b = tokenFor(ids.cashierB, 'cashier');
  });

  afterAll(async () => {
    if (!pool) return;
    // cashier_settlement_items -> sales is ON DELETE RESTRICT, so
    // settlements (and their items, which CASCADE) must go before sales.
    await pool.query('DELETE FROM cashier_settlements WHERE store_id = ?', [ids.store]);
    await pool.query('DELETE FROM cashier_settlement_counters WHERE store_id = ?', [ids.store]);
    await pool.query('DELETE FROM sales WHERE store_id = ?', [ids.store]);
    await pool.query('DELETE FROM stores WHERE id = ?', [ids.store]);
    await pool.query('DELETE FROM users WHERE id IN (?, ?, ?, ?)', [
      ids.admin,
      ids.manager,
      ids.cashierA,
      ids.cashierB,
    ]);
    await pool.end();
  });

  // ------------------------------------------------------------------
  // §37 acceptance scenario (numbered as in the spec)
  // ------------------------------------------------------------------
  describe('§37 acceptance scenario', () => {
    let day1Sales = [];
    let day2Sales = [];
    let settlement;

    test('day 1: Ahmed handles 3 orders; day 2: 5 more (total 8)', async () => {
      const day1 = new Date('2026-09-18T10:00:00');
      const day2 = new Date('2026-09-19T10:00:00');
      for (let i = 0; i < 3; i += 1) {
        day1Sales.push(await sell('a', [[ids.cafe, 1, 10]], { occurredAt: day1 }));
      }
      for (let i = 0; i < 5; i += 1) {
        day2Sales.push(await sell('a', [[ids.croissant, 1, 8]], { occurredAt: day2 }));
      }
      expect(day1Sales).toHaveLength(3);
      expect(day2Sales).toHaveLength(5);
    });

    test('Rapport: 8 commandes disponibles pour justificatif', async () => {
      const res = await request(app).get('/api/cashier-settlements/eligible-orders').set(as('a'));
      expect(res.status).toBe(200);
      expect(res.body.data.count).toBe(8);
      expect(res.body.data.total_amount).toBe('70.00'); // 3*10 + 5*8

      const summary = await request(app).get('/api/cashier-settlements/my-summary').set(as('a'));
      expect(summary.body.data.orders_available).toBe(8);
      expect(summary.body.data.orders_justified).toBe(0);
      expect(summary.body.data.orders_done).toBe(8);
    });

    test('IMPRIMER LE JUSTIFICATIF creates SET-2026-0001 with 8 items', async () => {
      const allIds = [...day1Sales, ...day2Sales].map((s) => s.id);
      const res = await request(app)
        .post('/api/cashier-settlements')
        .set(as('a'))
        .send({ sale_ids: allIds });
      expect(res.status).toBe(201);
      settlement = res.body.data.settlement;
      expect(settlement.settlement_number).toMatch(/^SET-\d{4}-0001$/);
      expect(settlement.order_count).toBe(8);
      expect(settlement.total_amount).toBe('70.00');
      expect(settlement.status).toBe('PRINTED');
      expect(settlement.orders).toHaveLength(8);
      expect(settlement.cashier_id).toBe(ids.cashierA);
    });

    test('all 8 orders disappear from "disponibles" and become "déjà justifiées"', async () => {
      const eligible = await request(app).get('/api/cashier-settlements/eligible-orders').set(as('a'));
      expect(eligible.body.data.count).toBe(0);

      const summary = await request(app).get('/api/cashier-settlements/my-summary').set(as('a'));
      expect(summary.body.data.orders_available).toBe(0);
      expect(summary.body.data.orders_justified).toBe(8);
      expect(summary.body.data.to_pay).toBe('70.00');
      expect(summary.body.data.already_paid).toBe('0.00');
    });

    test('trying to select order #1 again is impossible; POST rejects it', async () => {
      const res = await request(app)
        .post('/api/cashier-settlements')
        .set(as('a'))
        .send({ sale_ids: [day1Sales[0].id] });
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe('ORDER_ALREADY_SETTLED');
      expect(res.body.error.message).toContain(settlement.settlement_number);
    });

    test('Ventes / admin: all 8 orders still visible, receipt still viewable, never deleted', async () => {
      for (const s of [...day1Sales, ...day2Sales]) {
        const res = await request(app).get(`/api/sales/${s.id}`).set(as('a'));
        expect(res.status).toBe(200);
        expect(res.body.data.sale.settlement_number).toBe(settlement.settlement_number);
        expect(res.body.data.sale.payment_status).toBe('PAID'); // customer payment untouched
      }
      const adminSale = await request(app).get(`/api/sales/${day1Sales[0].id}`).set(as('admin'));
      expect(adminSale.status).toBe(200);
      expect(adminSale.body.data.sale.settlement_number).toBe(settlement.settlement_number);
    });

    test('admin sees SET-2026-0001, 8 orders, status À PAYER (PRINTED)', async () => {
      const res = await request(app)
        .get(`/api/admin/cashier-settlements/${settlement.id}`)
        .set(as('admin'));
      expect(res.status).toBe(200);
      expect(res.body.data.settlement.order_count).toBe(8);
      expect(res.body.data.settlement.status).toBe('PRINTED');
      expect(res.body.data.settlement.orders).toHaveLength(8);
    });

    test('MARQUER COMME PAYÉ -> PAID, with paid_by/paid_at recorded', async () => {
      const res = await request(app)
        .post(`/api/admin/cashier-settlements/${settlement.id}/mark-paid`)
        .set(as('admin'));
      expect(res.status).toBe(200);
      expect(res.body.data.settlement.status).toBe('PAID');
      expect(res.body.data.settlement.paid_by).toBe(ids.admin);
      expect(res.body.data.settlement.paid_at).not.toBeNull();
    });

    test('Rapport reflects the payment: 70.00 DH already paid, 0 à payer', async () => {
      const res = await request(app).get('/api/cashier-settlements/my-summary').set(as('a'));
      expect(res.body.data.to_pay).toBe('0.00');
      expect(res.body.data.already_paid).toBe('70.00');
      expect(res.body.data.orders_available).toBe(0);
    });
  });

  // ------------------------------------------------------------------
  // Duplicate / integrity enforcement (spec §10/§12/§13/§32)
  // ------------------------------------------------------------------
  describe('duplicate settlement enforcement', () => {
    test('DB-level UNIQUE(sale_id) rejects a second settlement even bypassing the pre-check', async () => {
      const sale = await sell('b', [[ids.cafe, 1, 10]]);
      const first = await request(app)
        .post('/api/cashier-settlements')
        .set(as('b'))
        .send({ sale_ids: [sale.id] });
      expect(first.status).toBe(201);

      // Simulate a race: directly attempt a second insert at the DB layer.
      const settlementRepository = require('../../src/repositories/cashierSettlementRepository');
      const { withTransaction } = require('../../src/config/db');
      await expect(
        withTransaction(async (conn) => {
          await settlementRepository.insertSettlement(conn, {
            id: uuid(),
            storeId: ids.store,
            cashierId: ids.cashierB,
            settlementNumber: `SET-RACE-${Date.now()}`,
            periodStart: new Date(),
            periodEnd: new Date(),
            orderCount: 1,
            totalAmount: '10.00',
            printedAt: new Date(),
            createdBy: ids.cashierB,
          });
          await settlementRepository.insertSettlementItems(conn, uuid(), [sale.id]);
        })
      ).rejects.toThrow();
    });
  });

  // ------------------------------------------------------------------
  // Ownership / security (spec §14/§30)
  // ------------------------------------------------------------------
  describe('security', () => {
    test('cashier cannot include another cashier\'s orders', async () => {
      const saleOfB = await sell('b', [[ids.cafe, 1, 10]]);
      const res = await request(app)
        .post('/api/cashier-settlements')
        .set(as('a'))
        .send({ sale_ids: [saleOfB.id] });
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe('ORDER_NOT_OWNED');

      // and B's order is still eligible afterwards (nothing was created)
      const eligible = await request(app).get('/api/cashier-settlements/eligible-orders').set(as('b'));
      expect(eligible.body.data.items.map((o) => o.id)).toContain(saleOfB.id);
    });

    test('cashier cannot view another cashier\'s settlement', async () => {
      const sale = await sell('b', [[ids.croissant, 1, 8]]);
      const created = await request(app)
        .post('/api/cashier-settlements')
        .set(as('b'))
        .send({ sale_ids: [sale.id] });
      const res = await request(app)
        .get(`/api/cashier-settlements/${created.body.data.settlement.id}`)
        .set(as('a'));
      expect(res.status).toBe(403);
    });

    test('cashier cannot mark a settlement as paid or reprint (admin-only actions)', async () => {
      const sale = await sell('b', [[ids.croissant, 1, 8]]);
      const created = await request(app)
        .post('/api/cashier-settlements')
        .set(as('b'))
        .send({ sale_ids: [sale.id] });
      const id = created.body.data.settlement.id;

      const markPaid = await request(app)
        .post(`/api/admin/cashier-settlements/${id}/mark-paid`)
        .set(as('b'));
      expect(markPaid.status).toBe(403);

      const reprint = await request(app)
        .post(`/api/admin/cashier-settlements/${id}/reprint`)
        .set(as('b'));
      expect(reprint.status).toBe(403);

      const list = await request(app).get('/api/admin/cashier-settlements').set(as('b'));
      expect(list.status).toBe(403);
    });

    test('manager (not just admin) CAN mark paid and reprint', async () => {
      const sale = await sell('b', [[ids.croissant, 2, 8]]);
      const created = await request(app)
        .post('/api/cashier-settlements')
        .set(as('b'))
        .send({ sale_ids: [sale.id] });
      const id = created.body.data.settlement.id;

      const markPaid = await request(app)
        .post(`/api/admin/cashier-settlements/${id}/mark-paid`)
        .set(as('manager'));
      expect(markPaid.status).toBe(200);
      expect(markPaid.body.data.settlement.status).toBe('PAID');

      const reprint = await request(app)
        .post(`/api/admin/cashier-settlements/${id}/reprint`)
        .set(as('manager'));
      expect(reprint.status).toBe(200);
      expect(reprint.body.data.copy).toBe(true);
      expect(reprint.body.data.settlement.reprint_count).toBe(1);
    });

    test('marking an already-paid settlement paid again is rejected', async () => {
      const sale = await sell('b', [[ids.croissant, 1, 8]]);
      const created = await request(app)
        .post('/api/cashier-settlements')
        .set(as('b'))
        .send({ sale_ids: [sale.id] });
      const id = created.body.data.settlement.id;
      await request(app).post(`/api/admin/cashier-settlements/${id}/mark-paid`).set(as('admin'));
      const again = await request(app)
        .post(`/api/admin/cashier-settlements/${id}/mark-paid`)
        .set(as('admin'));
      expect(again.status).toBe(409);
      expect(again.body.error.code).toBe('SETTLEMENT_ALREADY_PAID');
    });
  });

  // ------------------------------------------------------------------
  // Customer payment vs cashier settlement independence (spec §16)
  // ------------------------------------------------------------------
  describe('customer payment status stays independent', () => {
    test('an UNPAID order can still be settled, and stays UNPAID afterwards', async () => {
      const res = await request(app)
        .post('/api/sales')
        .set(as('a'))
        .send({
          client_operation_id: uuid(),
          items: [{ product_id: ids.cafe, quantity: 1, unit_price: 10 }],
          payments: [],
        });
      expect(res.status).toBe(201);
      const sale = res.body.data.sale;
      expect(sale.payment_status).toBe('PENDING');

      const settle = await request(app)
        .post('/api/cashier-settlements')
        .set(as('a'))
        .send({ sale_ids: [sale.id] });
      expect(settle.status).toBe(201);

      const after = await request(app).get(`/api/sales/${sale.id}`).set(as('a'));
      expect(after.body.data.sale.payment_status).toBe('PENDING'); // unchanged
      expect(after.body.data.sale.settlement_id).not.toBeNull();
    });
  });

  // ------------------------------------------------------------------
  // Admin cancellation keeps history (spec §33)
  // ------------------------------------------------------------------
  describe('admin cancellation', () => {
    test('cancel keeps the settlement row and its items; does not delete anything', async () => {
      const sale = await sell('b', [[ids.cafe, 1, 10]]);
      const created = await request(app)
        .post('/api/cashier-settlements')
        .set(as('b'))
        .send({ sale_ids: [sale.id] });
      const id = created.body.data.settlement.id;

      const cancel = await request(app)
        .post(`/api/admin/cashier-settlements/${id}/cancel`)
        .set(as('admin'))
        .send({ reason: 'Erreur de saisie' });
      expect(cancel.status).toBe(200);
      expect(cancel.body.data.settlement.status).toBe('CANCELLED');
      expect(cancel.body.data.settlement.cancel_reason).toBe('Erreur de saisie');
      expect(cancel.body.data.settlement.orders).toHaveLength(1);

      // The order stays excluded from future settlements (no automatic reuse).
      const eligible = await request(app).get('/api/cashier-settlements/eligible-orders').set(as('b'));
      expect(eligible.body.data.items.map((o) => o.id)).not.toContain(sale.id);
    });
  });
});
