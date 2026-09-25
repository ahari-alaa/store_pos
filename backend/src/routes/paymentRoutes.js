const express = require('express');
const controller = require('../controllers/paymentController');
const validate = require('../middleware/validate');
const { addPayment } = require('../validators/saleValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');

const router = express.Router();

router.use(requireAuth);
router.post('/', requirePermission('payments.create'), validate(addPayment), controller.create);

module.exports = router;
