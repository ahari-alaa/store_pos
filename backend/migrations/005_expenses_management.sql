-- =====================================================================
-- Store POS — MySQL schema (migration 005)
-- Expenses & Supplies Management System.
--
-- Extends the EXISTING `expenses` table (see 001_init.sql) rather than
-- replacing it — every new column is nullable or defaulted, so rows
-- created before this migration (amount/category/description only)
-- stay perfectly valid: they just read as expense_type = 'AUTRE' with
-- no quantity/unit/pricing breakdown, exactly as before.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- expense_categories — configurable categories per store, each grouped
-- under one of the three expense types from the spec (Approvisionnements
-- / Charges fixes / Autres). A plain free-text `category` on the
-- `expenses` row is still supported for quick entry without picking a
-- category (backward compatible with the pre-existing API), but the
-- Flutter UI drives selection from this table.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expense_categories (
  id            CHAR(36)      NOT NULL PRIMARY KEY,
  store_id      CHAR(36)      NOT NULL,
  name          VARCHAR(100)  NOT NULL,
  expense_type  ENUM('APPROVISIONNEMENT','CHARGE_FIXE','AUTRE') NOT NULL,
  is_active     TINYINT(1)    NOT NULL DEFAULT 1,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  -- Same name can legitimately exist under two types (e.g. "Eau" the
  -- bottled-water supply vs. "Eau" the water utility bill), so the
  -- uniqueness key includes expense_type, not just (store_id, name).
  UNIQUE KEY uq_expense_categories_store_name_type (store_id, name, expense_type),
  KEY idx_expense_categories_store_type (store_id, expense_type),
  CONSTRAINT fk_expense_categories_store FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ---------------------------------------------------------------------
-- expenses — new columns for the supplies/monthly-bills feature.
-- ---------------------------------------------------------------------
ALTER TABLE expenses
  ADD COLUMN expense_type      ENUM('APPROVISIONNEMENT','CHARGE_FIXE','AUTRE') NOT NULL DEFAULT 'AUTRE' AFTER category,
  ADD COLUMN category_id       CHAR(36)      NULL AFTER expense_type,
  ADD COLUMN quantity          DECIMAL(12,3) NULL AFTER description,
  ADD COLUMN unit              ENUM('kg','g','l','ml','unit','pack','box','bottle','piece') NULL AFTER quantity,
  ADD COLUMN unit_price        DECIMAL(12,2) NULL AFTER unit,
  ADD COLUMN supplier_id       CHAR(36)      NULL AFTER unit_price,
  ADD COLUMN supplier_name     VARCHAR(200)  NULL AFTER supplier_id,
  ADD COLUMN notes             VARCHAR(1000) NULL AFTER supplier_name,
  ADD COLUMN product_id        CHAR(36)      NULL AFTER notes,
  ADD COLUMN affects_inventory TINYINT(1)    NOT NULL DEFAULT 0 AFTER product_id,
  ADD COLUMN is_recurring      TINYINT(1)    NOT NULL DEFAULT 0 AFTER affects_inventory,
  ADD COLUMN recurring_day     TINYINT       NULL AFTER is_recurring,
  ADD COLUMN receipt_url       VARCHAR(500)  NULL AFTER recurring_day,
  ADD CONSTRAINT fk_expenses_category FOREIGN KEY (category_id) REFERENCES expense_categories(id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_expenses_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
  ADD CONSTRAINT fk_expenses_product  FOREIGN KEY (product_id)  REFERENCES products(id)  ON DELETE SET NULL,
  ADD KEY idx_expenses_store_type (store_id, expense_type),
  ADD KEY idx_expenses_category (store_id, category_id),
  ADD KEY idx_expenses_product (product_id),
  ADD KEY idx_expenses_supplier (supplier_id);

-- ---------------------------------------------------------------------
-- Seed default categories for every existing store, matching the
-- spec's example lists. Idempotent: UNIQUE(store_id, name, expense_type)
-- + INSERT IGNORE means re-running this migration file is a no-op the
-- second time (and the migration runner itself only ever applies a file
-- once anyway — see scripts/migrate.js).
-- ---------------------------------------------------------------------
INSERT IGNORE INTO expense_categories (id, store_id, name, expense_type)
SELECT UUID(), s.id, c.name, c.expense_type
FROM stores s
CROSS JOIN (
  SELECT 'Café' AS name, 'APPROVISIONNEMENT' AS expense_type
  UNION ALL SELECT 'Fruits', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Eau', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Lait', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Sucre', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Produits alimentaires', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Emballages', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Produits de nettoyage', 'APPROVISIONNEMENT'
  UNION ALL SELECT 'Électricité', 'CHARGE_FIXE'
  UNION ALL SELECT 'Eau', 'CHARGE_FIXE'
  UNION ALL SELECT 'Internet', 'CHARGE_FIXE'
  UNION ALL SELECT 'Téléphone', 'CHARGE_FIXE'
  UNION ALL SELECT 'Loyer', 'CHARGE_FIXE'
  UNION ALL SELECT 'Gaz', 'CHARGE_FIXE'
  UNION ALL SELECT 'Maintenance', 'AUTRE'
  UNION ALL SELECT 'Réparation', 'AUTRE'
  UNION ALL SELECT 'Transport', 'AUTRE'
  UNION ALL SELECT 'Équipement', 'AUTRE'
  UNION ALL SELECT 'Divers', 'AUTRE'
) c;
