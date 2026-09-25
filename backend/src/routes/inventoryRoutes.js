const express = require('express');
const controller = require('../controllers/inventoryController');
const validate = require('../middleware/validate');
const { adjustInventory } = require('../validators/inventoryValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

const router = express.Router();

router.use(requireAuth, requirePermission('inventory.manage'));

router.get('/', controller.list);
router.get('/:productId/movements', controller.listForProduct);
router.post('/adjust', validate(adjustInventory), controller.adjust);

module.exports = router;
