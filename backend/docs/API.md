# Store POS — API Reference

Base URL: `http(s)://<host>:<port>/api`

All responses share one envelope:

```json
{ "success": true, "data": { } }
```
```json
{ "success": false, "error": { "code": "VALIDATION_ERROR", "message": "..." } }
```

Authenticated routes require:
```
Authorization: Bearer <access_token>
```

---

## Auth

### POST /api/auth/login
Rate-limited (default 10 attempts / 15 minutes per IP).

Request:
```json
{ "email": "admin@example.com", "password": "ChangeMe123!" }
```
Response `200`:
```json
{
  "success": true,
  "data": {
    "user": { "id": "...", "store_id": "...", "name": "...", "email": "...", "role": "admin", "is_active": true },
    "access_token": "eyJ...",
    "refresh_token": "eyJ...",
    "expires_in": "12h"
  }
}
```
Errors: `401 INVALID_CREDENTIALS`, `403 USER_INACTIVE`, `429 TOO_MANY_ATTEMPTS`.

### POST /api/auth/login-pin
The Flutter POS app's login screen — cashier PIN login. Rate-limited
separately from `/login` (default 8 attempts / 15 minutes per IP, see
`PIN_LOGIN_RATE_LIMIT_*` in `.env`).

Only the PIN is sent. There is no user/email field — the backend finds
whichever user (any role) that PIN belongs to. See
`src/services/authService.js#loginWithPin` for how the PIN is looked up
without ever storing it, or a reversible hash of it, in the database.

Request:
```json
{ "pin": "1234" }
```
Response `200`: identical shape to `/login`.

Errors: `401 INVALID_PIN` ("Incorrect PIN" — returned both when no user
holds that PIN and never distinguishes that from a wrong PIN), `403
USER_INACTIVE`, `429 TOO_MANY_ATTEMPTS`.

### POST /api/auth/logout
Auth required. Stateless (deletes token client-side); returns `200`.

### GET /api/auth/me
Auth required. Returns the current user.

### POST /api/auth/users
Auth required, **admin only**. Creates a manager/cashier/admin account for the caller's store.
```json
{ "name": "Jane Cashier", "email": "jane@example.com", "password": "at-least-8-chars", "role": "cashier" }
```
Errors: `409 EMAIL_TAKEN`, `403 ROLE_NOT_ALLOWED`.

### PUT /api/auth/users/:id/pin
Auth required, **admin only**. Assigns/changes a staff member's PIN
(Users → *name* → Change PIN). Works for any role — an admin can also set
their own PIN this way.
```json
{ "pin": "1234" }
```
`pin` must be 4–6 digits. The response never includes the PIN or its
hash — only the same public user shape `/me` returns.

