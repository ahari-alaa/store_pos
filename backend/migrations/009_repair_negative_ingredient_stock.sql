-- =====================================================================
-- Store POS — MySQL schema (migration 009)
-- Repair legacy negative ingredient stock + delete-flow follow-up.
--
-- WHY THIS MIGRATION EXISTS
-- -------------------------
-- Before this change, an ingredient's stock_quantity could be driven
-- negative in practice (e.g. the "café -425.0 kg" case): an expense that
-- had added stock was edited/deleted long after sales had already
-- consumed most or all of it, and the old reversal logic subtracted the
-- full original purchase amount unconditionally instead of clamping at
-- zero. That specific bug is already fixed at the application layer —
-- ingredientRepository.clampedAdjustStock (used by
-- expenseService.reverseIngredientPurchase) now floors any reversal at
-- zero, and ingredientRepository.adjustStock's own UPDATE ... WHERE
-- stock_quantity + delta >= 0 guarantees no future write can ever take a
-- row below zero again — see migrations/006_ingredients.sql for the
-- column definition and src/repositories/ingredientRepository.js for
-- both guards.
--
-- This migration is the one-time DATA repair for rows that already went
-- negative before that guard existed. We deliberately do NOT try to
-- replay/recompute stock_quantity from the full
-- ingredient_stock_movements ledger here: that ledger is an authoritative
-- AUDIT TRAIL of what happened (purchases, sales, adjustments, damage)
-- and must not be rewritten or reinterpreted by a migration, and a
-- ledger that is itself incomplete (e.g. movements recorded before the
-- feature existed) could make a "replay" repair produce a different
-- wrong number instead of a right one. The safe, conservative floor is
-- simply: stock can never legitimately be negative, so any existing
-- negative value is clamped to 0. This matches the same "floor at zero,
-- never guess a positive number back into existence" principle already
-- used by clampedAdjustStock above, and it only ever *raises* a value
-- that was already known to be wrong, never modifies a valid one.
--
-- Idempotent: safe to run more than once (a second run is a no-op).
-- =====================================================================

SET NAMES utf8mb4;

UPDATE ingredients
   SET stock_quantity = 0.000
 WHERE stock_quantity < 0;
