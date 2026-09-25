/**
 * Creates the first store and its admin user, so there is a way to log in
 * before any other account exists. Safe to re-run: does nothing if a store
 * with the configured name already exists.
 *
 * Usage:
 *   npm run seed:admin
 *
 * Configure via env vars (see .env.example):
 *   SEED_STORE_NAME, SEED_ADMIN_NAME, SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD
 *
 * SEED_ADMIN_PIN (optional): the Flutter app's login screen is PIN-only
 * (see migrations/010_pin_authentication.sql), so without this the first
 * admin has no way to sign into it — they'd only be able to call
 * POST /api/auth/login (email/password) directly, e.g. via curl/Postman,
 * and then PUT /api/auth/users/:id/pin to give themselves a PIN. Setting
 * SEED_ADMIN_PIN here does that in one step. Must be 4-6 digits.
 */
require('dotenv').config();
const crypto = require('crypto');
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

const PIN_PATTERN = /^\d{4,6}$/;

// Mirrors authService.js#hashPin exactly — see that function for why a
// keyed HMAC is used instead of bcrypt for the PIN specifically. Kept as
// a standalone copy here rather than requiring authService.js, since
// authService.js pulls in the full Express app config (env.js#required)
// this standalone script doesn't otherwise need.
function hashPin(pin, pepper) {
  return crypto.createHmac('sha256', pepper).update(String(pin)).digest('hex');
}

async function main() {
  const storeName = process.env.SEED_STORE_NAME || 'Main Store';
  const adminName = process.env.SEED_ADMIN_NAME || 'Store Admin';
  const adminEmail = process.env.SEED_ADMIN_EMAIL;
  const adminPassword = process.env.SEED_ADMIN_PASSWORD;
  const adminPin = process.env.SEED_ADMIN_PIN;
  const saltRounds = parseInt(process.env.BCRYPT_SALT_ROUNDS || '12', 10);

  if (!adminEmail || !adminPassword) {
    console.error('SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD must be set in .env');
    process.exit(1);
  }

  if (adminPin && !PIN_PATTERN.test(adminPin)) {
    console.error('SEED_ADMIN_PIN must be 4 to 6 digits');
    process.exit(1);
  }
  if (adminPin && !process.env.PIN_PEPPER) {
    console.error('PIN_PEPPER must be set in .env to seed SEED_ADMIN_PIN');
    process.exit(1);
  }

  const connection = await mysql.createConnection({
    host: process.env.DB_HOST || '127.0.0.1',
    port: parseInt(process.env.DB_PORT || '3306', 10),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });

  const [existingUsers] = await connection.query('SELECT id FROM users WHERE email = ?', [
    adminEmail,
  ]);
  if (existingUsers.length > 0) {
    console.log(`Admin user ${adminEmail} already exists. Nothing to do.`);
    await connection.end();
    return;
  }

  let [stores] = await connection.query('SELECT id FROM stores WHERE name = ?', [storeName]);
  let storeId;
  if (stores.length > 0) {
    storeId = stores[0].id;
  } else {
    storeId = uuidv4();
    await connection.query('INSERT INTO stores (id, name) VALUES (?, ?)', [storeId, storeName]);
    console.log(`Created store "${storeName}" (${storeId})`);
  }

  const passwordHash = await bcrypt.hash(adminPassword, saltRounds);
  const userId = uuidv4();
  await connection.query(
    `INSERT INTO users (id, store_id, name, email, password_hash, role, is_active)
     VALUES (?, ?, ?, ?, ?, 'admin', 1)`,
    [userId, storeId, adminName, adminEmail, passwordHash]
  );

  console.log(`Created admin user ${adminEmail} for store "${storeName}".`);
  console.log('You can now log in from Flutter with this email/password.');

  await connection.end();
}

main().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});