Errors: `404 USER_NOT_FOUND`, `409 PIN_TAKEN` ("This PIN is already in
use" — never reveals which other account holds it), `422
VALIDATION_ERROR`.

---

## Products

All routes auth required.

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/api/products` | any role | `?search=&category=&is_active=&page=&page_size=&updated_since=` (ISO date, for incremental sync pulls) |
| GET | `/api/products/:id` | any role | |
| POST | `/api/products` | `products.manage` (admin, manager) | `id` optional — pass it to preserve an offline-generated UUID |
| PUT | `/api/products/:id` | `products.manage` | partial update |
| DELETE | `/api/products/:id` | `products.manage` | soft delete (`is_active = 0`) |

Create/update body:
```json
{
  "name": "Bottled Water 500ml",
  "barcode": "6111234567890",
  "sku": "WTR-500",
  "category": "Drinks",
  "price": 5.00,
  "cost": 3.00,
  "stock_quantity": 100,
  "tax_rate": 0.10,
  "is_active": true
}
```

---

## Sales

| Method | Path | Permission |
|---|---|---|
| GET | `/api/sales` | any role (cashiers see only their own) |
| GET | `/api/sales/:id` | any role (cashiers only their own) |
| POST | `/api/sales` | `sales.create` |
| POST | `/api/sales/:id/serve` | `sales.serve` (cashier) |
| POST | `/api/sales/:id/reprint` | `sales.serve` (cashier) |

Every sale row (list, detail, admin views) now also carries the serving
metadata added by migration 012: `served_at`, `served_by`, `served_by_name`,
`receipt_printed_at`, `receipt_printed_by(_name)`, `receipt_print_count`.
`served_at = null` means "à servir". **Serving never affects revenue, sale
counts, product statistics, payments or any admin report.**

### POST /api/sales/:id/serve
"IMPRIMER / SERVIR" — marks the cashier's own order as served. Body is
optional and may only contain `{ "client_operation_id": "<uuid>" }`; the
cashier is `req.user` and the timestamp is the server's — neither can be sent.

`200 { sale, already_applied }`. Rules:
- only the sale's own cashier may serve it (`403 ROLE_NOT_ALLOWED` otherwise);
- only `COMPLETED` sales (`409 SALE_NOT_SERVABLE`);
- atomic (`UPDATE … WHERE served_at IS NULL`): a second/concurrent serve gets
  `409 SALE_ALREADY_SERVED` ("Cette commande a déjà été servie.") and
  `served_at` is never rewritten;
- serving does not change `payment_status` (an unpaid order stays unpaid);
- idempotent retry: repeating the same `client_operation_id` for the same sale
  returns `200` with `already_applied: true` and records nothing new (the id
  is stored in `sync_operations` as `sale_served`); reusing it for another
  operation is `409 OPERATION_ID_REUSED`.

### POST /api/sales/:id/reprint
"RÉIMPRIMER" — records that an already served order's receipt was printed
again (`receipt_printed_at/by`, `receipt_print_count`). `served_at`/`served_by`
are not touched. `409 SALE_NOT_SERVED` if the order was never served.

### POST /api/sales
Creates a sale, its line items, its payment(s), and deducts stock — all in one
database transaction. **Idempotent** on `client_operation_id`: retrying the
same request (e.g. after a timeout) returns the original sale instead of
creating a duplicate.

```json
{
  "client_operation_id": "6f1a1a1a-....-uuid",
  "items": [
    { "product_id": "prod-uuid", "quantity": 2, "unit_price": 5.00 }
  ],
  "payments": [
    { "amount": 10.00, "payment_method": "CASH" }
  ],
  "discount_total": 0,
  "tax_total": 0,
  "note": "optional",
  "occurred_at": "2026-09-09T10:15:00Z"
}
```
Response `201` (new) or `200` (duplicate replay):
```json
{ "success": true, "data": { "sale": { "...": "..." }, "was_duplicate": false } }
```
Errors: `400 INVALID_PRODUCT`, `400 INACTIVE_PRODUCT`, `400 INSUFFICIENT_PAYMENT`,
`409 INSUFFICIENT_STOCK`.

---

## Payments

| Method | Path | Permission |
|---|---|---|
| POST | `/api/payments` | `payments.create` |

Adds a payment to an existing sale (e.g. completing a partially-paid sale).
Idempotent per `(sale_id, client_operation_id)`.
```json
{
  "client_operation_id": "uuid",
  "sale_id": "uuid",
  "amount": 5.00,
  "payment_method": "CASH"
}
```

---

## Expenses

| Method | Path | Permission |
|---|---|---|
| GET | `/api/expenses` | `expenses.manage` (admin, manager) |
| POST | `/api/expenses` | `expenses.manage` |
| PUT | `/api/expenses/:id` | `expenses.manage` |
| DELETE | `/api/expenses/:id` | `expenses.manage` |

```json
{
  "client_operation_id": "uuid",
  "amount": 45.00,
  "category": "Utilities",
  "description": "Electricity bill",
  "occurred_at": "2026-09-09T09:00:00Z"
}
```

---

## Inventory

| Method | Path | Permission |
|---|---|---|
| GET | `/api/inventory` | `inventory.manage` |
| GET | `/api/inventory/:productId/movements` | `inventory.manage` |
| POST | `/api/inventory/adjust` | `inventory.manage` |

```json
{
  "client_operation_id": "uuid",
  "product_id": "uuid",
  "quantity_delta": 50,
  "movement_type": "PURCHASE",
  "note": "Weekly restock"
}
```
`movement_type`: `PURCHASE | SALE | RETURN | ADJUSTMENT | DAMAGE | TRANSFER`
(`SALE` movements are created automatically by `POST /api/sales` — you
generally only call this endpoint for the others.)

---

## Sync

| Method | Path |
|---|---|
| POST | `/api/sync` |
| GET | `/api/sync/status` |

### POST /api/sync
Pushes a batch of queued offline operations from the Flutter `sync_queue`
table. Each operation is applied idempotently and independently — one
failure does not block the rest of the batch.

```json
{
  "operations": [
    {
      "operation_id": "uuid (from the local sync_queue row)",
      "entity_type": "sale",
      "entity_id": "uuid (local id)",
      "operation_type": "create",
      "client_created_at": "2026-09-09T08:00:00Z",
      "payload": { "...": "same shape as POST /api/sales body" }
    }
  ]
}
```
`entity_type`: `sale | expense | inventory_adjustment`.

Response:
```json
{
  "success": true,
  "data": {
    "results": [
      { "operation_id": "uuid", "status": "applied", "entity_id": "uuid" }
    ],
    "summary": { "applied": 1, "duplicate": 0, "failed": 0 }
  }
}
```
`status` is one of `applied | duplicate | failed`. A `failed` entry includes
an `error` string — the client should leave that queue row in place and
retry it later (with backoff), never delete it silently.

### GET /api/sync/status
Returns a rollup of operations the server has seen for this store in the
last 24 hours — useful for a diagnostics screen, not a substitute for the
client's own pending-count (which lives in its local `sync_queue`).

---

## Reports

All require `reports.view` (admin, manager).

| Method | Path | Query params |
|---|---|---|
| GET | `/api/reports/sales` | `from`, `to` (ISO dates) |
| GET | `/api/reports/top-products` | `from`, `to`, `limit` |
| GET | `/api/reports/expenses` | `from`, `to` |
| GET | `/api/reports/low-stock` | `threshold` (default 5) |
| GET | `/api/reports/overview` | `period` (`today`, `yesterday`, `week`, `last_week`, `month`, `last_month`, `custom`), `from`/`to` (required for `custom`), `include_sales` (bool), `recent_limit` (1-50) |
| GET | `/api/reports/orders-by-hour` | `period`, `from`/`to` |

### GET /api/reports/overview
One consistent payload for the Rapports screen, PDF, Excel and Print. All
sections are computed from one read-only snapshot for the same period.
Counting rules: a sale is a `COMPLETED` sale whose `occurred_at` is in the
period; revenue is `SUM(sales.total)`; `payments.total_collected +
payments.outstanding = kpis.revenue`; change handed back is deducted from
cash. Timestamps are naive local `YYYY-MM-DD HH:mm:ss`. `integrity.ok` is
`false` if sections fail to add up. `include_sales=true` also returns the
period's sales (max 5000, `sales_truncated` tells if cut).

### GET /api/reports/orders-by-hour
`{ period, scope, hours: [{ hour, label, orders, revenue }] (24 rows), total: { orders, revenue } }`
grouped by `HOUR(occurred_at)`, cumulative over the period.

### Cashier personal report (cashier role only)

Always computed for the authenticated cashier (`req.user.id`). There is no
`cashier_id` parameter — a client-sent `cashier_id`/`user_id` is discarded.
Admin and manager get `403` here (they use `/reports/overview`). Counting rules
are the admin report's (COMPLETED sales, revenue = `SUM(total)`, by `occurred_at`).

#### GET /api/reports/my-sales  (`reports.view_own`)
Query: `period` = `today|yesterday|week|last_week|month|last_month|custom`
(default `today`), `from`/`to` (required for `custom`), `include_orders=true`
(adds the period's full order list, for the printed report).

`{ generated_at, cashier:{id,name}, period, store, kpis:{ revenue, order_count,
items_sold, average_ticket, collected, outstanding }, payments:{ methods[],
total_collected, change_given, outstanding, unpaid, partial }, serving:{
to_serve_total (whole backlog, any date), served_in_period }, products:[{
product_id, name, quantity, revenue }] (THIS cashier's quantities only),
orders|null, orders_truncated, integrity }` — one read snapshot.

#### GET /api/reports/my-orders  (`sales.view_own`)
Query: `serve_status=all|to_serve|served`, `payment_status=PENDING|PARTIALLY_PAID|PAID|UNPAID`
(`UNPAID` = pending + partial), `search` (receipt-number prefix), optional
`period`/`from`/`to` (omit = no date bound; the "À servir" queue uses none),
`page`, `page_size` (≤100).
`{ items:[{ id, receipt_number, occurred_at, total, payment_status, paid_amount,
payment_method, is_served, served_at, served_by_name, receipt_print_count,
items:[{ name, quantity, unit_price, subtotal }] }], total, page, pageSize }`.
`to_serve` is oldest-first (serve in order); the rest newest-first.

---

## Error codes reference

| HTTP | code | Meaning |
|---|---|---|
| 400 | `BAD_REQUEST`, `INVALID_PRODUCT`, `INACTIVE_PRODUCT`, `INSUFFICIENT_PAYMENT` | Malformed or logically invalid request |
| 401 | `NO_TOKEN`, `TOKEN_INVALID`, `TOKEN_EXPIRED`, `INVALID_CREDENTIALS` | Authentication problem |
| 403 | `USER_INACTIVE`, `ROLE_NOT_ALLOWED`, `PERMISSION_DENIED` | Authenticated but not authorized |
| 404 | `NOT_FOUND`, `PRODUCT_NOT_FOUND`, `SALE_NOT_FOUND`, `EXPENSE_NOT_FOUND` | Resource does not exist (or belongs to another store) |
| 409 | `CONFLICT`, `EMAIL_TAKEN`, `PRODUCT_EXISTS`, `INSUFFICIENT_STOCK`, `DUPLICATE_ENTRY`, `SALE_ALREADY_SERVED`, `SALE_NOT_SERVED`, `SALE_NOT_SERVABLE`, `OPERATION_ID_REUSED` | State conflict |
| 422 | `VALIDATION_ERROR` | Body/query failed schema validation — see `error.details` |
| 429 | `TOO_MANY_ATTEMPTS` | Login rate limit hit |
| 500 | `INTERNAL_ERROR` | Unexpected server error |
