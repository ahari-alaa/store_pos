const express = require('express');
const controller = require('../controllers/saleController');
const validate = require('../middleware/validate');
const { createSale, listSales, serveSale, saleIdParam } = require('../validators/saleValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

const router = express.Router();

router.use(requireAuth);

router.get('/', validate(listSales, 'query'), controller.list);
router.get('/:id', controller.getById);
router.post('/', requirePermission('sales.create'), validate(createSale), controller.create);

// Cashier workflow: print + mark served, and reprint an already-served
// order. Neither deletes or edits the sale — see saleService.serveSale.
router.post(
  '/:id/serve',
  requirePermission('sales.serve'),
  validate(saleIdParam, 'params'),
  validate(serveSale),
  controller.serve
);
router.post(
  '/:id/reprint',
  requirePermission('sales.serve'),
  validate(saleIdParam, 'params'),
  controller.reprint
);

module.exports = router;
