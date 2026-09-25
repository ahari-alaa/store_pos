/**
 * END-TO-END test of the cashier "Rapport + À servir/Servies" feature against
 * a REAL MySQL database and the REAL Express app (routes, auth, validation,
 * services, SQL). Unlike the mocked unit tests, this is what proves the SQL
 * and the transactions actually behave.
 *
 * It is skipped unless INTEGRATION_DB=1, so `npm test` stays hermetic.
 *
 *   # scratch DB, migrated with `npm run migrate`
 *   INTEGRATION_DB=1 DB_HOST=127.0.0.1 DB_USER=... DB_PASSWORD=... DB_NAME=store_pos_test \
 *     npx jest tests/integration --runInBand
 *
 * Every run creates its own store + users (random ids) and deletes them at
 * the end, so it can run against a database that already holds other data.
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

async function sell(who, lines, { pay = true, occurredAt } = {}) {
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
      payments: pay ? [{ amount: total, payment_method: 'CASH' }] : [],
      ...(occurredAt ? { occurred_at: occurredAt.toISOString() } : {}),
    });
  expect(res.status).toBeLessThan(300);
  return res.body.data.sale;
}

async function dbSale(id) {
  const [[row]] = await pool.query('SELECT * FROM sales WHERE id = ?', [id]);
  return row;
}

async function counts(saleId) {
  const [[s]] = await pool.query('SELECT COUNT(*) c FROM sales WHERE store_id = ?', [ids.store]);
  const [[i]] = await pool.query('SELECT COUNT(*) c FROM sale_items WHERE sale_id = ?', [saleId]);
  const [[p]] = await pool.query('SELECT COUNT(*) c FROM payments WHERE sale_id = ?', [saleId]);
  return { sales: s.c, items: i.c, payments: p.c };
}

d('cashier rapport + serving (real MySQL, real app)', () => {
  beforeAll(async () => {
    ({ pool } = require('../../src/config/db'));
    app = require('../../src/server');

    await pool.query('INSERT INTO stores (id, name, currency) VALUES (?, ?, ?)', [
      ids.store,
      'Integration Store',
      'MAD',
    ]);
    const mkUser = (id, name, role) =>
      pool.query(
        'INSERT INTO users (id, store_id, name, email, password_hash, role) VALUES (?,?,?,?,?,?)',
        [id, ids.store, name, `${id}@it.test`, 'x', role]
      );
    await mkUser(ids.admin, 'Admin', 'admin');
    await mkUser(ids.cashierA, 'Cashier A', 'cashier');
    await mkUser(ids.cashierB, 'Cashier B', 'cashier');
    const mkProduct = (id, name, price, cost) =>
      pool.query(
        'INSERT INTO products (id, store_id, name, price, cost, stock_quantity) VALUES (?,?,?,?,?,?)',
        [id, ids.store, name, price, cost, 1000]
      );
    await mkProduct(ids.cafe, 'Café Americain', '10.00', '3.00');
    await mkProduct(ids.croissant, 'Croissant', '8.00', '2.50');

    tokens.admin = tokenFor(ids.admin, 'admin');
    tokens.a = tokenFor(ids.cashierA, 'cashier');
    tokens.b = tokenFor(ids.cashierB, 'cashier');
  });

  afterAll(async () => {
    if (!pool) return;
    // Order matters: sale_items -> products is ON DELETE RESTRICT, so the
    // sales (which cascade to items/payments) must go before the store
    // (which cascades to products).
    await pool.query('DELETE FROM sales WHERE store_id = ?', [ids.store]);
    await pool.query('DELETE FROM stores WHERE id = ?', [ids.store]);
    await pool.query('DELETE FROM users WHERE id IN (?, ?, ?)', [
      ids.admin,
      ids.cashierA,
      ids.cashierB,
    ]);
    await pool.end();
  });

  // ------------------------------------------------------------------
  // §28 acceptance scenario (numbered as in the spec)
  // ------------------------------------------------------------------
  describe('acceptance scenario', () => {
    let order100; // cashier A: 2 x Café + 1 x Croissant = 28.00
    let adminBefore;

    test('cashier A sells; cashier B sells too (must not leak into A)', async () => {
      order100 = await sell('a', [
        [ids.cafe, 2, 10],
        [ids.croissant, 1, 8],
      ]);
      await sell('b', [[ids.cafe, 5, 10]]);
      expect(order100.total).toBe('28.00');
      expect(order100.served_at).toBeNull(); // new orders start "à servir"
    });

    test("A's Rapport shows ONLY A's products/quantities (Café=2, not 7), revenue and order", async () => {
      const res = await request(app).get('/api/reports/my-sales?period=today').set(as('a'));
      expect(res.status).toBe(200);
      const r = res.body.data;
      expect(r.cashier).toEqual({ id: ids.cashierA, name: 'Cashier A' });
      expect(r.kpis.order_count).toBe(1);
      expect(r.kpis.items_sold).toBe(3);
      expect(r.kpis.revenue).toBe('28.00');
      expect(r.kpis.average_ticket).toBe('28.00');
      expect(r.products).toEqual([
        expect.objectContaining({ name: 'Café Americain', quantity: 2, revenue: '20.00' }),
        expect.objectContaining({ name: 'Croissant', quantity: 1, revenue: '8.00' }),
      ]);
      expect(r.serving.to_serve_total).toBe(1);
      expect(r.integrity.ok).toBe(true);
    });

    test('a client-sent cashier_id is ignored: A cannot read B\'s report', async () => {
      const res = await request(app)
        .get(`/api/reports/my-sales?period=today&cashier_id=${ids.cashierB}&user_id=${ids.cashierB}`)
        .set(as('a'));
      expect(res.status).toBe(200);
      expect(res.body.data.cashier.id).toBe(ids.cashierA);
      expect(res.body.data.kpis.revenue).toBe('28.00'); // B's 50.00 is not in here
      const orders = await request(app)
        .get(`/api/reports/my-orders?user_id=${ids.cashierB}&cashier_id=${ids.cashierB}`)
        .set(as('a'));
      expect(orders.body.data.items.map((o) => o.id)).toEqual([order100.id]);
    });

    test('order #100 is under À SERVIR with its lines', async () => {
      const res = await request(app).get('/api/reports/my-orders?serve_status=to_serve').set(as('a'));
      expect(res.status).toBe(200);
      const [o] = res.body.data.items;
      expect(o.id).toBe(order100.id);
      expect(o.is_served).toBe(false);
      expect(o.payment_status).toBe('PAID');
      expect(o.items.map((i) => [i.name, i.quantity])).toEqual([
        ['Café Americain', 2],
        ['Croissant', 1],
      ]);
      const served = await request(app).get('/api/reports/my-orders?serve_status=served').set(as('a'));
      expect(served.body.data.items).toHaveLength(0);
    });

    test('capture admin figures BEFORE serving', async () => {
      const res = await request(app).get('/api/reports/overview?period=today').set(as('admin'));
      expect(res.status).toBe(200);
      adminBefore = res.body.data;
      expect(adminBefore.kpis.sale_count).toBe(2);
      expect(adminBefore.kpis.revenue).toBe('78.00');
    });

    test('IMPRIMER / SERVIR: order is served, nothing is deleted', async () => {
      const before = await counts(order100.id);
      const res = await request(app).post(`/api/sales/${order100.id}/serve`).set(as('a')).send({});
      expect(res.status).toBe(200);
      expect(res.body.data.sale.served_by).toBe(ids.cashierA);
      expect(res.body.data.sale.served_by_name).toBe('Cashier A');
      expect(res.body.data.sale.served_at).toBeTruthy();

      const row = await dbSale(order100.id);
      expect(row.served_by).toBe(ids.cashierA);
      expect(row.served_at).not.toBeNull();
      expect(row.receipt_print_count).toBe(1);
      // sale, sale_items and payments still exist, unchanged
      expect(await counts(order100.id)).toEqual(before);
      expect(row.total).toBe('28.00');
      expect(row.payment_status).toBe('PAID');
      expect(row.sale_status).toBe('COMPLETED');
    });

    test('it left À SERVIR and is now under SERVIES', async () => {
      const q = await request(app).get('/api/reports/my-orders?serve_status=to_serve').set(as('a'));
      expect(q.body.data.items).toHaveLength(0);
      const s = await request(app).get('/api/reports/my-orders?serve_status=served').set(as('a'));
      expect(s.body.data.items.map((o) => o.id)).toEqual([order100.id]);
      expect(s.body.data.items[0].served_by_name).toBe('Cashier A');
    });

    test('serving changed NOTHING in the cashier report or the admin report', async () => {
      const mine = await request(app).get('/api/reports/my-sales?period=today').set(as('a'));
      expect(mine.body.data.kpis.revenue).toBe('28.00');
      expect(mine.body.data.kpis.order_count).toBe(1);
      expect(mine.body.data.products.map((p) => [p.name, p.quantity])).toEqual([
        ['Café Americain', 2],
        ['Croissant', 1],
      ]);
      expect(mine.body.data.serving.to_serve_total).toBe(0);

      const res = await request(app).get('/api/reports/overview?period=today').set(as('admin'));
      const after = res.body.data;
      expect(after.kpis).toEqual(adminBefore.kpis);
      expect(after.top_products).toEqual(adminBefore.top_products);
      expect(after.cashiers).toEqual(adminBefore.cashiers);
      expect(after.payments.total_collected).toEqual(adminBefore.payments.total_collected);
      expect(after.integrity.ok).toBe(true);
    });

    test('admin still sees the order with who served it and when', async () => {
      const list = await request(app).get('/api/sales').set(as('admin'));
      expect(list.body.data.items.map((s) => s.id)).toContain(order100.id);
      const one = await request(app).get(`/api/sales/${order100.id}`).set(as('admin'));
      expect(one.status).toBe(200);
      const s = one.body.data.sale;
      expect(s.cashier_name).toBe('Cashier A');
      expect(s.served_by_name).toBe('Cashier A');
      expect(s.served_at).toBeTruthy();
      expect(s.items).toHaveLength(2);
      expect(s.payments).toHaveLength(1);
      expect(s.receipt_print_count).toBe(1);
    });

    test('a second serve is rejected and served_at is NOT rewritten', async () => {
      const first = (await dbSale(order100.id)).served_at;
      const res = await request(app).post(`/api/sales/${order100.id}/serve`).set(as('a')).send({});
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe('SALE_ALREADY_SERVED');
      expect(res.body.error.message).toBe('Cette commande a déjà été servie.');
      const row = await dbSale(order100.id);
      expect(row.served_at).toBe(first);
      expect(row.receipt_print_count).toBe(1); // not printed/served again
    });

    test('RÉIMPRIMER: served_at unchanged, no new sale, revenue unchanged', async () => {
      const before = await dbSale(order100.id);
      const c0 = await counts(order100.id);
      const res = await request(app).post(`/api/sales/${order100.id}/reprint`).set(as('a')).send();
      expect(res.status).toBe(200);
      const row = await dbSale(order100.id);
      expect(row.served_at).toBe(before.served_at);
      expect(row.served_by).toBe(before.served_by);
      expect(row.receipt_print_count).toBe(2);
      expect(row.receipt_printed_by).toBe(ids.cashierA);
      expect(await counts(order100.id)).toEqual(c0);
      const mine = await request(app).get('/api/reports/my-sales?period=today').set(as('a'));
      expect(mine.body.data.kpis.revenue).toBe('28.00');
      expect(mine.body.data.kpis.order_count).toBe(1);
    });
  });

  // ------------------------------------------------------------------
  describe('serving rules', () => {
    test('reprint of a NOT yet served order is refused', async () => {
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      const res = await request(app).post(`/api/sales/${s.id}/reprint`).set(as('a')).send();
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe('SALE_NOT_SERVED');
      expect((await dbSale(s.id)).receipt_print_count).toBe(0);
    });

    test("another cashier cannot serve or reprint A's order", async () => {
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      const r1 = await request(app).post(`/api/sales/${s.id}/serve`).set(as('b')).send({});
      expect(r1.status).toBe(403);
      const r2 = await request(app).post(`/api/sales/${s.id}/reprint`).set(as('b')).send();
      expect(r2.status).toBe(403);
      expect((await dbSale(s.id)).served_at).toBeNull();
    });

    test('unknown order -> 404; malformed id -> 422', async () => {
      expect((await request(app).post(`/api/sales/${uuid()}/serve`).set(as('a')).send({})).status).toBe(404);
      expect((await request(app).post('/api/sales/not-a-uuid/serve').set(as('a')).send({})).status).toBe(422);
    });

    test('serving an UNPAID order does not pay it (payment status stays PENDING)', async () => {
      const s = await sell('a', [[ids.cafe, 3, 10]], { pay: false });
      expect(s.payment_status).toBe('PENDING');
      const res = await request(app).post(`/api/sales/${s.id}/serve`).set(as('a')).send({});
      expect(res.status).toBe(200);
      const row = await dbSale(s.id);
      expect(row.payment_status).toBe('PENDING');
      expect(row.served_at).not.toBeNull();
      const [[pay]] = await pool.query('SELECT COUNT(*) c FROM payments WHERE sale_id = ?', [s.id]);
      expect(pay.c).toBe(0);
    });

    test('a cancelled order cannot be served', async () => {
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      await pool.query("UPDATE sales SET sale_status = 'CANCELLED' WHERE id = ?", [s.id]);
      const res = await request(app).post(`/api/sales/${s.id}/serve`).set(as('a')).send({});
      expect(res.status).toBe(409);
      expect(res.body.error.code).toBe('SALE_NOT_SERVABLE');
      // ...and it never appears in the queue
      const q = await request(app).get('/api/reports/my-orders?serve_status=to_serve').set(as('a'));
      expect(q.body.data.items.map((o) => o.id)).not.toContain(s.id);
    });

    test('two simultaneous serve requests: exactly one wins, served_at is written once', async () => {
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      const results = await Promise.all(
        Array.from({ length: 8 }, () =>
          request(app).post(`/api/sales/${s.id}/serve`).set(as('a')).send({})
        )
      );
      const statuses = results.map((r) => r.status).sort();
      expect(statuses.filter((x) => x === 200)).toHaveLength(1);
      expect(statuses.filter((x) => x === 409)).toHaveLength(7);
      expect((await dbSale(s.id)).receipt_print_count).toBe(1);
    });

    test('idempotent retry with the same client_operation_id: success, one event, served_at unchanged', async () => {
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      const op = uuid();
      const r1 = await request(app).post(`/api/sales/${s.id}/serve`).set(as('a')).send({ client_operation_id: op });
      expect(r1.status).toBe(200);
      expect(r1.body.data.already_applied).toBe(false);
      const servedAt = (await dbSale(s.id)).served_at;
      const r2 = await request(app).post(`/api/sales/${s.id}/serve`).set(as('a')).send({ client_operation_id: op });
      expect(r2.status).toBe(200);
      expect(r2.body.data.already_applied).toBe(true);
      const row = await dbSale(s.id);
      expect(row.served_at).toBe(servedAt);
      expect(row.receipt_print_count).toBe(1);
      const [[ops]] = await pool.query(
        "SELECT COUNT(*) c FROM sync_operations WHERE operation_id = ? AND entity_type = 'sale_served'",
        [op]
      );
      expect(ops.c).toBe(1);
      // the same op id cannot be replayed against a different sale
      const other = await sell('a', [[ids.cafe, 1, 10]]);
      const r3 = await request(app).post(`/api/sales/${other.id}/serve`).set(as('a')).send({ client_operation_id: op });
      expect(r3.status).toBe(409);
      expect(r3.body.error.code).toBe('OPERATION_ID_REUSED');
      expect((await dbSale(other.id)).served_at).toBeNull();
    });

    test('the client cannot choose served_by / served_at in the body', async () => {
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      await request(app)
        .post(`/api/sales/${s.id}/serve`)
        .set(as('a'))
        .send({ served_by: ids.cashierB, served_at: '2000-01-01T00:00:00', user_id: ids.cashierB });
      const row = await dbSale(s.id);
      expect(row.served_by).toBe(ids.cashierA);
      expect(String(row.served_at)).not.toMatch(/^2000/);
    });

    test('FIFO: the to-serve queue lists the oldest order first', async () => {
      const q = await request(app).get('/api/reports/my-orders?serve_status=to_serve').set(as('b'));
      const times = q.body.data.items.map((o) => o.occurred_at);
      expect([...times].sort()).toEqual(times);
    });
  });

  // ------------------------------------------------------------------
  describe('period filters', () => {
    const ident = { yesterdayNoon: null, oldNoon: null };
    let yId;
    let oldId;

    beforeAll(async () => {
      const now = new Date();
      ident.yesterdayNoon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1, 12, 0, 0);
      ident.oldNoon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 45, 12, 0, 0);
      // Use a dedicated product quantity marker so numbers are unambiguous
      yId = (await sell('b', [[ids.croissant, 4, 8]], { occurredAt: ident.yesterdayNoon })).id;
      oldId = (await sell('b', [[ids.croissant, 6, 8]], { occurredAt: ident.oldNoon })).id;
    });

    const croissantQty = (r) => (r.products.find((p) => p.name === 'Croissant') || { quantity: 0 }).quantity;

    test('hier: only yesterday\'s sale; today\'s are excluded', async () => {
      const r = (await request(app).get('/api/reports/my-sales?period=yesterday').set(as('b'))).body.data;
      expect(r.kpis.order_count).toBe(1);
      expect(croissantQty(r)).toBe(4);
      expect(r.kpis.revenue).toBe('32.00');
    });

    test("aujourd'hui excludes yesterday and the 45-day-old sale", async () => {
      const r = (await request(app).get('/api/reports/my-sales?period=today').set(as('b'))).body.data;
      expect(croissantQty(r)).toBe(0);
      expect(r.kpis.order_count).toBeGreaterThanOrEqual(1); // B's 5 x Café today
    });

    test('ce mois excludes the 45-day-old sale', async () => {
      const r = (await request(app).get('/api/reports/my-sales?period=month').set(as('b'))).body.data;
      expect(croissantQty(r)).not.toBe(10);
      expect(croissantQty(r) === 0 || croissantQty(r) === 4).toBe(true);
    });

    test('période personnalisée finds exactly the old sale', async () => {
      const day = (dt) =>
        `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}-${String(dt.getDate()).padStart(2, '0')}`;
      const d0 = day(ident.oldNoon);
      const r = (await request(app).get(`/api/reports/my-sales?period=custom&from=${d0}&to=${d0}`).set(as('b'))).body.data;
      expect(r.kpis.order_count).toBe(1);
      expect(croissantQty(r)).toBe(6);
      expect(r.kpis.revenue).toBe('48.00');
      // custom without dates is a validation error
      expect((await request(app).get('/api/reports/my-sales?period=custom').set(as('b'))).status).toBe(422);
    });

    test('the à-servir queue is NOT date-bound (an old unserved order stays in the queue)', async () => {
      const q = await request(app).get('/api/reports/my-orders?serve_status=to_serve').set(as('b'));
      expect(q.body.data.items.map((o) => o.id)).toEqual(expect.arrayContaining([oldId, yId]));
      const bounded = await request(app).get('/api/reports/my-orders?serve_status=to_serve&period=today').set(as('b'));
      expect(bounded.body.data.items.map((o) => o.id)).not.toContain(oldId);
    });

    test('print payload: include_orders returns every order of the period and is self-consistent', async () => {
      const r = (await request(app).get('/api/reports/my-sales?period=yesterday&include_orders=true').set(as('b'))).body.data;
      expect(r.orders).toHaveLength(r.kpis.order_count);
      expect(r.orders[0].items[0].name).toBe('Croissant');
      expect(r.integrity.ok).toBe(true);
    });

    test('payment filters: UNPAID = PENDING + PARTIALLY_PAID', async () => {
      const unpaid = await request(app).get('/api/reports/my-orders?payment_status=UNPAID').set(as('a'));
      expect(unpaid.body.data.items.length).toBeGreaterThan(0);
      expect(unpaid.body.data.items.every((o) => o.payment_status !== 'PAID')).toBe(true);
      const paid = await request(app).get('/api/reports/my-orders?payment_status=PAID').set(as('a'));
      expect(paid.body.data.items.every((o) => o.payment_status === 'PAID')).toBe(true);
    });
  });

  // ------------------------------------------------------------------
  describe('permissions (server-side, not just hidden buttons)', () => {
    const adminOnly = [
      ['get', '/api/reports/overview?period=today'],
      ['get', '/api/reports/dashboard'],
      ['get', '/api/reports/dashboard-overview?period=today'],
      ['get', '/api/reports/sales'],
      ['get', '/api/reports/top-products'],
      ['get', '/api/reports/expenses'],
      ['get', '/api/reports/stock'],
      ['get', '/api/reports/cashier-sales?period=today&cashier_id=00000000-0000-4000-8000-000000000000'],
      ['get', '/api/expenses'],
      ['get', '/api/expenses/categories'],
      ['post', '/api/expenses'],
      ['get', '/api/suppliers'],
      ['post', '/api/suppliers'],
      ['get', '/api/ingredients'],
      ['get', '/api/ingredients/low-stock'],
      ['post', '/api/ingredients'],
      ['get', '/api/inventory'],
      ['post', '/api/inventory/adjust'],
      ['post', '/api/products'],
      ['get', `/api/products/${'00000000-0000-4000-8000-000000000000'}/ingredients`],
      ['get', '/api/auth/users'],
      ['post', '/api/auth/users'],
    ];

    test.each(adminOnly)('cashier is refused: %s %s', async (method, url) => {
      const res = await request(app)[method](url).set(as('a')).send({});
      expect(res.status).toBe(403);
    });

    test('cashier keeps what the POS needs: product list/detail (without purchase cost)', async () => {
      const list = await request(app).get('/api/products').set(as('a'));
      expect(list.status).toBe(200);
      expect(list.body.data.items.length).toBeGreaterThan(0);
      expect(list.body.data.items.every((p) => !('cost' in p))).toBe(true);
      const one = await request(app).get(`/api/products/${ids.cafe}`).set(as('a'));
      expect(one.status).toBe(200);
      expect('cost' in one.body.data.product).toBe(false);
      // admin still sees cost
      const adm = await request(app).get(`/api/products/${ids.cafe}`).set(as('admin'));
      expect(adm.body.data.product.cost).toBe('3.00');
    });

    test("cashier only ever lists/reads THEIR OWN sales", async () => {
      const list = await request(app).get('/api/sales').set(as('a'));
      expect(list.body.data.items.every((s) => s.user_id === ids.cashierA)).toBe(true);
      const bSale = (await request(app).get('/api/sales').set(as('b'))).body.data.items[0];
      expect((await request(app).get(`/api/sales/${bSale.id}`).set(as('a'))).status).toBe(403);
    });

    test('admin is not a cashier: personal endpoints and serving are refused', async () => {
      expect((await request(app).get('/api/reports/my-sales').set(as('admin'))).status).toBe(403);
      expect((await request(app).get('/api/reports/my-orders').set(as('admin'))).status).toBe(403);
      const s = await sell('a', [[ids.cafe, 1, 10]]);
      expect((await request(app).post(`/api/sales/${s.id}/serve`).set(as('admin')).send({})).status).toBe(403);
    });

    test('no token -> 401', async () => {
      expect((await request(app).get('/api/reports/my-sales')).status).toBe(401);
      expect((await request(app).post(`/api/sales/${uuid()}/serve`).send({})).status).toBe(401);
    });
  });
});
