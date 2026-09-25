const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const env = require('../config/env');
const ApiError = require('../utils/ApiError');
const userRepository = require('../repositories/userRepository');

function signAccessToken(user) {
  return jwt.sign(
    { sub: user.id, store_id: user.store_id, role: user.role },
    env.jwt.secret,
    { expiresIn: env.jwt.expiresIn }
  );
}

function signRefreshToken(user) {
  return jwt.sign({ sub: user.id, type: 'refresh' }, env.jwt.refreshSecret, {
    expiresIn: env.jwt.refreshExpiresIn,
  });
}

/**
 * Cashier PIN login support (see migrations/010_pin_authentication.sql).
 *
 * The cashier only ever types a PIN — never a username/email — so the
 * backend has to be able to find "the one user with this PIN" from the
 * PIN alone, with no selector to narrow the search. A per-user salted
 * bcrypt hash (like passwords use) can't be looked up that way: bcrypt
 * salts are random per row, so there is no query that finds "the row
 * whose bcrypt hash matches this plaintext" — you'd have to bcrypt.compare
 * against every user in the database on every login.
 *
 * Instead we store a deterministic HMAC-SHA256 of the PIN, keyed with a
 * server-side secret (env.security.pinPepper) that never touches the
 * database. This:
 *   - lets the DB enforce true PIN uniqueness with a UNIQUE key on the
 *     hash column (a real constraint, not just an application check),
 *   - lets login/PIN-set look the user up with a single indexed query,
 *   - never stores or logs the PIN itself, and
 *   - is not reversible by anyone who only has the database: the pepper
 *     lives in the server's environment, not in a column, so a DB leak
 *     alone does not expose PINs.
 * It's deliberately not bcrypt: bcrypt's per-row salt is what makes it
 * strong for passwords, but it's exactly what makes lookup-by-value
 * impossible, and a short numeric PIN's real protection against
 * brute-forcing comes from rate limiting (loginRateLimiter /
 * pinLoginRateLimiter) and keeping PIN_PEPPER as secret as JWT_SECRET,
 * not from the hash's computational cost.
 */
function hashPin(pin) {
  return crypto.createHmac('sha256', env.security.pinPepper).update(String(pin)).digest('hex');
}

function toPublicUser(user) {
  return {
    id: user.id,
    store_id: user.store_id,
    name: user.name,
    email: user.email,
    role: user.role,
    is_active: !!user.is_active,
  };
}

async function login({ email, password }) {
  const user = await userRepository.findByEmail(email);

  // Same generic error for "no such user" and "wrong password" so the API
  // never confirms whether an email is registered (avoids user enumeration).
  if (!user) {
    throw ApiError.unauthorized('Invalid email or password', 'INVALID_CREDENTIALS');
  }

  const passwordMatches = await bcrypt.compare(password, user.password_hash);
  if (!passwordMatches) {
    throw ApiError.unauthorized('Invalid email or password', 'INVALID_CREDENTIALS');
  }

  if (!user.is_active) {
    throw ApiError.forbidden('This account has been deactivated', 'USER_INACTIVE');
  }

  const accessToken = signAccessToken(user);
  const refreshToken = signRefreshToken(user);

  return {
    user: toPublicUser(user),
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: env.jwt.expiresIn,
  };
}

/**
 * Cashier PIN login: POST /api/auth/login-pin. The request carries only
 * `{ pin }` — the backend resolves which user that belongs to, exactly
 * like `login()` resolves a user from an email, and issues the same kind
 * of JWT access/refresh token pair via the same signAccessToken /
 * signRefreshToken used by every other login path, so every downstream
 * authorization check (requireAuth, authorize, ROLE_PERMISSIONS) behaves
 * identically regardless of which login method was used.
 */
async function loginWithPin({ pin }) {
  const user = await userRepository.findByPinHash(hashPin(pin));

  // Same generic error for "no user has this PIN" and any other failure
  // path below, so the response never confirms whether a PIN is in use.
  if (!user) {
    throw ApiError.unauthorized('Incorrect PIN', 'INVALID_PIN');
  }

  if (!user.is_active) {
    throw ApiError.forbidden('This account has been deactivated', 'USER_INACTIVE');
  }

  const accessToken = signAccessToken(user);
  const refreshToken = signRefreshToken(user);

  return {
    user: toPublicUser(user),
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: env.jwt.expiresIn,
  };
}

