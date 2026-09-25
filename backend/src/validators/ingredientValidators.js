const Joi = require('joi');

const createIngredient = Joi.object({
  id: Joi.string().uuid().optional(),
  name: Joi.string().min(1).max(150).required(),
  unit: Joi.string().valid('g', 'kg', 'ml', 'l', 'unit').required(),
  stock_quantity: Joi.number().min(0).precision(3).default(0),
  min_stock: Joi.number().min(0).precision(3).default(0),
  cost_per_unit: Joi.number().min(0).precision(4).default(0),
  is_active: Joi.boolean().default(true),
});

const updateIngredient = Joi.object({
  name: Joi.string().min(1).max(150),
  unit: Joi.string().valid('g', 'kg', 'ml', 'l', 'unit'),
  min_stock: Joi.number().min(0).precision(3),
  cost_per_unit: Joi.number().min(0).precision(4),
  is_active: Joi.boolean(),
}).min(1);

const listIngredients = Joi.object({
  search: Joi.string().max(200).allow('', null),
  is_active: Joi.boolean().optional(),
});

const addMovement = Joi.object({
  quantity_delta: Joi.number().precision(3).invalid(0).required(),
  movement_type: Joi.string().valid('PURCHASE', 'ADJUSTMENT', 'DAMAGE').required(),
  reference_id: Joi.string().uuid().allow(null, ''),
  note: Joi.string().max(300).allow('', null),
});

const recipeLines = Joi.object({
  lines: Joi.array()
    .items(
      Joi.object({
        ingredient_id: Joi.string().uuid().required(),
        quantity: Joi.number().greater(0).precision(3).required(),
        // Unit of THIS recipe line — may differ from the ingredient's
        // storage unit (e.g. recipe in `g`, ingredient stocked in `kg`);
        // omitted = same unit as the ingredient (spec §8).
        unit: Joi.string().valid('g', 'kg', 'ml', 'l', 'unit'),
      })
    )
    .min(0)
    .required(),
});

const addRecipeLine = Joi.object({
  ingredient_id: Joi.string().uuid().required(),
  quantity: Joi.number().greater(0).precision(3).required(),
  unit: Joi.string().valid('g', 'kg', 'ml', 'l', 'unit'),
});

const updateRecipeLine = Joi.object({
  quantity: Joi.number().greater(0).precision(3).required(),
  unit: Joi.string().valid('g', 'kg', 'ml', 'l', 'unit'),
});

module.exports = {
  createIngredient,
  updateIngredient,
  listIngredients,
  addMovement,
  recipeLines,
  addRecipeLine,
  updateRecipeLine,
};
