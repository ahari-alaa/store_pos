-- =====================================================================
-- Store POS — MySQL schema (migration 011)
-- Additive, data-neutral index for the Rapports queries.
--
-- Every report filters `sales` by store_id + a range on occurred_at
-- (the sale's business time). The existing indexes cover
-- (store_id, created_at) and (store_id, user_id, occurred_at), neither of
-- which can serve a store-wide occurred_at range, so a monthly report
-- would read every sale the store ever made. This index lets MySQL jump
-- straight to the requested period. Safe to skip on a small database.
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE sales
  ADD INDEX idx_sales_store_occurred (store_id, occurred_at);
