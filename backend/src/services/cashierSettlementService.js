const { v4: uuidv4 } = require('uuid');
const { withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const settlementRepository = require('../repositories/cashierSettlementRepository');
const { toCents, money, toInt } = require('./reportOverviewService');

/**
 * Cashier work-payment / settlement system ("Justificatif de travail").
 *
 * VERY IMPORTANT DISTINCTION (spec §2): this is the cashier's WORK payment
 * (how many orders he handled, so the manager can pay him), never the
 * CUSTOMER's payment for an order (`sales.payment_status`, owned entirely
 * by saleService/paymentController). Nothing here reads or writes
 * `payment_status`, and nothing in this file ever deletes or edits a sale,
 * a sale_item or a payment row — see migration 014's header.
 */

function receiptNumber(saleId) {
  const id = String(saleId || '');
  return id.length > 8 ? id.substring(0, 8) : id;
}

function orderSummary(row) {
  return {
    id: row.id,
    receipt_number: receiptNumber(row.id),
    occurred_at: String(row.occurred_at),
    total: money(toCents(row.total)),
    payment_status: row.payment_status,
  };
}

function settlementView(row, { orders } = {}) {
  return {
    id: row.id,
    settlement_number: row.settlement_number,
    cashier_id: row.cashier_id,
    cashier_name: row.cashier_name,
    period: { start: String(row.period_start), end: String(row.period_end) },
    order_count: toInt(row.order_count),
    total_amount: money(toCents(row.total_amount)),
    status: row.status,
    created_at: String(row.created_at),
    printed_at: String(row.printed_at),
    created_by: row.created_by,
    paid_at: row.paid_at ? String(row.paid_at) : null,
    paid_by: row.paid_by || null,
    paid_by_name: row.paid_by_name || null,
    cancelled_at: row.cancelled_at ? String(row.cancelled_at) : null,
    cancelled_by: row.cancelled_by || null,
    cancel_reason: row.cancel_reason || null,
    reprint_count: toInt(row.reprint_count),
    last_reprinted_at: row.last_reprinted_at ? String(row.last_reprinted_at) : null,
    last_reprinted_by_name: row.last_reprinted_by_name || null,
    can_print: false, // a settlement is only ever created already-printed; see file header
    can_view: true,
    orders: orders ? orders.map(orderSummary) : undefined,
  };
}

// ---------------------------------------------------------------------
// Cashier: eligible orders ("commandes à justifier")
// ---------------------------------------------------------------------

async function eligibleOrders(storeId, userId) {
  const rows = await settlementRepository.eligibleSales(storeId, userId);
  const totalCents = rows.reduce((sum, r) => sum + toCents(r.total), 0);
  return {
    items: rows.map(orderSummary),
    count: rows.length,
    total_amount: money(totalCents),
  };
}

/** KPI header for the Rapport screen (spec §18/§28). */
async function mySummary(storeId, userId) {
  const c = await settlementRepository.myCounters(storeId, userId);
  return {
    orders_done: c.eligibleCount + c.justifiedCount,
    orders_available: c.eligibleCount,
    orders_justified: c.justifiedCount,
    justified_revenue: money(toCents(c.justifiedRevenue)),
    settlement_count: c.settlementCount,
    to_pay: money(toCents(c.toPay)),
    already_paid: money(toCents(c.alreadyPaid)),
  };
}

async function mySettlements(storeId, userId, { status, page, pageSize } = {}) {
  const { items, total } = await settlementRepository.listMine(storeId, userId, {
    status,
    page,
    pageSize,
  });
  return { items: items.map((r) => settlementView(r)), total };
}

// ---------------------------------------------------------------------
// Create ("IMPRIMER LE JUSTIFICATIF")
// ---------------------------------------------------------------------

/**
 * Creates a cashier settlement out of the given sale ids — spec §6/§13.
 * Everything happens inside ONE transaction:
 *   1. Lock the requested sales (store-scoped).
 *   2. Verify every one exists, belongs to THIS cashier, is COMPLETED, and
 *      is not already attached to another settlement.
 *   3. Allocate a settlement number.
 *   4. Insert the settlement row + its items.
 * Any failure rolls back the whole thing — no half-created settlement is
 * ever observable (spec §25).
 *
 * `user` MUST be the authenticated req.user — never a client-supplied
 * cashier id (spec §14).
 */
async function createSettlement(storeId, user, saleIds) {
  const uniqueIds = [...new Set(saleIds)];
  if (uniqueIds.length === 0) {
    throw ApiError.badRequest('Sélectionnez au moins une commande.', 'NO_ORDERS_SELECTED');
  }

  const settlement = await withTransaction(async (conn) => {
    const { found, alreadySettled } = await settlementRepository.lockSalesForSettlement(
      conn,
      storeId,
      user.id,
      uniqueIds
    );

    const foundById = new Map(found.map((r) => [r.id, r]));
    const settledIds = new Set(alreadySettled.map((r) => r.sale_id));

    const missing = uniqueIds.filter((id) => !foundById.has(id));
    if (missing.length > 0) {
      throw ApiError.badRequest(
        `Commande(s) introuvable(s): ${missing.join(', ')}`,
        'ORDER_NOT_FOUND'
      );
    }

    const notOwned = found.filter((r) => r.user_id !== user.id);
    if (notOwned.length > 0) {
      throw ApiError.forbidden(
        'Vous ne pouvez inclure que vos propres commandes.',
        'ORDER_NOT_OWNED'
      );
    }

    const notCompleted = found.filter((r) => r.sale_status !== 'COMPLETED');
    if (notCompleted.length > 0) {
      throw ApiError.conflict(
        'Seules les commandes complétées peuvent être justifiées.',
        'ORDER_NOT_ELIGIBLE'
      );
    }

    const alreadyIncluded = found.filter((r) => settledIds.has(r.id));
    if (alreadyIncluded.length > 0) {
      const first = alreadySettled.find((r) => r.sale_id === alreadyIncluded[0].id);
      throw ApiError.conflict(
        `Cette commande est déjà incluse dans le justificatif ${first ? first.settlement_number : ''}.`,
        'ORDER_ALREADY_SETTLED',
        { sale_ids: alreadyIncluded.map((r) => r.id) }
      );
    }

    const now = new Date();
    const occurredDates = found.map((r) => new Date(r.occurred_at));
    const periodStart = new Date(Math.min(...occurredDates));
    const periodEnd = new Date(Math.max(...occurredDates));
    const totalAmount = found
      .reduce((sum, r) => sum + toCents(r.total), 0);

    const settlementNumber = await settlementRepository.nextSettlementNumber(
      conn,
      storeId,
      now.getFullYear()
    );

    const id = uuidv4();
    await settlementRepository.insertSettlement(conn, {
      id,
      storeId,
      cashierId: user.id,
      settlementNumber,
      periodStart,
      periodEnd,
      orderCount: found.length,
      totalAmount: money(totalAmount),
      printedAt: now,
      createdBy: user.id,
    });
    // The UNIQUE KEY on cashier_settlement_items.sale_id is the final,
    // race-proof guard (spec §10/§32): if a concurrent transaction
    // attached one of these sale ids between our lock check above and
    // this insert, this statement — and therefore the whole transaction —
    // throws and rolls back instead of creating a partial settlement.
    await settlementRepository.insertSettlementItems(
      conn,
      id,
      found.map((r) => r.id)
    );

    return id;
  });

  return getSettlementForCashier(storeId, user, settlement);
}

// ---------------------------------------------------------------------
// Read one
// ---------------------------------------------------------------------

async function getSettlementForCashier(storeId, user, id) {
  const row = await settlementRepository.findById(storeId, id);
  if (!row) throw ApiError.notFound('Justificatif introuvable', 'SETTLEMENT_NOT_FOUND');
  if (row.cashier_id !== user.id) {
    throw ApiError.forbidden('Vous ne pouvez consulter que vos propres justificatifs.', 'ROLE_NOT_ALLOWED');
  }
  const orders = await settlementRepository.itemsForSettlement(storeId, id);
  return settlementView(row, { orders });
}

async function getSettlementForAdmin(storeId, id) {
  const row = await settlementRepository.findById(storeId, id);
  if (!row) throw ApiError.notFound('Justificatif introuvable', 'SETTLEMENT_NOT_FOUND');
  const orders = await settlementRepository.itemsForSettlement(storeId, id);
  return settlementView(row, { orders });
}

// ---------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------

async function adminList(storeId, { cashierId, status, from, to, page, pageSize } = {}) {
  const { items, total } = await settlementRepository.listAll(storeId, {
    cashierId,
    status,
    from,
    to,
    page,
    pageSize,
  });
  return { items: items.map((r) => settlementView(r)), total };
}

/**
 * "MARQUER COMME PAYÉ" (spec §23) — the payment made TO THE CASHIER, never
 * to be confused with a customer's `payment_status`. Only moves
 * PRINTED -> PAID; a cashier can never call this (route-level permission),
 * and `paid_by` always comes from the authenticated admin, never the body.
 */
async function markPaid(storeId, admin, id) {
  await withTransaction(async (conn) => {
    const settlement = await settlementRepository.findByIdForUpdate(conn, storeId, id);
    if (!settlement) throw ApiError.notFound('Justificatif introuvable', 'SETTLEMENT_NOT_FOUND');
    if (settlement.status === 'CANCELLED') {
      throw ApiError.conflict('Ce justificatif est annulé.', 'SETTLEMENT_CANCELLED');
    }
    if (settlement.status === 'PAID') {
      throw ApiError.conflict('Ce justificatif est déjà payé.', 'SETTLEMENT_ALREADY_PAID');
    }
    const applied = await settlementRepository.markPaid(conn, storeId, id, admin.id, new Date());
    if (!applied) {
      throw ApiError.conflict('Ce justificatif est déjà payé.', 'SETTLEMENT_ALREADY_PAID');
    }
  });
  return getSettlementForAdmin(storeId, id);
}

/**
 * Admin-only cancellation (spec §33). Keeps full history — the row is
 * never deleted, its items are never removed, so its orders remain
 * permanently excluded from future settlements unless a separate,
 * explicitly-audited reversal workflow is built later.
 */
async function cancelSettlement(storeId, admin, id, reason) {
  await withTransaction(async (conn) => {
    const settlement = await settlementRepository.findByIdForUpdate(conn, storeId, id);
    if (!settlement) throw ApiError.notFound('Justificatif introuvable', 'SETTLEMENT_NOT_FOUND');
    if (settlement.status === 'CANCELLED') {
      throw ApiError.conflict('Ce justificatif est déjà annulé.', 'SETTLEMENT_ALREADY_CANCELLED');
    }
    const applied = await settlementRepository.cancel(conn, storeId, id, admin.id, new Date(), reason);
    if (!applied) {
      throw ApiError.conflict('Impossible d’annuler ce justificatif.', 'SETTLEMENT_CANCEL_FAILED');
    }
  });
  return getSettlementForAdmin(storeId, id);
}

/**
 * Admin-only duplicate print (spec §21/§26). This is deliberately the ONLY
 * "print again" path in the whole feature — there is no cashier-facing
 * reprint endpoint. It never touches `printed_at` or `status`; the caller
 * (Flutter) is responsible for clearly marking the rendered document
 * "COPIE / DUPLICATA" so it can never be confused with the original.
 */
async function adminReprint(storeId, admin, id) {
  await withTransaction(async (conn) => {
    const settlement = await settlementRepository.findByIdForUpdate(conn, storeId, id);
    if (!settlement) throw ApiError.notFound('Justificatif introuvable', 'SETTLEMENT_NOT_FOUND');
    await settlementRepository.markReprinted(conn, storeId, id, admin.id, new Date());
  });
  return getSettlementForAdmin(storeId, id);
}

module.exports = {
  eligibleOrders,
  mySummary,
  mySettlements,
  createSettlement,
  getSettlementForCashier,
  getSettlementForAdmin,
  adminList,
  markPaid,
  cancelSettlement,
  adminReprint,
};
