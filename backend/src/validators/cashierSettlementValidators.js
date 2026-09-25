const Joi = require('joi');

// SECURITY (spec §14): no cashier_id field anywhere here. The cashier is
// always req.user.id — validate() strips unknown keys, so a client-sent
// cashier_id/user_id is discarded before it reaches a handler.
const createSettlement = Joi.object({
  sale_ids: Joi.array().items(Joi.string().uuid()).min(1).max(1000).required(),
});

const settlementIdParam = Joi.object({ id: Joi.string().uuid().required() });

const mySettlementsQuery = Joi.object({
  status: Joi.string().valid('PRINTED', 'PAID', 'CANCELLED').optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(100).default(50),
});

const adminSettlementsQuery = Joi.object({
  cashier_id: Joi.string().uuid().optional(),
  status: Joi.string().valid('PRINTED', 'PAID', 'CANCELLED').optional(),
  from: Joi.string()
    .pattern(/^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}:\d{2})?$/)
    .optional(),
  to: Joi.string()
    .pattern(/^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}:\d{2})?$/)
    .optional(),
  page: Joi.number().integer().min(1).default(1),
  page_size: Joi.number().integer().min(1).max(200).default(50),
});

const cancelSettlement = Joi.object({
  reason: Joi.string().max(500).allow('', null).optional(),
});

module.exports = {
  createSettlement,
  settlementIdParam,
  mySettlementsQuery,
  adminSettlementsQuery,
  cancelSettlement,
};
