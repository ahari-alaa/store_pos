const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');
const syncRepository = require('../repositories/syncRepository');
const saleService = require('./saleService');
const expenseService = require('./expenseService');
const inventoryService = require('./inventoryService');
const { createSale } = require('../validators/saleValidators');
const { createExpense } = require('../validators/expenseValidators');
const { adjustInventory } = require('../validators/inventoryValidators');
const { hasPermission } = require('../middleware/authorize');

const SCHEMAS_BY_ENTITY = {
  sale: createSale,
  expense: createExpense,
  inventory_adjustment: adjustInventory,
};

const HANDLERS_BY_ENTITY = {
  sale: (storeId, userId, payload) => saleService.createSale(storeId, userId, payload),
  expense: (storeId, userId, payload) => expenseService.create(storeId, userId, payload),
  inventory_adjustment: (storeId, _userId, payload) => inventoryService.adjust(storeId, payload),
};

// Mirrors the permission a route-level check would apply if these entities
// were only ever created online. Enforced here too because the sync queue
// is a second door into the same writes (section 9: the server must
// enforce authorization, not just the Flutter UI that happened to be
// showing at the time the operation was queued).
const PERMISSION_BY_ENTITY = {
  sale: 'sales.create',
  expense: 'expenses.manage',
  inventory_adjustment: 'inventory.manage',
};

/**
 * Applies one queued operation from the Flutter sync_queue.
 *
 * Every outcome is recorded to `sync_operations` keyed by
 * (store_id, operation_id) so a byte-for-byte retry of the same push
 * request — e.g. the phone lost signal right after the server responded —
 * is detected and short-circuited to "duplicate" rather than reprocessed.
 *
 * Failures are caught per-operation and returned as part of the batch
 * result instead of aborting the whole push, so nine good operations
 * aren't held hostage by one bad one (section 17: "keep in queue and show
 * an error", not "silently delete" or "block everything").
 */
async function applyOperation(storeId, user, operation) {
  const userId = user.id;
  const alreadySeen = await syncRepository.findByOperationId(null, storeId, operation.operation_id);
  if (alreadySeen) {
    return {
      operation_id: operation.operation_id,
      status: 'duplicate',
      entity_id: alreadySeen.entity_id,
    };
  }

  const requiredPermission = PERMISSION_BY_ENTITY[operation.entity_type];
  if (requiredPermission && !hasPermission(user.role, requiredPermission)) {
    await syncRepository.record(null, {
      id: uuidv4(),
      operationId: operation.operation_id,
      storeId,
      userId,
      entityType: operation.entity_type,
      entityId: operation.entity_id,
      operationType: operation.operation_type,
      status: 'failed',
      errorMessage: `Role '${user.role}' cannot perform '${operation.entity_type}' operations`,
    });
    return {
      operation_id: operation.operation_id,
      status: 'failed',
      error: 'PERMISSION_DENIED',
    };
  }

  const schema = SCHEMAS_BY_ENTITY[operation.entity_type];
  const handler = HANDLERS_BY_ENTITY[operation.entity_type];
  if (!schema || !handler) {
    await syncRepository.record(null, {
      id: uuidv4(),
      operationId: operation.operation_id,
      storeId,
      userId,
      entityType: operation.entity_type,
      entityId: operation.entity_id,
      operationType: operation.operation_type,
      status: 'failed',
      errorMessage: `Unsupported entity_type: ${operation.entity_type}`,
    });
    return {
      operation_id: operation.operation_id,
      status: 'failed',
      error: `Unsupported entity_type: ${operation.entity_type}`,
    };
  }

  const { error: validationError, value } = schema.validate(operation.payload, {
    abortEarly: false,
    stripUnknown: true,
  });
  if (validationError) {
    const message = validationError.details.map((d) => d.message).join('; ');
    await syncRepository.record(null, {
      id: uuidv4(),
      operationId: operation.operation_id,
      storeId,
      userId,
      entityType: operation.entity_type,
      entityId: operation.entity_id,
      operationType: operation.operation_type,
      status: 'failed',
      errorMessage: message,
    });
    return { operation_id: operation.operation_id, status: 'failed', error: message };
  }

  try {
    const result = await handler(storeId, userId, value);
    const wasDuplicate = result && result.wasDuplicate;
    await syncRepository.record(null, {
      id: uuidv4(),
      operationId: operation.operation_id,
      storeId,
      userId,
      entityType: operation.entity_type,
      entityId: operation.entity_id,
      operationType: operation.operation_type,
      status: wasDuplicate ? 'duplicate' : 'applied',
    });
    return {
      operation_id: operation.operation_id,
      status: wasDuplicate ? 'duplicate' : 'applied',
      entity_id: operation.entity_id,
    };
  } catch (err) {
    logger.warn(`sync operation ${operation.operation_id} failed:`, err.message);
    await syncRepository.record(null, {
      id: uuidv4(),
      operationId: operation.operation_id,
      storeId,
      userId,
      entityType: operation.entity_type,
      entityId: operation.entity_id,
      operationType: operation.operation_type,
      status: 'failed',
      errorMessage: err.message,
    });
    return { operation_id: operation.operation_id, status: 'failed', error: err.message };
  }
}

/**
 * Applies operations sequentially (not in parallel) — sales in the same
 * batch may touch the same product's stock, and processing them one at a
 * time keeps behaviour predictable and matches how they were queued
 * on-device (oldest first).
 */
async function pushOperations(storeId, user, operations) {
  const results = [];
  for (const operation of operations) {
    // eslint-disable-next-line no-await-in-loop
    results.push(await applyOperation(storeId, user, operation));
  }

  const summary = results.reduce(
    (acc, r) => {
      acc[r.status] = (acc[r.status] || 0) + 1;
      return acc;
    },
    { applied: 0, duplicate: 0, failed: 0 }
  );

  return { results, summary };
}

async function getStatus(storeId) {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const rows = await syncRepository.pendingCountSince(storeId, since);
  const counts = { applied: 0, duplicate: 0, failed: 0 };
  for (const row of rows) counts[row.status] = row.count;
  return { last_24h: counts, server_time: new Date().toISOString() };
}

module.exports = { pushOperations, getStatus };
