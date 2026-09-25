const { v4: uuidv4 } = require('uuid');
const { withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const saleRepository = require('../repositories/saleRepository');
const paymentRepository = require('../repositories/paymentRepository');
const productRepository = require('../repositories/productRepository');
const inventoryRepository = require('../repositories/inventoryRepository');
const syncRepository = require('../repositories/syncRepository');
const ingredientService = require('./ingredientService');
const { resolveRange } = require('./reportService');

function round2(n) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

/**
 * Creates a sale, its line items, its payment(s), and the matching
 * inventory deductions — all inside one MySQL transaction, exactly as
 * required by section 11 ("Sale + Sale Items + Payment + Inventory update
 * must all succeed or all fail").
 *
 * Idempotency (section 5/17): `client_operation_id` is unique per
 * (store_id, client_operation_id). If a sale with this id already exists
 * for the store, we return it as-is instead of creating a duplicate —
 * this is what makes it safe for the Flutter sync queue to retry a push
 * that timed out without knowing whether the server actually received it.
 */
async function createSale(storeId, userId, input) {
  // withTransaction resolves only the sale id + duplicate flag. The full
  // sale (with items/payments) is re-read afterwards via the plain pool,
  // once the transaction has committed — reading it through a second
  // connection *inside* the still-open transaction would see nothing,
  // since the insert is not yet committed.
  const { saleId, wasDuplicate } = await withTransaction(async (conn) => {
    const existing = await saleRepository.findByClientOperationId(
      conn,
      storeId,
      input.client_operation_id
    );
    if (existing) {
      return { saleId: existing.id, wasDuplicate: true };
    }

    // Lock every referenced product row up front (in a stable order — by id —
    // to avoid deadlocks between two concurrent sales sharing a product) and
    // validate them before writing anything.
    const sortedItems = [...input.items].sort((a, b) => (a.product_id > b.product_id ? 1 : -1));
    const products = new Map();
    for (const item of sortedItems) {
      const product = await productRepository.findByIdForUpdate(conn, storeId, item.product_id);
      if (!product) {
        throw ApiError.badRequest(
          `Product ${item.product_id} not found in this store`,
          'INVALID_PRODUCT'
        );
      }
      if (!product.is_active) {
        throw ApiError.badRequest(`Product "${product.name}" is not active`, 'INACTIVE_PRODUCT');
      }
      products.set(item.product_id, product);
    }

    let subtotal = 0;
    const saleItemRows = input.items.map((item) => {
      const lineSubtotal = round2(item.unit_price * item.quantity);
      subtotal = round2(subtotal + lineSubtotal);
      return {
        id: uuidv4(),
        productId: item.product_id,
        quantity: item.quantity,
        unitPrice: item.unit_price,
        subtotal: lineSubtotal,
      };
    });

    const discountTotal = round2(input.discount_total || 0);
    const taxTotal = round2(input.tax_total || 0);
    const total = round2(subtotal - discountTotal + taxTotal);

    const paidAmount = round2(input.payments.reduce((sum, p) => round2(sum + p.amount), 0));

    // "Give receipt without paying" (Sales spec §2/§3): an empty/zero
    // payments array is a deliberate, valid way to create a sale — NOT an
    // error. It must NOT be treated as insufficient payment; it simply
    // means the sale starts out NOT PAID (`PENDING`) and is paid later via
    // addPayment() below, which updates this same row rather than creating
    // a new one (spec §6/§9/§20).
    //
    // Any NON-zero amount, on the other hand, is a cashier declaring "this
    // is what the customer is paying right now", so it must still cover
    // the total — partial payment at creation time isn't part of this
    // workflow (partial top-ups happen via addPayment on an existing sale).
    const isUnpaid = paidAmount <= 0.005;
    if (!isUnpaid && paidAmount + 0.005 < total) {
      throw ApiError.badRequest(
        `Payments (${paidAmount}) do not cover the sale total (${total})`,
        'INSUFFICIENT_PAYMENT'
      );
    }

    const paymentStatus = isUnpaid ? 'PENDING' : 'PAID';

    const saleId = uuidv4();
    const now = new Date();
    await saleRepository.insertSale(conn, storeId, {
      id: saleId,
      userId,
      clientOperationId: input.client_operation_id,
      subtotal,
      discountTotal,
      taxTotal,
      total,
      paymentStatus,
      saleStatus: 'COMPLETED',
      note: input.note,
      occurredAt: input.occurred_at ? new Date(input.occurred_at) : now,
    });

    await saleRepository.insertSaleItems(conn, saleId, saleItemRows);

    const paymentRows = input.payments.map((p) => ({
      id: uuidv4(),
      amount: p.amount,
      paymentMethod: p.payment_method === 'MIXED' ? 'CASH' : p.payment_method,
    }));
    await paymentRepository.insertPayments(conn, saleId, userId, paymentRows);

    // Deduct stock for every line item; adjustStock's conditional UPDATE
    // returns false if this would push stock below zero (protects against
    // overselling under concurrent sales even though we already hold the
    // row lock from findByIdForUpdate above).
    for (const item of saleItemRows) {
      const success = await productRepository.adjustStock(
        conn,
        storeId,
        item.productId,
        -item.quantity
      );
      if (!success) {
        const product = products.get(item.productId);
        throw ApiError.conflict(
          `Not enough stock for "${product ? product.name : item.productId}"`,
          'INSUFFICIENT_STOCK'
        );
      }
      await inventoryRepository.insertMovement(conn, storeId, {
        id: uuidv4(),
        productId: item.productId,
        quantityDelta: -item.quantity,
        movementType: 'SALE',
        referenceId: saleId,
      });

      // Consommation automatique: if this product has a recipe (Modifier
      // le produit → Ingrédients / Recette), deduct the ingredients it
      // used too. If any required supply is short, this throws and the
      // whole transaction (including the product-stock deduction just
      // above and anything already written for earlier cart lines) rolls
      // back — see ingredientService.consumeForSale.
      const product = products.get(item.productId);
      await ingredientService.consumeForSale(conn, storeId, {
        productId: item.productId,
        productName: product ? product.name : undefined,
        quantity: item.quantity,
        saleId,
      });
    }

    return { saleId, wasDuplicate: false };
  });

  const sale = await saleRepository.findById(storeId, saleId);
  return { sale, wasDuplicate };
}

/**
 * Records an additional payment against an existing sale (e.g. completing
 * a PARTIALLY_PAID sale, or recording a top-up). Idempotent per
 * (sale_id, client_operation_id) via the payments table's unique key.
 */
async function addPayment(storeId, userId, input) {
  const { paymentId, wasDuplicate } = await withTransaction(async (conn) => {
    const sale = await saleRepository.findByIdForUpdate(conn, storeId, input.sale_id);
    if (!sale) throw ApiError.notFound('Sale not found', 'SALE_NOT_FOUND');

    const existing = await paymentRepository.findByClientOperationId(
      conn,
      input.sale_id,
      input.client_operation_id
    );
    if (existing) {
      return { paymentId: existing.id, wasDuplicate: true };
    }

    const id = uuidv4();
    await paymentRepository.insertPayments(conn, input.sale_id, userId, [
      {
        id,
        clientOperationId: input.client_operation_id,
        amount: input.amount,
        paymentMethod: input.payment_method,
      },
    ]);

    const totalPaid = await paymentRepository.sumBySale(conn, input.sale_id);
    const newStatus = totalPaid + 0.005 >= Number(sale.total) ? 'PAID' : 'PARTIALLY_PAID';
    await saleRepository.updatePaymentStatus(conn, input.sale_id, newStatus);

    return { paymentId: id, wasDuplicate: false };
  });

  const sale = await saleRepository.findById(storeId, input.sale_id);
  return { sale, paymentId, wasDuplicate };
}

async function getById(storeId, id) {
  const sale = await saleRepository.findById(storeId, id);
  if (!sale) throw ApiError.notFound('Sale not found', 'SALE_NOT_FOUND');
  return sale;
}

async function list(storeId, query) {
  // A named `period` (Rapports — spec §15) resolves to a concrete
  // from/to the exact same way every other Rapports section does
  // (reportService.js#resolveRange), so "cette semaine" means the same
  // thing on the Transactions récentes table as it does on the KPI row
  // above it. The Sales screen's own calls never set `period`, so they
  // fall through to the from/to they already computed, unchanged.
  const { start, end } = query.period
    ? resolveRange(query.period, query.from, query.to)
    : { start: query.from, end: query.to };

  return saleRepository.list(storeId, {
    from: start,
    to: end,
    userId: query.user_id,
    search: query.search,
    paymentStatus: query.payment_status,
    page: query.page,
    pageSize: query.page_size,
  });
}

// `sync_operations.entity_type` value used to make a serve request
// idempotent (see serveSale). Reusing that table keeps ONE place where "this
// client operation id was already applied" is recorded, instead of adding a
// second idempotency mechanism just for serving.
const SERVE_OPERATION_ENTITY = 'sale_served';

/**
 * Serving an order = the cashier printed it and hands it over ("IMPRIMER /
 * SERVIR"). It changes ONLY the serving columns of the sale (migration
 * 012): the sale, its items, its payments, its totals and its payment
 * status are never touched, so revenue and every report stay identical.
 * Serving does not pay an unpaid order either — the two are independent.
 *
 * Concurrency: the sale row is locked (SELECT ... FOR UPDATE) and then
 * claimed with `UPDATE ... WHERE served_at IS NULL`. Whoever loses the race
 * affects 0 rows and gets SALE_ALREADY_SERVED — an order is never served
 * (nor its `served_at` overwritten) twice.
 *
 * Idempotency: a client that lost the response and retries with the same
 * `client_operation_id` gets a success (`alreadyApplied: true`) instead of
 * "already served", and no second event is recorded.
 *
 * @param {{id: string}} user the AUTHENTICATED user (from req.user — never
 *   a client-supplied id).
 */
async function serveSale(storeId, user, saleId, { clientOperationId } = {}) {
  const { alreadyApplied } = await withTransaction(async (conn) => {
    const sale = await saleRepository.findByIdForUpdate(conn, storeId, saleId);
    if (!sale) throw ApiError.notFound('Sale not found', 'SALE_NOT_FOUND');
    if (sale.user_id !== user.id) {
      throw ApiError.forbidden('You can only serve your own orders', 'ROLE_NOT_ALLOWED');
    }

    if (clientOperationId) {
      const prior = await syncRepository.findByOperationId(conn, storeId, clientOperationId);
      if (prior) {
        if (prior.entity_type === SERVE_OPERATION_ENTITY && prior.entity_id === saleId) {
          return { alreadyApplied: true };
        }
        throw ApiError.conflict(
          'This client_operation_id was already used for another operation',
          'OPERATION_ID_REUSED'
        );
      }
    }

    if (sale.sale_status !== 'COMPLETED') {
      throw ApiError.conflict('Only completed orders can be served', 'SALE_NOT_SERVABLE');
    }
    if (sale.served_at) {
      throw ApiError.conflict('Cette commande a déjà été servie.', 'SALE_ALREADY_SERVED');
    }

    const claimed = await saleRepository.markServed(conn, storeId, saleId, user.id, new Date());
    if (!claimed) {
      throw ApiError.conflict('Cette commande a déjà été servie.', 'SALE_ALREADY_SERVED');
    }

    if (clientOperationId) {
      await syncRepository.record(conn, {
        id: uuidv4(),
        operationId: clientOperationId,
        storeId,
        userId: user.id,
        entityType: SERVE_OPERATION_ENTITY,
        entityId: saleId,
        operationType: 'update',
        status: 'applied',
      });
    }
    return { alreadyApplied: false };
  });

  const sale = await saleRepository.findById(storeId, saleId);
  return { sale, alreadyApplied };
}

/**
 * "Réimprimer": the receipt of an ALREADY SERVED order was printed again.
 * Only the print audit columns change; `served_at` / `served_by` are never
 * rewritten and no sale, item or payment is created or modified.
 */
async function reprintSale(storeId, user, saleId) {
  await withTransaction(async (conn) => {
    const sale = await saleRepository.findByIdForUpdate(conn, storeId, saleId);
    if (!sale) throw ApiError.notFound('Sale not found', 'SALE_NOT_FOUND');
    if (sale.user_id !== user.id) {
      throw ApiError.forbidden('You can only reprint your own orders', 'ROLE_NOT_ALLOWED');
    }
    if (!sale.served_at) {
      throw ApiError.conflict(
        'This order has not been served yet — use IMPRIMER / SERVIR',
        'SALE_NOT_SERVED'
      );
    }
    await saleRepository.markReprinted(conn, storeId, saleId, user.id, new Date());
  });
  return { sale: await saleRepository.findById(storeId, saleId) };
}

module.exports = { createSale, addPayment, getById, list, serveSale, reprintSale };
