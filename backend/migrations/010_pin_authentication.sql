-- =====================================================================
-- Store POS — MySQL schema (migration 010)
-- Cashier PIN login.
--
-- WHY THESE COLUMNS
-- ------------------
-- The cashier login screen now asks only for a PIN (no email, no user
-- picker) — the backend has to resolve exactly which user that PIN
-- belongs to on its own. That requires being able to look a user up BY
-- their PIN, which a per-row-salted bcrypt hash (like password_hash)
-- cannot support: there is no query that finds "the row whose bcrypt
-- hash matches this plaintext" short of bcrypt.compare-ing every user in
-- the table on every login attempt.
--
-- `pin_hash` instead stores a deterministic HMAC-SHA256 of the PIN,
-- keyed with a server-only secret (PIN_PEPPER, see src/config/env.js and
-- src/services/authService.js#hashPin) that is never written to the
-- database. Two consequences of that, both intentional:
--   * PIN uniqueness is enforced by a real UNIQUE key on this column
--     (see below), not just an application-side check.
--   * A copy of the database alone does not reveal any PIN — the pepper
--     that would be needed to test guesses against these hashes lives
--     only in the server's environment, exactly like JWT_SECRET.
-- `pin_hash` is nullable: existing admin/manager accounts keep working
-- with email/password (see BACKWARD COMPATIBILITY in authRoutes.js) and
-- are not required to have a PIN. MySQL's UNIQUE key allows any number
-- of NULLs, so that doesn't conflict with enforcing uniqueness among the
-- users that DO have a PIN set.
--
-- `pin_set_at` is informational only (e.g. for a future "PIN last
-- changed" display) — nothing currently reads it besides
-- authService.setPin writing it.
-- =====================================================================

ALTER TABLE users
  ADD COLUMN pin_hash    CHAR(64)  NULL AFTER password_hash,
  ADD COLUMN pin_set_at  DATETIME  NULL AFTER pin_hash,
  ADD UNIQUE KEY uq_users_pin_hash (pin_hash);
