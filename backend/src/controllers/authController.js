const asyncHandler = require('../utils/asyncHandler');
const { ok, created } = require('../utils/apiResponse');
const authService = require('../services/authService');

const login = asyncHandler(async (req, res) => {
  const result = await authService.login(req.body);
  ok(res, result);
});

// Cashier PIN login: POST /api/auth/login-pin — { pin } only, no
// email/username. See authService.loginWithPin for how the user is
// resolved from the PIN alone.
const loginPin = asyncHandler(async (req, res) => {
  const result = await authService.loginWithPin(req.body);
  ok(res, result);
});

const me = asyncHandler(async (req, res) => {
  const user = await authService.me(req.user.id);
  ok(res, { user });
});

// Logout is stateless on the server (JWT access tokens are short-lived and
// not stored server-side). Flutter is responsible for deleting the token
// from secure storage. This endpoint exists so the client has a single,
// consistent place to call and so a future token-blacklist can be added
// here without changing the client.
const logout = asyncHandler(async (req, res) => {
  ok(res, { message: 'Logged out' });
});

// Admin-only: provision a new cashier/manager/admin account for the store.
const createUser = asyncHandler(async (req, res) => {
  const user = await authService.createUser({
    ...req.body,
    store_id: req.body.store_id || req.user.storeId,
  });
  created(res, { user });
});

// Admin-only: list cashiers/managers/admins for the caller's own store.
const listUsers = asyncHandler(async (req, res) => {
  const result = await authService.listUsers(req.user.storeId, req.query);
  ok(res, result);
});

// Admin-only: update a cashier/manager/admin's name/role/active state, or
// reset their password.
const updateUser = asyncHandler(async (req, res) => {
  const user = await authService.updateUser(
    req.user.storeId,
    req.params.id,
    req.body,
    req.user.id
  );
  ok(res, { user });
});

// Admin-only: assign/change a cashier's PIN (Users → [name] → Change PIN).
const setPin = asyncHandler(async (req, res) => {
  const user = await authService.setPin(
    req.user.storeId,
    req.params.id,
    req.body.pin,
    req.user.id
  );
  ok(res, { user });
});

module.exports = { login, loginPin, me, logout, createUser, listUsers, updateUser, setPin };
