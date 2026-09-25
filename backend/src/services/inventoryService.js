const { v4: uuidv4 } = require('uuid');
const { withTransaction } = require('../config/db');
const ApiError = require('../utils/ApiError');
const productRepository = require('../repositories/productRepository');
const inventoryRepository = require('../repositories/inventoryRepository');

/**
 * Applies a manual inventory movement (stock received, damage write-off,
 * manual correction, transfer). Sales themselves create their own SALE
 * movements inside saleService — this is for everything else.
 */
async function adjust(storeId, input) {
  const existing = await inventoryRepository.findByClientOperationId(
    storeId,
    input.client_operation_id
  );
  if (existing) {
    return { movement: existing, wasDuplicate: true };
  }

  const movementId = await withTransaction(async (conn) => {
    const product = await productRepository.findByIdForUpdate(conn, storeId, input.product_id);
    if (!product) {
      throw ApiError.badRequest('Product not found in this store', 'INVALID_PRODUCT');
    }

    const success = await productRepository.adjustStock(
      conn,
      storeId,
      input.product_id,
      input.quantity_delta
    );
    if (!success) {
      throw ApiError.conflict(
        `Adjustment would make stock negative for "${product.name}"`,
        'INSUFFICIENT_STOCK'
      );
    }

    const id = uuidv4();
    await inventoryRepository.insertMovement(conn, storeId, {
      id,
      productId: input.product_id,
      clientOperationId: input.client_operation_id,
      quantityDelta: input.quantity_delta,
      movementType: input.movement_type,
      referenceId: input.reference_id,
      note: input.note,
    });
    return id;
  });

  const movements = await inventoryRepository.listForProduct(storeId, input.product_id, {
    page: 1,
    pageSize: 1,
  });
  return { movement: movements.find((m) => m.id === movementId) || movements[0], wasDuplicate: false };
}

async function listForProduct(storeId, productId, query) {
  return inventoryRepository.listForProduct(storeId, productId, {
    page: query.page || 1,
    pageSize: query.page_size || 50,
  });
}

async function listForStore(storeId, query) {
  return inventoryRepository.listForStore(storeId, {
    page: query.page || 1,
    pageSize: query.page_size || 50,
  });
}

module.exports = { adjust, listForProduct, listForStore };
