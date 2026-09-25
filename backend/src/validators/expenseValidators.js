const Joi = require('joi');

const EXPENSE_TYPES = ['APPROVISIONNEMENT', 'CHARGE_FIXE', 'AUTRE'];
const UNITS = ['kg', 'g', 'l', 'ml', 'unit', 'pack', 'box', 'bottle', 'piece'];

// Same "naive local datetime" shape used by the rest of the app (see
// reportValidators.js's localDateTime) — occurred_at is stored and read
// back with no timezone conversion, so an expense dated 05/09/2026 lines
// up with the same calendar day everywhere (spec §24).
const localDateTime = Joi.string().pattern(/^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}:\d{2})?$/);

const createExpense = Joi.object({
  client_operation_id: Joi.string().uuid().required(),

  // Category: either an existing category_id, or a free-text
  // category + expense_type pair (quick entry / backward compatible
  // with the original API).
  category_id: Joi.string().uuid(),
  category: Joi.string().max(100),
  expense_type: Joi.string().valid(...EXPENSE_TYPES),

  description: Joi.string().max(500).allow('', null),

  // Supplies path: quantity + unit + unit_price -> amount is computed
  // server-side (spec §2/§23) and never trusted from the client.
  quantity: Joi.number().positive().precision(3),
  unit: Joi.string().valid(...UNITS),
  unit_price: Joi.number().min(0).precision(2),

  // Fixed-charge / simple path: a plain amount, no quantity breakdown.
  amount: Joi.number().min(0.01).precision(2),

  supplier_id: Joi.string().uuid().allow(null),
  supplier_name: Joi.string().max(200).allow('', null),
  notes: Joi.string().max(1000).allow('', null),

  product_id: Joi.string().uuid().allow(null),
  // Supply/ingredient purchase target — mutually exclusive with
  // product_id (spec §3: a purchase restocks either a finished product
  // or a raw supply, never both, and never creates a second stock
  // system for the same item).
  ingredient_id: Joi.string().uuid().allow(null),
  affects_inventory: Joi.boolean(),

  is_recurring: Joi.boolean(),
  recurring_day: Joi.number().integer().min(1).max(31).allow(null),

  occurred_at: localDateTime.optional(),
})
  .custom((value, helpers) => {
    if (!value.category_id && !value.category) {
      return helpers.message('category or category_id is required');
    }
    if (value.quantity != null && value.unit_price == null) {
      return helpers.message('unit_price is required when quantity is given');
    }
    if (value.unit_price != null && value.quantity == null) {
      return helpers.message('quantity is required when unit_price is given');
    }
    if (value.quantity == null && value.amount == null) {
      return helpers.message('amount is required when quantity/unit_price are not given');
    }
    if (value.product_id && value.ingredient_id) {
      return helpers.message('product_id and ingredient_id are mutually exclusive');
    }
    if (value.affects_inventory && !value.product_id && !value.ingredient_id) {
      return helpers.message('product_id or ingredient_id is required when affects_inventory is true');
    }
    return value;
  }, 'expense cross-field validation');

const updateExpense = Joi.object({
  category_id: Joi.string().uuid().allow(null),
  category: Joi.string().max(100),
  expense_type: Joi.string().valid(...EXPENSE_TYPES),

  description: Joi.string().max(500).allow('', null),

  quantity: Joi.number().positive().precision(3).allow(null),
  unit: Joi.string().valid(...UNITS).allow(null),
  unit_price: Joi.number().min(0).precision(2).allow(null),
  amount: Joi.number().min(0.01).precision(2),

  supplier_id: Joi.string().uuid().allow(null),
  supplier_name: Joi.string().max(200).allow('', null),
  notes: Joi.string().max(1000).allow('', null),

  product_id: Joi.string().uuid().allow(null),
  ingredient_id: Joi.string().uuid().allow(null),
  affects_inventory: Joi.boolean(),

  is_recurring: Joi.boolean(),
  recurring_day: Joi.number().integer().min(1).max(31).allow(null),

  occurred_at: localDateTime.optional(),
}).custom((value, helpers) => {
  if (value.product_id && value.ingredient_id) {
    return helpers.message('product_id and ingredient_id are mutually exclusive');
  }
  if (value.affects_inventory === true && value.product_id === null && value.ingredient_id === null) {
    return helpers.message('product_id or ingredient_id is required when affects_inventory is true');
  }
  return value;
}, 'expense update cross-field validation');

const createCategory = Joi.object({
  name: Joi.string().max(100).required(),
  expense_type: Joi.string()
    .valid(...EXPENSE_TYPES)
    .required(),
});

const updateCategory = Joi.object({
  name: Joi.string().max(100),
  expense_type: Joi.string().valid(...EXPENSE_TYPES),
  is_active: Joi.boolean(),
}).min(1);

const monthlyReportQuery = Joi.object({
  year: Joi.number().integer().min(2000).max(2100).required(),
  month: Joi.number().integer().min(1).max(12).required(),
});

const recurringQuery = Joi.object({
  year: Joi.number().integer().min(2000).max(2100).required(),
  month: Joi.number().integer().min(1).max(12).required(),
});

module.exports = {
  createExpense,
  updateExpense,
  createCategory,
  updateCategory,
  monthlyReportQuery,
  recurringQuery,
  EXPENSE_TYPES,
  UNITS,
};
