# Store POS — Backend (Node.js + Express + MySQL)

REST API for the Store POS Flutter app. Replaces the previous Supabase
design with a self-hosted Node.js/Express/MySQL stack: JWT authentication,
role-based authorization, and an idempotent sync endpoint for the app's
offline-first SQLite queue.

See [`docs/API.md`](docs/API.md) for the full endpoint reference.

## Requirements

- Node.js 18+ and npm
- MySQL 8.0+ (or MariaDB 10.6+)

## 1. Install Node.js and MySQL (Windows)

1. Download and install Node.js LTS from https://nodejs.org — this also installs npm.
2. Download and install MySQL Community Server from https://dev.mysql.com/downloads/installer/
   (choose the "Server only" or "Developer Default" setup; remember the root password you set).
3. Open **MySQL Workbench** or the **MySQL Command Line Client** to run the database setup below.

## 2. Create the database and an app user

In a MySQL client (Workbench, `mysql` CLI, etc.):

```sql
CREATE DATABASE store_pos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'store_pos_app'@'%' IDENTIFIED BY 'change_me';
GRANT ALL PRIVILEGES ON store_pos.* TO 'store_pos_app'@'%';
FLUSH PRIVILEGES;
```

## 3. Configure the backend

```bash
cd backend
copy .env.example .env
```
(`cp .env.example .env` on macOS/Linux)

Edit `.env` and set at minimum:
- `DB_USER`, `DB_PASSWORD`, `DB_NAME` — match what you created above
- `JWT_SECRET` — a long random string (e.g. generate one with `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"`)
- `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` — the first login you'll use from Flutter

**Never commit `.env` to git** — it's already in `.gitignore`.

## 4. Install dependencies, migrate, seed

```bash
cd backend
npm install
npm run migrate       # creates all tables (safe to re-run - skips what's already applied)
npm run seed:admin    # creates your first store + admin user
```

## 5. Run the server

```bash
npm run dev     # nodemon, auto-restarts on file changes (development)
npm start       # plain node (production)
```

The API is now available at `http://localhost:3000/api` (or whatever `PORT`
you set). Check it's alive:

```bash
curl http://localhost:3000/api/health
```

Point the Flutter app's `API_BASE_URL` at this address — use your machine's
LAN IP (e.g. `http://192.168.1.20:3000/api`), not `localhost`, if testing
on a physical phone or a different machine on the network.

## 6. Run the tests

```bash
npm test
```

Tests are unit-level (Jest) and mock the database layer entirely - they run
without a real MySQL connection and check the logic that matters most:
authentication (correct/incorrect password, deactivated user, no user
enumeration), sale creation (idempotency, oversell protection, transactional
writes), and the sync engine (duplicate detection, per-role permission
enforcement, partial-batch failure isolation).

## Project structure

```
backend/
├── src/
│   ├── config/        # env loading, MySQL pool + transaction helper
│   ├── controllers/    # thin HTTP handlers -> call services
│   ├── middleware/      # auth (JWT), authorize (RBAC), validate, errors, rate limit
│   ├── models/          # (reserved - repositories currently hold all SQL)
│   ├── repositories/    # parameterized SQL, always scoped by store_id
│   ├── routes/          # Express routers, one per resource
│   ├── services/        # business logic, transactions, idempotency
│   ├── validators/      # Joi schemas
│   └── server.js
├── migrations/          # plain .sql files, applied in order by scripts/migrate.js
├── scripts/             # migrate.js, seedAdmin.js
├── tests/               # Jest unit tests
├── docs/API.md
├── .env.example
└── package.json
```

## Security notes

- Passwords are hashed with bcrypt (`BCRYPT_SALT_ROUNDS`, default 12) - never
  stored or logged in plaintext.
- JWTs carry only `user_id` (`sub`), `store_id`, and `role` - no sensitive data.
- Every data-access query is scoped by `store_id` taken from the verified JWT,
  never from client-supplied input, so one store can't read or write another's data.
- Login is rate-limited (`LOGIN_RATE_LIMIT_*` env vars).
- `helmet()` sets standard security headers; configure `CORS_ORIGIN` for production.
- Put this server behind HTTPS (a reverse proxy like nginx/Caddy with a TLS
  certificate, or your cloud provider's load balancer) before exposing it
  to the internet - the app itself speaks plain HTTP.
- MySQL is never exposed directly to Flutter or to the internet - only this
  API talks to it.

## Deploying

Any host that can run Node.js + MySQL works (a small VPS, a managed Node
host with a managed MySQL instance, etc.). Minimum production checklist:

1. Set `NODE_ENV=production`.
2. Put a real TLS certificate in front of the app (nginx/Caddy reverse proxy, or your platform's built-in HTTPS).
3. Set a strong, unique `JWT_SECRET`/`JWT_REFRESH_SECRET` and `DB_PASSWORD`.
4. Restrict `CORS_ORIGIN` to the actual origins that need it (Flutter mobile apps don't send an Origin header, so this mainly matters if you build a web dashboard later).
5. Take regular MySQL backups (`mysqldump` on a schedule, or your host's managed backup feature).
6. Run `npm run migrate` as part of your deploy step, before starting the new server process.
