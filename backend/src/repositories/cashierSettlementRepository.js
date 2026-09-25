const { v4: uuidv4 } = require('uuid');
const { pool } = require('../config/db');

/**
 * Data access for the cashier work-payment / settlement system
 * (migration 014). See that migration's header for what these tables mean
 * and, just as importantly, what they deliberately do NOT touch (`sales`,
 * `sale_items`, `payments`, `served_at`, `payment_status`).
 */

// ---------------------------------------------------------------------
// Settlement numbering
// ---------------------------------------------------------------------

/**
 * Atomically allocates the next settlement number for (store, year), e.g.
 * "SET-2026-0005". `next_seq` holds the LAST issued sequence number (0 =
 * none yet this year); `INSERT ... ON DUPLICATE KEY UPDATE` takes MySQL's
 * implicit row lock, so two cashiers printing at the same instant are
 * naturally serialized instead of racing. Both statements share the
 * settlement-creation transaction's connection, so the SELECT always reads
 * back this same transaction's write.
 */
async function nextSettlementNumber(conn, storeId, year) {
  await conn.query(
    `INSERT INTO cashier_settlement_counters (store_id, year, next_seq)
     VALUES (?, ?, 1)
     ON DUPLICATE KEY UPDATE next_seq = next_seq + 1`,
    [storeId, year]
  );
  const [[row]] = await conn.query(
    'SELECT next_seq FROM cashier_settlement_counters WHERE store_id = ? AND year = ?',
    [storeId, year]
  );
  const seq = Number(row.next_seq);
  return `SET-${year}-${String(seq).padStart(4, '0')}`;
}

// ---------------------------------------------------------------------
// Eligibility — sales that CAN be included in a new settlement
// ---------------------------------------------------------------------

/**
 * This cashier's completed sales that are not yet attached to ANY
 * settlement (PRINTED, PAID, or CANCELLED — a cancelled settlement does
 * not free its orders, see migration 014). No payment_status filter:
 * unpaid/partially-paid orders are still eligible for cashier settlement
 * (spec §16 — customer payment and cashier settlement are independent).
 */
async function eligibleSales(storeId, userId) {
  const [rows] = await pool.query(
    `SELECT s.id, s.total, s.occurred_at, s.payment_status
       FROM sales s
       LEFT JOIN cashier_settlement_items csi ON csi.sale_id = s.id
      WHERE s.store_id = ? AND s.user_id = ? AND s.sale_status = 'COMPLETED'
        AND csi.id IS NULL
      ORDER BY s.occurred_at ASC, s.created_at ASC`,
    [storeId, userId]
  );
  return rows;
}

/**
 * Locks (`FOR UPDATE`) exactly the requested sales, scoped to this store +
 * cashier, and reports which requested ids do not exist / aren't owned by
 * this cashier / aren't completed / are already settled. Called inside the
 * settlement-creation transaction so a concurrent settlement or a
 * concurrent cancellation of the sale can't slip in between the check and
 * the insert (spec §13 — verify, then create, all inside one transaction).
 */
async function lockSalesForSettlement(conn, storeId, userId, saleIds) {
  if (saleIds.length === 0) return { found: [], alreadySettled: [] };

  const [rows] = await conn.query(
    `SELECT s.id, s.total, s.occurred_at, s.sale_status, s.user_id
       FROM sales s
      WHERE s.store_id = ? AND s.id IN (?)
      FOR UPDATE`,
    [storeId, saleIds]
  );

  // Which of the requested ids are already attached to a settlement —
  // checked with a plain (non-locking) read: the UNIQUE key on
  // cashier_settlement_items.sale_id is the real, race-proof guard at
  // insert time; this is only what lets the service return a precise,
  // named error instead of a generic constraint-violation message.
  const [settled] = await conn.query(
    `SELECT csi.sale_id, cs.settlement_number
       FROM cashier_settlement_items csi
       JOIN cashier_settlements cs ON cs.id = csi.settlement_id
      WHERE csi.sale_id IN (?)`,
    [saleIds]
  );

  return { found: rows, alreadySettled: settled };
}

// ---------------------------------------------------------------------
// Create
// ---------------------------------------------------------------------

