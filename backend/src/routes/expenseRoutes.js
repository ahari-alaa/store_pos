const express = require('express');
const controller = require('../controllers/expenseController');
const validate = require('../middleware/validate');
const {
  createExpense,
  updateExpense,
  createCategory,
  updateCategory,
  monthlyReportQuery,
  recurringQuery,
} = require('../validators/expenseValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');
const { uploadExpenseReceipt } = require('../middleware/upload');
const asyncHandler = require('../utils/asyncHandler');
const ApiError = require('../utils/ApiError');
const expenseService = require('../services/expenseService');

const router = express.Router();

router.use(requireAuth, requirePermission('expenses.manage'));

// Static/nested paths must come BEFORE '/:id' below, or Express would
// swallow e.g. 'categories' or 'report' as an :id.
router.get('/categories', controller.listCategories);
router.post('/categories', validate(createCategory), controller.createCategory);
router.put('/categories/:id', validate(updateCategory), controller.updateCategory);
router.delete('/categories/:id', controller.deactivateCategory);

router.get('/report/monthly', validate(monthlyReportQuery, 'query'), controller.monthlyReport);
router.get(
  '/recurring-suggestions',
  validate(recurringQuery, 'query'),
  controller.recurringSuggestions
);

router.get('/feed', controller.feed);
router.get('/', controller.list);
router.get('/:id', controller.getOne);
router.post('/', validate(createExpense), controller.create);
router.put('/:id', validate(updateExpense), controller.update);
router.delete('/:id', controller.remove);

router.post(
  '/:id/receipt',
  // Existence check runs BEFORE multer parses the multipart body, so a
  // bad/foreign expense id never gets a receipt file written to disk
  // for nothing (mirrors productRoutes' image upload guard).
  asyncHandler(async (req, res, next) => {
    await expenseService.getById(req.user.storeId, req.params.id);
    next();
  }),
  uploadExpenseReceipt.single('receipt'),
  controller.uploadReceipt
);
router.delete('/:id/receipt', controller.removeReceipt);

module.exports = router;
