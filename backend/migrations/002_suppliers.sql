-- =====================================================================
-- Store POS — MySQL schema (migration 002)
-- Adds the `suppliers` module (Purchases/Suppliers screen).
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS suppliers (
  id            CHAR(36)      NOT NULL PRIMARY KEY,
  store_id      CHAR(36)      NOT NULL,
  name          VARCHAR(200)  NOT NULL,
  contact_name  VARCHAR(150),
  phone         VARCHAR(40),
  email         VARCHAR(190),
  address       VARCHAR(300),
  notes         VARCHAR(500),
  is_active     TINYINT(1)    NOT NULL DEFAULT 1,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY idx_suppliers_store (store_id),
  CONSTRAINT fk_suppliers_store FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
