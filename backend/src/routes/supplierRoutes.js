const express = require('express');
const controller = require('../controllers/supplierController');
const validate = require('../middleware/validate');
const { createSupplier, updateSupplier, listSuppliers } = require('../validators/supplierValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

const router = express.Router();

router.use(requireAuth);

// Suppliers are management data: reads need the same permission as writes
// (admin/manager). A cashier has no supplier screen and must not be able to
// list suppliers by calling the endpoint directly.
router.get(
  '/',
  requirePermission('suppliers.manage'),
  validate(listSuppliers, 'query'),
  controller.list
);
router.get('/:id', requirePermission('suppliers.manage'), controller.getById);
router.post('/', requirePermission('suppliers.manage'), validate(createSupplier), controller.create);
router.put(
  '/:id',
  requirePermission('suppliers.manage'),
  validate(updateSupplier),
  controller.update
);
router.delete('/:id', requirePermission('suppliers.manage'), controller.remove);

module.exports = router;
