-- =====================================================================
-- Store POS — MySQL schema (migration 008)
-- Ingredient delete integrity fix.
--
-- WHY THIS MIGRATION EXISTS
-- -------------------------
-- migrations/006_ingredients.sql originally defined:
--   product_ingredients.ingredient_id       -> ingredients(id) ON DELETE CASCADE
--   ingredient_stock_movements.ingredient_id -> ingredients(id) ON DELETE CASCADE
--
-- CASCADE here is dangerous: deleting an ingredient/supply would
-- silently wipe out
--   - every product recipe line that uses it (product_ingredients), and
--   - its entire purchase/sale/adjustment/damage audit trail
--     (ingredient_stock_movements)
-- with no warning and no way to recover the history.
--
-- The application layer (ingredientService.remove) now checks for recipe
-- usage and stock/expense history BEFORE attempting a delete, and refuses
-- with a precise INGREDIENT_IN_USE / INGREDIENT_HAS_HISTORY error when
-- either is found. This migration makes that behavior the DB's own
-- guarantee too (the same RESTRICT pattern already used for
-- sale_items.product_id -> products.id, see migrations/001_init.sql),
-- so a bug or a bypass in the application layer can never silently
-- destroy recipe or audit data — the DB will simply refuse the DELETE
-- (MySQL error 1451 / ER_ROW_IS_REFERENCED_2) as a backstop.
--
-- Written as a stored procedure so it is idempotent / safe to run
-- against a database in either state (whatever the current constraint
-- name or action actually is), per the requirement not to assume the
-- live schema matches the original migration files exactly. No
-- DELIMITER directive is used/needed: this file is executed as a single
-- multi-statement batch by scripts/migrate.js (mysql2 with
-- multipleStatements: true), which hands the whole CREATE PROCEDURE
-- statement to the MySQL server in one piece — the server's own parser
-- (not a client-side line-splitter) is what needs to see the matching
-- BEGIN/END, and it does regardless of DELIMITER.
-- =====================================================================

SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS _migrate_008_fix_ingredient_fks;

CREATE PROCEDURE _migrate_008_fix_ingredient_fks()
BEGIN
  DECLARE existing_fk VARCHAR(128);

  -- ---- product_ingredients.ingredient_id -> ingredients.id ----
  SELECT CONSTRAINT_NAME INTO existing_fk
    FROM information_schema.KEY_COLUMN_USAGE
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = 'product_ingredients'
     AND COLUMN_NAME = 'ingredient_id'
     AND REFERENCED_TABLE_NAME = 'ingredients'
   LIMIT 1;

  IF existing_fk IS NOT NULL THEN
    SET @drop_sql = CONCAT('ALTER TABLE product_ingredients DROP FOREIGN KEY `', existing_fk, '`');
    PREPARE stmt FROM @drop_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;

  ALTER TABLE product_ingredients
    ADD CONSTRAINT fk_product_ingredients_ingredient
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT;

  -- ---- ingredient_stock_movements.ingredient_id -> ingredients.id ----
  SET existing_fk = NULL;
  SELECT CONSTRAINT_NAME INTO existing_fk
    FROM information_schema.KEY_COLUMN_USAGE
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = 'ingredient_stock_movements'
     AND COLUMN_NAME = 'ingredient_id'
     AND REFERENCED_TABLE_NAME = 'ingredients'
   LIMIT 1;

  IF existing_fk IS NOT NULL THEN
    SET @drop_sql2 = CONCAT('ALTER TABLE ingredient_stock_movements DROP FOREIGN KEY `', existing_fk, '`');
    PREPARE stmt2 FROM @drop_sql2;
    EXECUTE stmt2;
    DEALLOCATE PREPARE stmt2;
  END IF;

  ALTER TABLE ingredient_stock_movements
    ADD CONSTRAINT fk_ingredient_movements_ingredient
    FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT;
END;

CALL _migrate_008_fix_ingredient_fks();

DROP PROCEDURE IF EXISTS _migrate_008_fix_ingredient_fks;
