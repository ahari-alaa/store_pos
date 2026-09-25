const rateLimit = require('express-rate-limit');
const env = require('../config/env');

const loginRateLimiter = rateLimit({
  windowMs: env.security.loginRateLimitWindowMinutes * 60 * 1000,
  max: env.security.loginRateLimitMaxAttempts,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'TOO_MANY_ATTEMPTS',
      message: 'Too many login attempts. Please try again later.',
    },
  },
});

// Separate bucket from loginRateLimiter so PIN attempts and email/password
// attempts don't share (or exhaust) each other's allowance, and so its
// window/max can be tuned independently — a PIN's small digit space
// generally warrants a tighter limit than a password.
const pinLoginRateLimiter = rateLimit({
  windowMs: env.security.pinLoginRateLimitWindowMinutes * 60 * 1000,
  max: env.security.pinLoginRateLimitMaxAttempts,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'TOO_MANY_ATTEMPTS',
      message: 'Too many login attempts. Please try again later.',
    },
  },
});

module.exports = { loginRateLimiter, pinLoginRateLimiter };
