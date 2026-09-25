# Store POS — Flutter app wired to `store_pos_backend`

Flutter + Riverpod, Clean Architecture, feature-based folders. This app
now talks to the real Node/Express + MySQL backend (`store_pos_backend`)
instead of in-memory mock data: login, product listing, and completing a
sale all go over HTTP.

## What changed from the mock milestone

- **Auth**: a real login screen (`features/auth`) calling
  `POST /api/auth/login`, storing the JWT in secure storage, restoring the
  session on app restart, and redirecting to `/login` automatically if a
  token expires or is rejected.
- **Products**: `features/pos/data/datasources/products_api.dart` fetches
  `GET /api/products` (paginated) instead of reading
  `MockPosDatasource` (deleted). Categories are derived client-side from
  the distinct `category` values on the returned products, since the
  backend doesn't expose a separate categories endpoint in this
  milestone.
- **Sales**: "Complete Sale" now posts to `POST /api/sales` with a
  client-generated idempotency key (`client_operation_id`), the cart line
  items, and the payment split. The backend validates stock, deducts it
  atomically, and returns the created sale; the cart only clears after
  that succeeds. Network/validation errors show as a snackbar instead of
  silently "completing".
- Field names on `Product` now mirror the backend/DB columns exactly
  (`price`, `cost`, `category`, `stock_quantity`, `tax_rate`) instead of
  the old mock-only names (`sellingPrice`, `purchasePrice`, `categoryId`).

## Project structure (new/changed pieces only)

```
lib/
  core/
    config/       api_config.dart        backend base URL (dart-define override)
    network/      api_client.dart        thin http wrapper, unwraps {success,data}/{error}
                  api_exception.dart     normalized API error type
                  providers.dart         apiClientProvider (shared by every datasource)
    storage/      token_storage.dart     secure storage for the JWT session
    router/       app_router.dart        now auth-gated: /splash, /login, then the app
    widgets/      splash_page.dart       shown while the session is being restored
  features/
    auth/
      domain/entities/    app_user.dart
      data/                auth_api.dart
      presentation/
        providers/         auth_provider.dart   (AuthNotifier: login/logout/session restore)
        pages/              login_page.dart
    pos/
      data/datasources/    products_api.dart, sales_api.dart   (replaced the mock datasource)
      presentation/providers/  sale_provider.dart  (builds + submits the sale payload)
      ...                      (everything else is the same POS UI as before)
```

## How to run it

### 1. Start the backend

```bash
cd store_pos_backend
cp .env.example .env        # then edit DB_* and JWT_SECRET as needed
npm install
npm run migrate             # runs migrations/001_init.sql
npm run seed:admin          # creates the first admin user from SEED_ADMIN_* in .env
npm start                   # listens on PORT (default 3000)
```

Log in with the email/password from `SEED_ADMIN_EMAIL` /
`SEED_ADMIN_PASSWORD` in your `.env` (defaults to
`admin@example.com` / `ChangeMe123!` unless you changed them).

You'll also want at least one product in the database to see anything in
the POS grid — either insert one directly, or add a "Products" admin
screen later; there's no seed data for products in this milestone.

### 2. Point the Flutter app at the backend

By default the app assumes the backend is running on the **same machine**
as wherever Flutter is running:
- Android emulator → `http://10.0.2.2:3000/api` (emulator's alias for the
  host machine)
- Everything else (iOS simulator, desktop, web) → `http://localhost:3000/api`

To point at a different host (a physical device, a deployed server, a
different port), override at run time — no code changes needed:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000/api
```

### 3. Run the app

```bash
cd store_pos

# If android/ios/web/etc. platform folders aren't present yet:
flutter create . --project-name store_pos --org com.yourcompany

flutter pub get
flutter run -d windows   # or macos / linux / chrome / an Android/iOS device
```

## How to test it

1. App opens on a splash screen, then redirects to **Login** (no session
   yet).
2. Log in with the seeded admin (or any user you've created via
   `POST /api/auth/users`, admin-only).
3. POS screen loads; the product grid fetches from the backend — if it's
   empty, add a product to the `products` table for your store first.
4. Tap products into the cart, set a discount/payment as before.
5. **Complete Sale** now actually calls the backend:
   - On success: confirmation dialog, cart clears, and the product grid
     refetches so updated stock quantities show immediately.
   - On failure (e.g. insufficient stock, network error): a red snackbar
     shows the backend's error message; the cart is **not** cleared.
6. Click the user badge (top-right) → **Log out** → app returns to the
   login screen and the stored token is cleared.
7. Kill and restart the app → it goes straight back to POS without asking
   to log in again (session restored from secure storage), as long as the
   token hasn't expired.

## Known limitations (intentional — out of scope for this pass)

- Only POS is wired to the backend; every other sidebar module (Products,
  Inventory, Sales history, Reports, ...) still shows "Coming soon" even
  though the backend already has working endpoints for several of them
  (`/api/inventory`, `/api/expenses`, `/api/reports`, `/api/sync`) — those
  are natural next screens to wire up the same way `pos` was.
  Products screen in particular would let you add/edit products through
  the UI instead of inserting them directly into the database.
- No offline queue/sync yet (Phase 8/9 in the original plan) — every
  action requires connectivity to the backend right now.
- No barcode hardware or ESC/POS printing yet — the search field is
  scanner-ready (autofocused, plain text input) but there's no
  exact-barcode "instant add" shortcut wired up yet.
- Sidebar doesn't hide modules based on role yet, even though the backend
  already enforces role-based permissions server-side
  (`middleware/authorize.js`) — a cashier who navigates to a
  manager/admin-only "coming soon" page just sees the placeholder, but
  would get a 403 from the API if that page tried to call a
  manager/admin-only endpoint.
