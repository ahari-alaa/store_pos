const express = require('express');
const controller = require('../controllers/ingredientController');
const validate = require('../middleware/validate');
const {
  createIngredient,
  updateIngredient,
  listIngredients,
  addMovement,
} = require('../validators/ingredientValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

const router = express.Router();

router.use(requireAuth);

// Reuses the existing 'inventory.manage' permission (admin + manager) —
// ingredient stock is just another flavour of inventory.
// Reads need 'inventory.manage' too (admin/manager): ingredient stock and
// usage are management data, not something a cashier may query directly.
router.get(
  '/',
  requirePermission('inventory.manage'),
  validate(listIngredients, 'query'),
  controller.list
);
router.get('/low-stock', requirePermission('inventory.manage'), controller.lowStock);
router.get('/:id', requirePermission('inventory.manage'), controller.getById);
router.post('/', requirePermission('inventory.manage'), validate(createIngredient), controller.create);
router.put(
  '/:id',
  requirePermission('inventory.manage'),
  validate(updateIngredient),
  controller.update
);
router.delete('/:id', requirePermission('inventory.manage'), controller.remove);
router.post('/:id/deactivate', requirePermission('inventory.manage'), controller.deactivate);

router.post(
  '/:id/movements',
  requirePermission('inventory.manage'),
  validate(addMovement),
  controller.addMovement
);
router.get('/:id/movements', requirePermission('inventory.manage'), controller.movements);
router.get('/:id/used-in', requirePermission('inventory.manage'), controller.usedInProducts);

module.exports = router;
