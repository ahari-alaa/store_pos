const Joi = require('joi');

const adjustInventory = Joi.object({
  client_operation_id: Joi.string().uuid().required(),
  product_id: Joi.string().uuid().required(),
  quantity_delta: Joi.number().integer().not(0).required(), // +received / -damaged etc.
  movement_type: Joi.string()
    .valid('PURCHASE', 'SALE', 'RETURN', 'ADJUSTMENT', 'DAMAGE', 'TRANSFER')
    .required(),
  reference_id: Joi.string().uuid().allow(null),
  note: Joi.string().max(300).allow('', null),
});

module.exports = { adjustInventory };
