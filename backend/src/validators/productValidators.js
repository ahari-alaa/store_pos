const Joi = require('joi');

const createProduct = Joi.object({
  id: Joi.string().uuid().optional(), // client may pre-generate for offline create
  name: Joi.string().min(1).max(200).required(),
  barcode: Joi.string().max(64).allow(null, ''),
  sku: Joi.string().max(64).allow(null, ''),
  category: Joi.string().max(100).allow(null, ''),
  image_url: Joi.string().max(500).allow(null, ''),
  price: Joi.number().min(0).precision(2).required(),
  cost: Joi.number().min(0).precision(2).default(0),
  stock_quantity: Joi.number().integer().min(0).default(0),
  tax_rate: Joi.number().min(0).max(1).default(0),
  is_active: Joi.boolean().default(true),
});

const updateProduct = createProduct.fork(['name', 'price'], (s) => s.optional());

const listProducts = Joi.object({
  search: Joi.string().max(200).allow('', null),
  category: Joi.string().max(100).allow('', null),
  is_active: Joi.boolean().optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(200).default(50),
  updated_since: Joi.string().isoDate().optional(), // for incremental offline sync pulls
});

module.exports = { createProduct, updateProduct, listProducts };
