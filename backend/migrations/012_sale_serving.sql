-- =====================================================================
-- Store POS — MySQL schema (migration 012)
-- Cashier "À servir / Servies" workflow.
--
-- WHY A DEDICATED STATE (and not a status change or a DELETE)
-- ------------------------------------------------------------
-- Printing/serving an order must ONLY move it out of the cashier's
-- operational queue. The sale, its sale_items and its payments stay
-- exactly as they were, so revenue, sale counts, product statistics and
-- every admin report are unaffected. That is why serving is recorded in
-- its own columns instead of touching `sale_status` / `payment_status`
-- (which have a business meaning in every report) and never by deleting
-- rows.
--
--   served_at            NULL  = still "à servir"; set ONCE, never rewritten
--   served_by            the user who served it (audit)
--   receipt_printed_at   last time the receipt was printed (serve OR reprint)
--   receipt_printed_by   who printed it last
--   receipt_print_count  how many times it was printed (>1 = reprints)
--
-- `served_at` being written only by a conditional
-- `UPDATE ... WHERE served_at IS NULL` (see saleRepository.markServed) is
-- what prevents two cashier clients from serving the same order twice.
--
-- Existing rows are untouched by this file (all new columns are NULL/0).
-- See 013_sale_serving_backfill_legacy.sql for what to do about sales that
-- were made before this workflow existed.
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE sales
  ADD COLUMN served_at            DATETIME     NULL              AFTER occurred_at,
  ADD COLUMN served_by            CHAR(36)     NULL              AFTER served_at,
  ADD COLUMN receipt_printed_at   DATETIME     NULL              AFTER served_by,
  ADD COLUMN receipt_printed_by   CHAR(36)     NULL              AFTER receipt_printed_at,
  ADD COLUMN receipt_print_count  INT UNSIGNED NOT NULL DEFAULT 0 AFTER receipt_printed_by,
  -- Serves the cashier's queue: WHERE store_id = ? AND user_id = ? AND served_at IS NULL
  ADD INDEX idx_sales_store_user_served (store_id, user_id, served_at),
  -- RESTRICT (same as sales.user_id / payments.user_id): the audit trail
  -- must never silently lose the name of who served/printed an order.
  ADD CONSTRAINT fk_sales_served_by
    FOREIGN KEY (served_by) REFERENCES users(id) ON DELETE RESTRICT,
  ADD CONSTRAINT fk_sales_receipt_printed_by
    FOREIGN KEY (receipt_printed_by) REFERENCES users(id) ON DELETE RESTRICT;
