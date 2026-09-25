const { v4: uuidv4 } = require('uuid');
const ApiError = require('../utils/ApiError');
const productRepository = require('../repositories/productRepository');
const { deleteProductImageFile } = require('../middleware/upload');

async function list(storeId, query) {
  return productRepository.list(storeId, {
    search: query.search,
    category: query.category,
    isActive: query.is_active,
    page: query.page,
    pageSize: query.page_size,
    updatedSince: query.updated_since,
  });
}

async function getById(storeId, id) {
  const product = await productRepository.findById(storeId, id);
  if (!product) throw ApiError.notFound('Product not found', 'PRODUCT_NOT_FOUND');
  return product;
}

/** Thin existence/ownership check, exposed for the image-upload route so
 * it can reject a bad product id BEFORE multer starts writing the
 * uploaded file to disk (see routes/productRoutes.js). */
async function assertExists(storeId, id) {
  await getById(storeId, id);
}

async function create(storeId, input) {
  // Allow the client to pre-generate the id (offline-created product),
  // otherwise generate one server-side.
  const id = input.id || uuidv4();
  const existing = await productRepository.findById(storeId, id);
  if (existing) {
    throw ApiError.conflict('A product with this id already exists', 'PRODUCT_EXISTS');
  }
  return productRepository.create(storeId, { ...input, id });
}

async function update(storeId, id, input) {
  const updated = await productRepository.update(storeId, id, input);
  if (!updated) throw ApiError.notFound('Product not found', 'PRODUCT_NOT_FOUND');
  return updated;
}

// MySQL's FK error code when a DELETE is blocked by ON DELETE RESTRICT
// (see fk_sale_items_product in migrations/001_init.sql).
const ER_ROW_IS_REFERENCED_2 = 1451;

/**
 * Deletes a product outright, including its uploaded image file, so
 * nothing is left orphaned on disk or lingering in the products table.
 *
 * If the product has ever been sold, the DB refuses the hard delete
 * (sale_items.product_id -> products.id is ON DELETE RESTRICT, to protect
 * historical sales/reporting from pointing at a vanished product) — in
 * that case this falls back to the existing soft-delete (deactivate)
 * behavior instead of failing the request, and reports which one
 * happened so the caller can show the right message.
 */
async function remove(storeId, id) {
  const existing = await getById(storeId, id);

  try {
    await productRepository.hardDelete(storeId, id);
  } catch (error) {
    if (error && error.errno === ER_ROW_IS_REFERENCED_2) {
      await productRepository.softDelete(storeId, id);
      return { id, deleted: false, deactivated: true };
    }
    throw error;
  }

  if (existing.image_url) deleteProductImageFile(existing.image_url);
  return { id, deleted: true, deactivated: false };
}

/**
 * Points a product at a newly-uploaded image and deletes whichever image
 * file it previously pointed to (if any), so replacing a photo doesn't
 * leave the old one orphaned on disk.
 */
async function setImage(storeId, id, imageUrl) {
  const existing = await getById(storeId, id);
  const updated = await productRepository.update(storeId, id, { image_url: imageUrl });
  if (existing.image_url && existing.image_url !== imageUrl) {
    deleteProductImageFile(existing.image_url);
  }
  return updated;
}

async function removeImage(storeId, id) {
  const existing = await getById(storeId, id);
  const updated = await productRepository.update(storeId, id, { image_url: null });
  if (existing.image_url) deleteProductImageFile(existing.image_url);
  return updated;
}

module.exports = { list, getById, create, update, remove, setImage, removeImage, assertExists };
