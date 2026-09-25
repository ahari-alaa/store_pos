-- =====================================================================
-- Store POS — MySQL schema (migration 003)
-- Adds product photos (Products screen "Add image").
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE products
  ADD COLUMN image_url VARCHAR(500) NULL AFTER category;
