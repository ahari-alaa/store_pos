-- =====================================================================
-- Store POS — MySQL schema (migration 006)
-- Ingredients / Recipe / Auto-consumption module.
--
-- Adds:
--  - ingredients        : raw stock items (Café, Eau, Sucre, Bouteille...)
--                          tracked in their own unit (kg, L, unit...).
--  - product_ingredients: the "recipe" — how much of each ingredient one
--                          unit of a product consumes (Produits →
--                          Modifier le produit → Ingrédients / Recette).
--  - ingredient_stock_movements: append-only ledger mirroring
--                          inventory_movements but for ingredients, so a
--                          sale, a manual restock or an adjustment are all
--                          auditable (Stocks des ingrédients screen).
-- =====================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS ingredients (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  store_id        CHAR(36)      NOT NULL,
  name            VARCHAR(150)  NOT NULL,
  unit            ENUM('g','kg','ml','l','unit') NOT NULL DEFAULT 'unit',
  stock_quantity  DECIMAL(14,3) NOT NULL DEFAULT 0.000,
  min_stock       DECIMAL(14,3) NOT NULL DEFAULT 0.000,
  cost_per_unit   DECIMAL(12,4) NOT NULL DEFAULT 0.0000,
  is_active       TINYINT(1)    NOT NULL DEFAULT 1,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_ingredients_store_name (store_id, name),
  KEY idx_ingredients_store (store_id),
  CONSTRAINT fk_ingredients_store FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS product_ingredients (
  id             CHAR(36)      NOT NULL PRIMARY KEY,
  store_id       CHAR(36)      NOT NULL,
  product_id     CHAR(36)      NOT NULL,
  ingredient_id  CHAR(36)      NOT NULL,
  -- Quantity of the ingredient (in the ingredient's own unit) consumed by
  -- ONE unit sold of this product — e.g. 25 g of Café per Café sold.
  quantity       DECIMAL(14,3) NOT NULL,
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_product_ingredients (product_id, ingredient_id),
  KEY idx_product_ingredients_product (store_id, product_id),
  KEY idx_product_ingredients_ingredient (store_id, ingredient_id),
  CONSTRAINT fk_product_ingredients_store      FOREIGN KEY (store_id)      REFERENCES stores(id)      ON DELETE CASCADE,
  CONSTRAINT fk_product_ingredients_product    FOREIGN KEY (product_id)    REFERENCES products(id)    ON DELETE CASCADE,
  CONSTRAINT fk_product_ingredients_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS ingredient_stock_movements (
  id              CHAR(36)      NOT NULL PRIMARY KEY,
  store_id        CHAR(36)      NOT NULL,
  ingredient_id   CHAR(36)      NOT NULL,
  quantity_delta  DECIMAL(14,3) NOT NULL,
  movement_type   ENUM('PURCHASE','SALE_CONSUMPTION','ADJUSTMENT','DAMAGE') NOT NULL,
  reference_id    CHAR(36)      NULL,
  note            VARCHAR(300),
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_ingredient_movements_store_ingredient (store_id, ingredient_id),
  KEY idx_ingredient_movements_reference (reference_id),
  CONSTRAINT fk_ingredient_movements_store      FOREIGN KEY (store_id)      REFERENCES stores(id)      ON DELETE CASCADE,
  CONSTRAINT fk_ingredient_movements_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
