require('dotenv').config();

/**
 * Centralized, validated environment configuration.
 * Fail fast at boot if a required secret is missing, rather than
 * silently running with an undefined JWT secret in production.
 */
function required(name, { allowEmptyInTest = false } = {}) {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    if (process.env.NODE_ENV === 'test' && allowEmptyInTest) return '';
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const env = {
  nodeEnv: process.env.NODE_ENV || 'development',
  port: parseInt(process.env.PORT || '3000', 10),

  db: {
    host: process.env.DB_HOST || '127.0.0.1',
    port: parseInt(process.env.DB_PORT || '3306', 10),
    name: required('DB_NAME'),
    user: required('DB_USER'),
    password: process.env.DB_PASSWORD || '',
    connectionLimit: parseInt(process.env.DB_CONNECTION_LIMIT || '10', 10),
  },

  jwt: {
    secret: required('JWT_SECRET'),
    expiresIn: process.env.JWT_EXPIRES_IN || '12h',
    refreshSecret: process.env.JWT_REFRESH_SECRET || required('JWT_SECRET'),
    refreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  },

  security: {
    bcryptSaltRounds: parseInt(process.env.BCRYPT_SALT_ROUNDS || '12', 10),
    loginRateLimitWindowMinutes: parseInt(
      process.env.LOGIN_RATE_LIMIT_WINDOW_MINUTES || '15',
      10
    ),
    loginRateLimitMaxAttempts: parseInt(
      process.env.LOGIN_RATE_LIMIT_MAX_ATTEMPTS || '10',
      10
    ),
    // Cashier PIN login (see authService.js#hashPin / migrations/010).
    // Separate secret from JWT_SECRET on purpose: it's the key for a
    // deterministic HMAC used only to look a user up by their PIN, so it
    // must never be reused for anything else that gets logged or exposed.
    pinPepper: required('PIN_PEPPER', { allowEmptyInTest: true }) || 'test-pin-pepper',
    pinLoginRateLimitWindowMinutes: parseInt(
      process.env.PIN_LOGIN_RATE_LIMIT_WINDOW_MINUTES || '15',
      10
    ),
    pinLoginRateLimitMaxAttempts: parseInt(
      process.env.PIN_LOGIN_RATE_LIMIT_MAX_ATTEMPTS || '8',
      10
    ),
    corsOrigin: process.env.CORS_ORIGIN || '*',
  },
};

module.exports = env;
