const express = require('express');
const controller = require('../controllers/productController');
const recipeController = require('../controllers/recipeController');
const validate = require('../middleware/validate');
const { createProduct, updateProduct, listProducts } = require('../validators/productValidators');
const { recipeLines, addRecipeLine, updateRecipeLine } = require('../validators/ingredientValidators');
const { requireAuth } = require('../middleware/auth');
const { requirePermission } = require('../middleware/authorize');
const { uploadProductImage } = require('../middleware/upload');

const router = express.Router();

router.use(requireAuth);

router.get('/', validate(listProducts, 'query'), controller.list);
router.get('/:id', controller.getById);
router.post('/', requirePermission('products.manage'), validate(createProduct), controller.create);
router.put(
  '/:id',
  requirePermission('products.manage'),
  validate(updateProduct),
  controller.update
);
router.delete('/:id', requirePermission('products.manage'), controller.remove);

// Image upload: existence check first (see controller.ensureProductExists),
// then multer parses the multipart body and writes the file to disk, then
// the controller records the URL on the product row.
router.post(
  '/:id/image',
  requirePermission('products.manage'),
  controller.ensureProductExists,
  uploadProductImage.single('image'),
  controller.uploadImage
);
router.delete('/:id/image', requirePermission('products.manage'), controller.removeImage);

// Recipe / ingredients (Modifier le produit → Ingrédients / Recette tab).
// Recipes/ingredient costs are management data (cashiers only need the
// catalogue endpoints above).
router.get('/:id/ingredients', requirePermission('products.manage'), recipeController.getForProduct);
router.put(
  '/:id/ingredients',
  requirePermission('products.manage'),
  validate(recipeLines),
  recipeController.setForProduct
);
// Single-line add/edit ("+ Add supply" / "Edit recipe supply" dialogs),
// alongside the whole-list PUT above which the legacy editor still uses.
router.post(
  '/:id/ingredients',
  requirePermission('products.manage'),
  validate(addRecipeLine),
  recipeController.addLine
);
router.put(
  '/:id/ingredients/:ingredientId',
  requirePermission('products.manage'),
  validate(updateRecipeLine),
  recipeController.updateLine
);
router.delete(
  '/:id/ingredients/:ingredientId',
  requirePermission('products.manage'),
  recipeController.removeLine
);

module.exports = router;