async function insertSettlement(conn, s) {
  await conn.query(
    `INSERT INTO cashier_settlements
       (id, store_id, cashier_id, settlement_number, period_start, period_end,
        order_count, total_amount, status, printed_at, created_by)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PRINTED', ?, ?)`,
    [
      s.id,
      s.storeId,
      s.cashierId,
      s.settlementNumber,
      s.periodStart,
      s.periodEnd,
      s.orderCount,
      s.totalAmount,
      s.printedAt,
      s.createdBy,
    ]
  );
}

async function insertSettlementItems(conn, settlementId, saleIds) {
  if (saleIds.length === 0) return;
  const values = [];
  const params = [];
  for (const saleId of saleIds) {
    values.push('(?, ?, ?)');
    params.push(uuidv4(), settlementId, saleId);
  }
  await conn.query(
    `INSERT INTO cashier_settlement_items (id, settlement_id, sale_id) VALUES ${values.join(', ')}`,
    params
  );
}

// ---------------------------------------------------------------------
// Read
// ---------------------------------------------------------------------

const SETTLEMENT_SELECT = `
  SELECT cs.*, c.name AS cashier_name,
         cb.name AS created_by_name, pb.name AS paid_by_name,
         xb.name AS cancelled_by_name, rb.name AS last_reprinted_by_name
    FROM cashier_settlements cs
    LEFT JOIN users c  ON c.id = cs.cashier_id
    LEFT JOIN users cb ON cb.id = cs.created_by
    LEFT JOIN users pb ON pb.id = cs.paid_by
    LEFT JOIN users xb ON xb.id = cs.cancelled_by
    LEFT JOIN users rb ON rb.id = cs.last_reprinted_by
`;

async function findById(storeId, id) {
  const [rows] = await pool.query(`${SETTLEMENT_SELECT} WHERE cs.id = ? AND cs.store_id = ? LIMIT 1`, [
    id,
    storeId,
  ]);
  return rows[0] || null;
}

/**
 * The orders belonging to one settlement, in the order they were sold —
 * used both by the cashier's [VOIR] and the printed justificatif (spec
 * §19), and by the admin detail view.
 */
async function itemsForSettlement(storeId, settlementId) {
  const [rows] = await pool.query(
    `SELECT s.id, s.total, s.occurred_at, s.payment_status
       FROM cashier_settlement_items csi
       JOIN sales s ON s.id = csi.sale_id
      WHERE csi.settlement_id = ? AND s.store_id = ?
      ORDER BY s.occurred_at ASC, s.created_at ASC`,
    [settlementId, storeId]
  );
  return rows;
}

async function listMine(storeId, userId, { status, page = 1, pageSize = 50 } = {}) {
  const where = ['cs.store_id = ?', 'cs.cashier_id = ?'];
  const params = [storeId, userId];
  if (status) {
    where.push('cs.status = ?');
    params.push(status);
  }
  const whereSql = where.join(' AND ');
  const [rows] = await pool.query(
    `${SETTLEMENT_SELECT} WHERE ${whereSql} ORDER BY cs.created_at DESC LIMIT ? OFFSET ?`,
    [...params, pageSize, (page - 1) * pageSize]
  );
  const [[countRow]] = await pool.query(
    `SELECT COUNT(*) AS total FROM cashier_settlements cs WHERE ${whereSql}`,
    params
  );
  return { items: rows, total: Number(countRow.total) };
}

async function listAll(storeId, { cashierId, status, from, to, page = 1, pageSize = 50 } = {}) {
  const where = ['cs.store_id = ?'];
  const params = [storeId];
  if (cashierId) {
    where.push('cs.cashier_id = ?');
    params.push(cashierId);
  }
  if (status) {
    where.push('cs.status = ?');
    params.push(status);
  }
  if (from) {
    where.push('cs.created_at >= ?');
    params.push(from);
  }
  if (to) {
    where.push('cs.created_at <= ?');
    params.push(to);
  }
  const whereSql = where.join(' AND ');
  const [rows] = await pool.query(
    `${SETTLEMENT_SELECT} WHERE ${whereSql} ORDER BY cs.created_at DESC LIMIT ? OFFSET ?`,
    [...params, pageSize, (page - 1) * pageSize]
  );
  const [[countRow]] = await pool.query(
    `SELECT COUNT(*) AS total FROM cashier_settlements cs WHERE ${whereSql}`,
    params
  );
  return { items: rows, total: Number(countRow.total) };
}

