const express = require('express');
const controller = require('../controllers/syncController');
const validate = require('../middleware/validate');
const { pushSync } = require('../validators/syncValidators');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.use(requireAuth);

// Any authenticated role can sync their own queued offline work — the
// permission check happens per-entity inside syncService's handlers
// (e.g. a cashier's queued expense would still need 'expenses.manage'
// if we later choose to enforce that here too).
router.post('/', validate(pushSync), controller.push);
router.get('/status', controller.status);

module.exports = router;
