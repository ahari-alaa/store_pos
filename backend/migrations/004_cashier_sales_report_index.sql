-- =====================================================================
-- Store POS — MySQL schema (migration 004)
-- Adds the composite index the new cashier sales report queries
-- (saleRepository.cashierSalesSummary / cashierSalesByDay) filter and
-- group by: store_id + user_id (WHERE) + occurred_at (WHERE range /
-- GROUP BY DATE(...)). The existing idx_sales_store_created and
-- idx_sales_user indexes don't cover this combination, so a cashier's
-- monthly report on a large store would otherwise fall back to a
-- store-wide scan.
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE sales
  ADD INDEX idx_sales_store_user_occurred (store_id, user_id, occurred_at);
