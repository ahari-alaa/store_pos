const Joi = require('joi');

// 4-6 digits, matches the FINAL REQUIREMENT / VALIDATION sections of the
// PIN-login spec. Digits only — never accepted as a number type, since a
// leading zero ("0123") must stay a valid, distinct PIN.
const PIN_PATTERN = /^\d{4,6}$/;
const pinSchema = Joi.string().pattern(PIN_PATTERN).required().messages({
  'string.pattern.base': 'PIN must be 4 to 6 digits',
  'string.empty': 'PIN is required',
});

const login = Joi.object({
  email: Joi.string().email().required(),
  password: Joi.string().min(6).required(),
});

const loginPin = Joi.object({
  pin: pinSchema,
});

const setPin = Joi.object({
  pin: pinSchema,
});

const createUser = Joi.object({
  name: Joi.string().min(2).max(120).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(8).required(),
  role: Joi.string().valid('admin', 'manager', 'cashier').required(),
  // Optional: defaults to the creating admin's own store (see
  // authController.createUser). Only relevant once multi-store admins exist.
  store_id: Joi.string().uuid().optional(),
});

const listUsers = Joi.object({
  search: Joi.string().max(200).allow('', null),
  role: Joi.string().valid('admin', 'manager', 'cashier').optional(),
  is_active: Joi.boolean().optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(200).default(50),
});

const updateUser = Joi.object({
  name: Joi.string().min(2).max(120).optional(),
  email: Joi.string().email().optional(),
  role: Joi.string().valid('admin', 'manager', 'cashier').optional(),
  is_active: Joi.boolean().optional(),
  password: Joi.string().min(8).optional(),
}).min(1);

module.exports = { login, loginPin, setPin, createUser, listUsers, updateUser };
