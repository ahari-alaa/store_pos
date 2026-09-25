const express = require('express');
const controller = require('../controllers/authController');
const validate = require('../middleware/validate');
const { login, loginPin, setPin, createUser, listUsers, updateUser } = require('../validators/authValidators');
const { requireAuth } = require('../middleware/auth');
const { authorize } = require('../middleware/authorize');
const { loginRateLimiter, pinLoginRateLimiter } = require('../middleware/rateLimiter');

const router = express.Router();

router.post('/login', loginRateLimiter, validate(login), controller.login);

// Cashier PIN login — the POS app's only login screen. Kept alongside
// (not replacing) /login: admin/manager accounts can still authenticate
// with email/password against the same users table if a future
// admin-only surface needs it (see BACKWARD COMPATIBILITY in the spec).
router.post('/login-pin', pinLoginRateLimiter, validate(loginPin), controller.loginPin);

router.post('/logout', requireAuth, controller.logout);
router.get('/me', requireAuth, controller.me);

// Only an admin can provision new accounts for their own store.
router.post(
  '/users',
  requireAuth,
  authorize('admin'),
  validate(createUser),
  controller.createUser
);

// Cashiers screen: list + edit/deactivate existing accounts. Admin-only,
// same as provisioning (section 9 of the spec: only an admin manages staff).
router.get(
  '/users',
  requireAuth,
  authorize('admin'),
  validate(listUsers, 'query'),
  controller.listUsers
);
router.put(
  '/users/:id',
  requireAuth,
  authorize('admin'),
  validate(updateUser),
  controller.updateUser
);

// Admin-only: assign/change a staff member's PIN (Users → [name] →
// Change PIN). Same permission gate as every other user-management route.
router.put(
  '/users/:id/pin',
  requireAuth,
  authorize('admin'),
  validate(setPin),
  controller.setPin
);

module.exports = router;
