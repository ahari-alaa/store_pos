-- =====================================================================
-- Store POS — MySQL data migration (migration 013)
-- OPTIONAL: mark sales that pre-date the serving workflow as served.
--
-- Migration 012 adds `served_at` as NULL for every existing sale, and NULL
-- means "à servir". Without this file, every cashier would open the new
-- Rapport screen and find their ENTIRE sales history waiting to be served.
--
-- This only fills the new columns for rows that exist RIGHT NOW. It does
-- not change any original column (totals, statuses, payments, items), so
-- revenue and every report stay identical.
--
--   served_at = the sale's own occurred_at   (no "served" time was ever
--                                            recorded; the receipt was
--                                            handed over at the register)
--   served_by = NULL                          (unknown — the UI/admin view
--                                            shows these as "historique")
--
-- DELETE THIS FILE before running `npm run migrate` if you would rather
-- keep old orders in the "à servir" queue.
-- =====================================================================

SET NAMES utf8mb4;

UPDATE sales
   SET served_at = occurred_at
 WHERE served_at IS NULL;
