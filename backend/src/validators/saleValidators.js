const Joi = require('joi');
const { REPORT_PERIODS } = require('./reportValidators');

const saleItem = Joi.object({
  product_id: Joi.string().uuid().required(),
  quantity: Joi.number().integer().min(1).required(),
  unit_price: Joi.number().min(0).precision(2).required(),
});

const payment = Joi.object({
  amount: Joi.number().min(0).precision(2).required(),
  payment_method: Joi.string().valid('CASH', 'CARD', 'TRANSFER', 'MIXED').required(),
});

/**
 * `client_operation_id`: a UUID generated once on the device when the sale
 * is first created offline. It is the idempotency key that lets the sync
 * queue safely retry without ever creating a duplicate sale (section 5/17
 * of the spec). It must be present and unique per logical sale.
 *
 * `payments` may be an EMPTY array: this is what lets the cashier "Give
 * receipt without paying" (Sales spec §2/§3) — a real sale is still
 * created (with its items + stock deduction), just with no payment rows,
 * so saleService.createSale marks it `PENDING` ("NOT PAID") instead of
 * requiring full payment up front.
 */
const createSale = Joi.object({
  client_operation_id: Joi.string().uuid().required(),
  items: Joi.array().items(saleItem).min(1).required(),
  payments: Joi.array().items(payment).min(0).default([]),
  discount_total: Joi.number().min(0).precision(2).default(0),
  tax_total: Joi.number().min(0).precision(2).default(0),
  note: Joi.string().max(500).allow('', null),
  // Allows offline-created timestamps to be preserved for accurate reporting,
  // separate from the row's server-side created_at (when it was synced).
  occurred_at: Joi.string().isoDate().optional(),
});

const listSales = Joi.object({
  from: Joi.string().isoDate().optional(),
  to: Joi.string().isoDate().optional(),
  // Rapports "Transactions récentes" (spec §15) passes a named period
  // instead of computing from/to itself, so it resolves identically to
  // every other Rapports section (see reportService.js#resolveRange).
  // Optional and additive: the Sales screen keeps sending from/to
  // directly and never sets this.
  period: Joi.string().valid(...REPORT_PERIODS).optional(),
  user_id: Joi.string().uuid().optional(),
  // Sales-screen search/filter (spec §15/§16): free-text match against the
  // receipt number (sale id), cashier name, or note; and an exact filter
  // on payment_status ("All" = omit this param).
  search: Joi.string().max(190).allow('', null).optional(),
  payment_status: Joi.string().valid('PENDING', 'PARTIALLY_PAID', 'PAID', 'REFUNDED').optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(200).default(50),
});

const addPayment = Joi.object({
  client_operation_id: Joi.string().uuid().required(),
  sale_id: Joi.string().uuid().required(),
  amount: Joi.number().min(0.01).precision(2).required(),
  payment_method: Joi.string().valid('CASH', 'CARD', 'TRANSFER').required(),
});

// POST /sales/:id/serve — the body is optional and can ONLY carry the
// idempotency key. No cashier id / timestamp is accepted from the client:
// the server uses req.user.id and its own clock.
const serveSale = Joi.object({
  client_operation_id: Joi.string().uuid().optional(),
});

const saleIdParam = Joi.object({ id: Joi.string().uuid().required() });

module.exports = { createSale, listSales, saleItem, payment, addPayment, serveSale, saleIdParam };
