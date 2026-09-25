-- =====================================================================
-- Store POS — MySQL schema (migration 014)
-- Cashier work-payment / settlement system ("Justificatif de travail").
--
-- WHAT THIS IS NOT
-- -----------------
-- This is NOT the serving workflow (migration 012: served_at / à-servir
-- queue) and it is NOT `sales.payment_status` (whether the CUSTOMER paid).
-- It answers a third, independent question: has THIS cashier already used
-- a given order to justify how many orders he handled, for the manager to
-- pay him for his work? A sale keeps exactly one `payment_status` and one
-- `served_at`, completely unaffected by anything in this file — no column
-- is added to `sales`, nothing here is ever DELETEd, and no sale, item or
-- payment row is touched.
--
-- cashier_settlement_counters
-- ----------------------------
-- Backs an atomic "next settlement number for (store, year)" via
-- `INSERT ... ON DUPLICATE KEY UPDATE next_seq = LAST_INSERT_ID(next_seq+1)`
-- (see cashierSettlementRepository.nextSettlementNumber) — safe under two
-- cashiers printing at the same instant, without a separate row lock.
--
-- cashier_settlements
-- ---------------------
-- One row per printed justificatif ("SET-2026-0005"). There is no DRAFT
-- status stored: the row is only ever written by the same transaction that
-- validates and attaches its orders (cashierSettlementService.createSettlement),
-- so if printing/creation fails partway, nothing is left half-created (spec
-- §13/§25) — the first state a settlement can be observed in is the
-- equivalent of "printed". `status` afterwards moves forward only:
-- PRINTED -> PAID (admin marks the cashier paid) or PRINTED -> CANCELLED
-- (admin-only, kept for history, never deletes — spec §33).
--
-- cashier_settlement_items
-- --------------------------
-- The join table between a settlement and the sales it covers. The
-- `UNIQUE KEY uq_settlement_items_sale (sale_id)` is the enforcement spec
-- §12/§32 calls "mandatory": a sale_id can appear in this table AT MOST
-- ONCE, ever — across every settlement, PRINTED or CANCELLED — so an
-- INSERT for an already-settled sale fails at the database level even if
-- every application-side check were somehow bypassed. Cancelling a
-- settlement (see cashier_settlements.status) does NOT delete its items,
-- so a cancelled settlement's orders do not silently become reusable
-- (spec §33 — that needs an explicit, separately audited reversal, which
-- is out of scope here).
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS cashier_settlement_counters (
  store_id    CHAR(36)  NOT NULL,
  year        INT       NOT NULL,
  next_seq    INT       NOT NULL DEFAULT 1,
  PRIMARY KEY (store_id, year)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cashier_settlements (
  id                   CHAR(36)      NOT NULL PRIMARY KEY,
  store_id             CHAR(36)      NOT NULL,
  cashier_id           CHAR(36)      NOT NULL,
  settlement_number    VARCHAR(40)   NOT NULL,
  period_start         DATETIME      NOT NULL,
  period_end           DATETIME      NOT NULL,
  order_count          INT           NOT NULL,
  total_amount         DECIMAL(12,2) NOT NULL,
  -- No 'DRAFT': a row only ever exists once its items are attached in the
  -- same transaction (see file header). 'PRINTED' is therefore the initial
  -- status, not a default meant to be overwritten by a later "confirm" step.
  status               ENUM('PRINTED','PAID','CANCELLED') NOT NULL DEFAULT 'PRINTED',
  created_at           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- Same instant as created_at in practice (the settlement is created BY
  -- being printed) — kept as its own column because the spec (§11) asks
  -- for "printed_at" explicitly, and a future workflow could conceivably
  -- separate the two.
  printed_at           DATETIME      NOT NULL,
  created_by           CHAR(36)      NOT NULL,
  -- Cashier-payment status (NOT customer payment — see file header).
  paid_at              DATETIME      NULL,
  paid_by              CHAR(36)      NULL,
  cancelled_at         DATETIME      NULL,
  cancelled_by         CHAR(36)      NULL,
  cancel_reason        VARCHAR(500)  NULL,
  -- Admin-only "RÉIMPRIMER UNE COPIE" (spec §26). The cashier's own [VOIR]
  -- never touches these — only the admin duplicate action does.
  reprint_count        INT UNSIGNED  NOT NULL DEFAULT 0,
  last_reprinted_at    DATETIME      NULL,
  last_reprinted_by    CHAR(36)      NULL,
  UNIQUE KEY uq_settlements_store_number (store_id, settlement_number),
  KEY idx_settlements_store_cashier (store_id, cashier_id, created_at),
  KEY idx_settlements_store_status (store_id, status),
  CONSTRAINT fk_settlements_store      FOREIGN KEY (store_id)   REFERENCES stores(id) ON DELETE CASCADE,
  CONSTRAINT fk_settlements_cashier    FOREIGN KEY (cashier_id) REFERENCES users(id)  ON DELETE RESTRICT,
  CONSTRAINT fk_settlements_created_by FOREIGN KEY (created_by) REFERENCES users(id)  ON DELETE RESTRICT,
  CONSTRAINT fk_settlements_paid_by    FOREIGN KEY (paid_by)    REFERENCES users(id)  ON DELETE RESTRICT,
  CONSTRAINT fk_settlements_cancelled_by FOREIGN KEY (cancelled_by) REFERENCES users(id) ON DELETE RESTRICT,
  CONSTRAINT fk_settlements_reprinted_by FOREIGN KEY (last_reprinted_by) REFERENCES users(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS cashier_settlement_items (
  id             CHAR(36)  NOT NULL PRIMARY KEY,
  settlement_id  CHAR(36)  NOT NULL,
  sale_id        CHAR(36)  NOT NULL,
  created_at     DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- THE constraint: one sale can belong to one cashier settlement, ever.
  UNIQUE KEY uq_settlement_items_sale (sale_id),
  KEY idx_settlement_items_settlement (settlement_id),
  CONSTRAINT fk_settlement_items_settlement
    FOREIGN KEY (settlement_id) REFERENCES cashier_settlements(id) ON DELETE CASCADE,
  -- RESTRICT, like every other FK onto sales(id): a sale can never be
  -- deleted out from under a settlement that references it (and sales are
  -- never deleted by this app in the first place — spec §8/§29).
  CONSTRAINT fk_settlement_items_sale
    FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
