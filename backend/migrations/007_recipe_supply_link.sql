-- =====================================================================
-- Store POS — MySQL schema (migration 007)
-- Supplies → Recipe → Yield → Auto-consumption.
--
-- This migration does NOT create a second stock system. It connects the
-- two that already exist:
--   - `ingredients`             = the real Supplies / Inventory stock
--     (single source of truth for raw-material quantity, migration 006)
--   - `expenses` (APPROVISIONNEMENT) = purchases (migration 005)
--
-- Adds:
--  1. product_ingredients.unit — the recipe line can now be entered in a
--     unit different from the ingredient's own storage unit (e.g. a
--     recipe in grams for an ingredient stocked in kg). NULL means "same
--     as the ingredient's unit", so every existing recipe row keeps
--     working exactly as before with zero data migration required.
--  2. expenses.ingredient_id — a purchase (Expenses → Approvisionnement)
--     can now restock a `ingredients` row directly, the same way it
--     already restocks a finished `products` row via expenses.product_id.
--     Exactly one of (product_id, ingredient_id) may be set — enforced
--     in expenseService, not the DB, to keep the same validation style
--     as the rest of this schema.
-- =====================================================================

SET NAMES utf8mb4;

ALTER TABLE product_ingredients
  ADD COLUMN unit ENUM('g','kg','ml','l','unit') NULL AFTER quantity;

ALTER TABLE expenses
  ADD COLUMN ingredient_id CHAR(36) NULL AFTER product_id,
  ADD CONSTRAINT fk_expenses_ingredient FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE SET NULL,
  ADD KEY idx_expenses_ingredient (ingredient_id);
