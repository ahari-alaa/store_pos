const Joi = require('joi');

const createSupplier = Joi.object({
  id: Joi.string().uuid().optional(),
  name: Joi.string().min(1).max(200).required(),
  contact_name: Joi.string().max(150).allow(null, ''),
  phone: Joi.string().max(40).allow(null, ''),
  email: Joi.string().email().max(190).allow(null, ''),
  address: Joi.string().max(300).allow(null, ''),
  notes: Joi.string().max(500).allow(null, ''),
  is_active: Joi.boolean().default(true),
});

const updateSupplier = createSupplier.fork(['name'], (s) => s.optional());

const listSuppliers = Joi.object({
  search: Joi.string().max(200).allow('', null),
  is_active: Joi.boolean().optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(200).default(50),
});

module.exports = { createSupplier, updateSupplier, listSuppliers };