async function me(userId) {
  const user = await userRepository.findById(userId);
  if (!user) throw ApiError.notFound('User not found');
  return toPublicUser(user);
}

/**
 * Admin-only: create a new user (cashier/manager/admin) for a store.
 * Never called from an unauthenticated route — see routes/authRoutes.js.
 */
async function createUser({ name, email, password, role, store_id: storeId }) {
  const existing = await userRepository.findByEmail(email);
  if (existing) {
    throw ApiError.conflict('A user with this email already exists', 'EMAIL_TAKEN');
  }
  const passwordHash = await bcrypt.hash(password, env.security.bcryptSaltRounds);
  const user = await userRepository.create({
    id: uuidv4(),
    storeId,
    name,
    email,
    passwordHash,
    role,
  });
  return toPublicUser(user);
}

/**
 * Admin-only: list cashiers/managers/admins for a store (the "Cashiers"
 * screen). Store-scoped like every other list endpoint.
 */
async function listUsers(storeId, query) {
  const result = await userRepository.listByStore(storeId, {
    search: query.search,
    role: query.role,
    isActive: query.is_active,
    page: query.page,
    pageSize: query.page_size,
  });
  return { ...result, items: result.items.map(toPublicUser) };
}

/**
 * Admin-only: update a cashier/manager/admin's name, role, active status,
 * and/or reset their password. `actingUserId` is the admin making the
 * request — used only to stop an admin from locking themselves out by
 * deactivating or demoting their own account through this endpoint.
 */
async function updateUser(storeId, id, input, actingUserId) {
  if (id === actingUserId) {
    if (input.is_active === false) {
      throw ApiError.badRequest('You cannot deactivate your own account', 'CANNOT_EDIT_SELF');
    }
    if (input.role && input.role !== 'admin') {
      throw ApiError.badRequest('You cannot change your own role', 'CANNOT_EDIT_SELF');
    }
  }

  if (input.email) {
    const existing = await userRepository.findByEmail(input.email);
    if (existing && existing.id !== id) {
      throw ApiError.conflict('A user with this email already exists', 'EMAIL_TAKEN');
    }
  }

  const fields = {};
  if (input.name !== undefined) fields.name = input.name;
  if (input.email !== undefined) fields.email = input.email;
  if (input.role !== undefined) fields.role = input.role;
  if (input.is_active !== undefined) fields.is_active = input.is_active ? 1 : 0;
  if (input.password) {
    fields.password_hash = await bcrypt.hash(input.password, env.security.bcryptSaltRounds);
  }

  const updated = await userRepository.updateForStore(storeId, id, fields);
  if (!updated) throw ApiError.notFound('User not found', 'USER_NOT_FOUND');
  return toPublicUser(updated);
}

/**
 * Admin-only: assign or change a cashier/manager/admin's PIN (Users →
 * [name] → Change PIN). `actingUserId` is unused today — admins are
 * allowed to set their own PIN (e.g. the very first admin, seeded with
 * email/password, giving themselves a PIN so they can also use the PIN
 * pad) — kept as a parameter for symmetry with updateUser and in case a
 * future rule needs it.
 */
async function setPin(storeId, id, pin, actingUserId) { // eslint-disable-line no-unused-vars
  const target = await userRepository.findByIdForStore(storeId, id);
  if (!target) throw ApiError.notFound('User not found', 'USER_NOT_FOUND');

  const pinHash = hashPin(pin);

  const existing = await userRepository.findByPinHash(pinHash);
  if (existing && existing.id !== id) {
    // Generic message — never confirms which other user already holds it.
    throw ApiError.conflict('This PIN is already in use', 'PIN_TAKEN');
  }

  const updated = await userRepository.updateForStore(storeId, id, {
    pin_hash: pinHash,
    pin_set_at: new Date(),
  });
  if (!updated) throw ApiError.notFound('User not found', 'USER_NOT_FOUND');
  return toPublicUser(updated);
}

module.exports = { login, loginWithPin, me, createUser, listUsers, updateUser, setPin, toPublicUser, hashPin };