/**
 * KPI counters for the cashier's Rapport "Commandes à justifier / déjà
 * justifiées" header (spec §18/§28). One query, no date bound — mirrors
 * the serving queue's own "to_serve_total" (cashierReportService), which
 * is likewise never period-bound.
 */
async function myCounters(storeId, userId) {
  const [[eligible]] = await pool.query(
    `SELECT COUNT(*) AS n
       FROM sales s
       LEFT JOIN cashier_settlement_items csi ON csi.sale_id = s.id
      WHERE s.store_id = ? AND s.user_id = ? AND s.sale_status = 'COMPLETED' AND csi.id IS NULL`,
    [storeId, userId]
  );
  const [[justified]] = await pool.query(
    `SELECT COUNT(*) AS n, COALESCE(SUM(s.total), 0) AS revenue
       FROM cashier_settlement_items csi
       JOIN sales s ON s.id = csi.sale_id
       JOIN cashier_settlements cs ON cs.id = csi.settlement_id
      WHERE s.store_id = ? AND cs.cashier_id = ? AND cs.status != 'CANCELLED'`,
    [storeId, userId]
  );
  const [[money]] = await pool.query(
    `SELECT
        COALESCE(SUM(CASE WHEN status = 'PRINTED' THEN total_amount ELSE 0 END), 0) AS to_pay,
        COALESCE(SUM(CASE WHEN status = 'PAID' THEN total_amount ELSE 0 END), 0)    AS already_paid,
        COUNT(*) AS settlement_count
       FROM cashier_settlements
      WHERE store_id = ? AND cashier_id = ? AND status != 'CANCELLED'`,
    [storeId, userId]
  );
  return {
    eligibleCount: Number(eligible.n),
    justifiedCount: Number(justified.n),
    justifiedRevenue: justified.revenue,
    toPay: money.to_pay,
    alreadyPaid: money.already_paid,
    settlementCount: Number(money.settlement_count),
  };
}

// ---------------------------------------------------------------------
// State transitions (admin)
// ---------------------------------------------------------------------

async function markPaid(conn, storeId, id, paidBy, paidAt) {
  const [result] = await conn.query(
    `UPDATE cashier_settlements
        SET status = 'PAID', paid_at = ?, paid_by = ?
      WHERE id = ? AND store_id = ? AND status = 'PRINTED'`,
    [paidAt, paidBy, id, storeId]
  );
  return result.affectedRows === 1;
}

async function cancel(conn, storeId, id, cancelledBy, cancelledAt, reason) {
  const [result] = await conn.query(
    `UPDATE cashier_settlements
        SET status = 'CANCELLED', cancelled_at = ?, cancelled_by = ?, cancel_reason = ?
      WHERE id = ? AND store_id = ? AND status IN ('PRINTED', 'PAID')`,
    [cancelledAt, cancelledBy, reason || null, id, storeId]
  );
  return result.affectedRows === 1;
}

/** Admin-only duplicate copy (spec §26) — never rewrites printed_at/status. */
async function markReprinted(conn, storeId, id, reprintedBy, reprintedAt) {
  const [result] = await conn.query(
    `UPDATE cashier_settlements
        SET reprint_count = reprint_count + 1, last_reprinted_at = ?, last_reprinted_by = ?
      WHERE id = ? AND store_id = ?`,
    [reprintedAt, reprintedBy, id, storeId]
  );
  return result.affectedRows === 1;
}

async function findByIdForUpdate(conn, storeId, id) {
  const [rows] = await conn.query(
    'SELECT * FROM cashier_settlements WHERE id = ? AND store_id = ? FOR UPDATE',
    [id, storeId]
  );
  return rows[0] || null;
}

module.exports = {
  nextSettlementNumber,
  eligibleSales,
  lockSalesForSettlement,
  insertSettlement,
  insertSettlementItems,
  findById,
  findByIdForUpdate,
  itemsForSettlement,
  listMine,
  listAll,
  myCounters,
  markPaid,
  cancel,
  markReprinted,
};
