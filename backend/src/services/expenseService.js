const { v4: uuidv4 } = require('uuid');
const ApiError = require('../utils/ApiError');
const { withTransaction } = require('../config/db');
const expenseRepository = require('../repositories/expenseRepository');
const expenseCategoryRepository = require('../repositories/expenseCategoryRepository');
const inventoryRepository = require('../repositories/inventoryRepository');
const productRepository = require('../repositories/productRepository');
const supplierRepository = require('../repositories/supplierRepository');
const ingredientRepository = require('../repositories/ingredientRepository');
const ingredientMovementRepository = require('../repositories/ingredientMovementRepository');
const { deleteExpenseReceiptFile } = require('../middleware/upload');

// ---------------------------------------------------------------------
// Money helpers (spec §23: exact decimal calculations, never floats).
// mysql2 returns DECIMAL columns as strings (decimalNumbers: false in
// config/db.js) specifically to avoid this class of bug — these helpers
// keep that guarantee through the multiplication step too, instead of
// doing `quantity * unitPrice` as a plain JS float multiply.
// ---------------------------------------------------------------------

/** quantity (up to 3 decimals) × unitPrice (up to 2 decimals) -> "X.XX" */
function computeTotal(quantity, unitPrice) {
  const qMilli = Math.round(Number(quantity) * 1000); // e.g. 15.000 kg -> 15000
  const pCenti = Math.round(Number(unitPrice) * 100); // e.g. 85.00 DH -> 8500
  const totalCents = Math.round((qMilli * pCenti) / 1000);
  return (totalCents / 100).toFixed(2);
}

function monthRange(year, month) {
  const start = new Date(Date.UTC(year, month - 1, 1, 0, 0, 0));
  const endExclusive = new Date(Date.UTC(year, month, 1, 0, 0, 0));
  const endInclusive = new Date(endExclusive.getTime() - 1000);
  return { start, endInclusive, endExclusive };
}

/**
 * Resolves the category for a create/update: prefer an existing
 * `category_id` (the configurable-categories path), falling back to a
 * free-text `category` + `expense_type` pair for quick entry / backward
 * compatibility with the original API shape.
 */
async function resolveCategory(storeId, input) {
  if (input.category_id) {
    const category = await expenseCategoryRepository.findById(storeId, input.category_id);
    if (!category) throw ApiError.badRequest('Category not found', 'INVALID_CATEGORY');
    return { categoryId: category.id, categoryName: category.name, expenseType: category.expense_type };
  }
  if (!input.category) {
    throw ApiError.badRequest('category or category_id is required', 'CATEGORY_REQUIRED');
  }
  // expense_type defaults to 'AUTRE' (matching the column default) when
  // omitted — this keeps the original API contract intact for
  // already-deployed clients / offline sync queues that only ever sent
  // { amount, category } (spec §22: must not break existing sync).
  return { categoryId: null, categoryName: input.category, expenseType: input.expense_type || 'AUTRE' };
}

async function resolveSupplier(storeId, supplierId, suppliedName) {
  if (!supplierId) return { supplierId: null, supplierName: suppliedName || null };
  const supplier = await supplierRepository.findById(storeId, supplierId);
  if (!supplier) throw ApiError.badRequest('Supplier not found', 'INVALID_SUPPLIER');
  return { supplierId: supplier.id, supplierName: suppliedName || supplier.name };
}

/** Reverses a previously-recorded PURCHASE inventory movement for this
 * expense, inside the given transaction — used when an edit changes the
 * expense's inventory impact, or when the expense is deleted.
 *
 * Uses `clampedAdjustStock` rather than blindly subtracting the full
 * original purchase quantity: some or all of that purchased stock may
 * already have been sold in the time since the purchase was recorded, so
 * reversing it unconditionally could drive stock negative. The reversal
 * is clamped at zero, and the logged ADJUSTMENT movement records the
 * amount actually applied (not the original purchase amount) so the
 * audit trail stays honest about what really changed. */
async function reverseInventoryMovement(conn, storeId, expenseId, note) {
  const previous = await inventoryRepository.findLatestForReference(conn, storeId, expenseId);
  if (!previous) return;
  const { applied, clamped } = await productRepository.clampedAdjustStock(
    conn,
    storeId,
    previous.product_id,
    -previous.quantity_delta
  );
  if (applied === 0) return;
  await inventoryRepository.insertMovement(conn, storeId, {
    id: uuidv4(),
    productId: previous.product_id,
    clientOperationId: null,
    quantityDelta: applied,
    movementType: 'ADJUSTMENT',
    referenceId: expenseId,
    note: clamped
      ? `${note} — clamped: stock from this purchase was already partially/fully sold, floored at 0`
      : note,
  });
}

/** Records a new PURCHASE inventory movement for this expense, inside
 * the given transaction. products.stock_quantity is an INTEGER column
 * (pre-existing schema — see migrations/001_init.sql), so a fractional
 * supply quantity (e.g. 15.5 kg) is rounded to the nearest whole unit
 * for the stock movement; the expense record itself always keeps the
 * exact quantity/unit the user entered. */
async function applyInventoryMovement(conn, storeId, productId, quantity, expenseId, note) {
  const product = await productRepository.findByIdForUpdate(conn, storeId, productId);
  if (!product) throw ApiError.badRequest('Product not found in this store', 'INVALID_PRODUCT');
  const delta = Math.max(1, Math.round(Number(quantity) || 0));
  const success = await productRepository.adjustStock(conn, storeId, productId, delta);
  if (!success) {
    throw ApiError.conflict(
      `Stock adjustment failed for "${product.name}"`,
      'STOCK_ADJUST_FAILED'
    );
  }
  await inventoryRepository.insertMovement(conn, storeId, {
    id: uuidv4(),
    productId,
    clientOperationId: null,
    quantityDelta: delta,
    movementType: 'PURCHASE',
    referenceId: expenseId,
    note,
  });
}

/**
 * Ingredient-side counterpart of applyInventoryMovement — the actual
 * "Supplies come from Expenses" link (spec §3). Unlike the product path,
 * `ingredients.stock_quantity` is DECIMAL(14,3), so the full fractional
 * quantity is kept (a 15.5 kg purchase is 15.5 kg of real stock, not
 * rounded to 16).
 */
async function applyIngredientPurchase(conn, storeId, ingredientId, quantity, expenseId, note) {
  const ingredient = await ingredientRepository.findByIdForUpdate(conn, storeId, ingredientId);
  if (!ingredient) throw ApiError.badRequest('Ingredient not found in this store', 'INVALID_INGREDIENT');
  const delta = Number(quantity) || 0;
  if (delta <= 0) throw ApiError.badRequest('quantity must be greater than 0', 'INVALID_QUANTITY');
  const success = await ingredientRepository.adjustStock(conn, storeId, ingredientId, delta);
  if (!success) {
    throw ApiError.conflict(
      `Stock adjustment failed for "${ingredient.name}"`,
      'STOCK_ADJUST_FAILED'
    );
  }
  await ingredientMovementRepository.insertMovement(conn, storeId, {
    id: uuidv4(),
    ingredientId,
    quantityDelta: delta,
    movementType: 'PURCHASE',
    referenceId: expenseId,
    note,
  });
}

/**
 * Reverses a previously-recorded ingredient PURCHASE movement for this
 * expense, inside the given transaction — same role as
 * reverseInventoryMovement but for the ingredient/supply stock.
 *
 * ROOT CAUSE FIX for the negative-stock bug (e.g. "café" reaching
 * -425 kg): this used to call `forceAdjustStock`, which subtracts the
 * ORIGINAL purchase quantity unconditionally, with no floor. If sales had
 * already consumed some or all of that purchase by the time the expense
 * was edited or deleted, the reversal would drive stock_quantity below
 * zero. It now uses `clampedAdjustStock`, which floors the result at
 * zero and reports the amount actually applied, so the logged movement
 * reflects reality instead of the (possibly no-longer-available) original
 * purchase amount.
 */
async function reverseIngredientPurchase(conn, storeId, expenseId, note) {
  const previous = await ingredientMovementRepository.findLatestForReference(conn, storeId, expenseId);
  if (!previous) return;
  const { applied, clamped } = await ingredientRepository.clampedAdjustStock(
    conn,
    storeId,
    previous.ingredient_id,
    -previous.quantity_delta
  );
  if (applied === 0) return;
  await ingredientMovementRepository.insertMovement(conn, storeId, {
    id: uuidv4(),
    ingredientId: previous.ingredient_id,
    quantityDelta: applied,
    movementType: 'ADJUSTMENT',
    referenceId: expenseId,
    note: clamped
      ? `${note} — clamped: stock from this purchase was already partially/fully consumed, floored at 0`
      : note,
  });
}

async function getById(storeId, id) {
  const expense = await expenseRepository.findById(storeId, id);
  if (!expense) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
  return expense;
}

async function create(storeId, userId, input) {
  const existing = await expenseRepository.findByClientOperationId(
    storeId,
    input.client_operation_id
  );
  if (existing) {
    return { expense: existing, wasDuplicate: true };
  }

  const { categoryId, categoryName, expenseType } = await resolveCategory(storeId, input);

  const hasQuantityPricing = input.quantity != null && input.unit_price != null;
  const amount = hasQuantityPricing ? computeTotal(input.quantity, input.unit_price) : input.amount;
  if (amount == null) {
    throw ApiError.badRequest('amount (or quantity + unit_price) is required', 'AMOUNT_REQUIRED');
  }

  const { supplierId, supplierName } = await resolveSupplier(
    storeId,
    input.supplier_id,
    input.supplier_name
  );

  if (input.product_id && input.ingredient_id) {
    throw ApiError.badRequest(
      'A purchase links to either a product or a supply/ingredient, not both',
      'AMBIGUOUS_INVENTORY_TARGET'
    );
  }
  if (input.affects_inventory && !input.product_id && !input.ingredient_id) {
    throw ApiError.badRequest(
      'product_id or ingredient_id is required when affects_inventory is true',
      'PRODUCT_REQUIRED'
    );
  }
  const affectsInventory =
    Boolean(input.affects_inventory) && Boolean(input.product_id || input.ingredient_id);
  const isIngredientPurchase = affectsInventory && Boolean(input.ingredient_id);

  const id = uuidv4();
  const occurredAt = input.occurred_at ? new Date(input.occurred_at) : new Date();

  await withTransaction(async (conn) => {
    if (isIngredientPurchase) {
      await applyIngredientPurchase(
        conn,
        storeId,
        input.ingredient_id,
        input.quantity,
        id,
        `Purchase: ${categoryName}${input.quantity != null && input.unit ? ` (${input.quantity} ${input.unit})` : ''}`
      );
    } else if (affectsInventory) {
      await applyInventoryMovement(
        conn,
        storeId,
        input.product_id,
        input.quantity,
        id,
        `Purchase: ${categoryName}${input.quantity != null && input.unit ? ` (${input.quantity} ${input.unit})` : ''}`
      );
    }
    await expenseRepository.create(conn, storeId, userId, {
      id,
      clientOperationId: input.client_operation_id,
      amount,
      category: categoryName,
      expenseType,
      categoryId,
      description: input.description,
      quantity: input.quantity ?? null,
      unit: input.unit ?? null,
      unitPrice: input.unit_price ?? null,
      supplierId,
      supplierName,
      notes: input.notes ?? null,
      productId: affectsInventory && !isIngredientPurchase ? input.product_id : null,
      ingredientId: isIngredientPurchase ? input.ingredient_id : null,
      affectsInventory,
      isRecurring: Boolean(input.is_recurring),
      recurringDay: input.recurring_day ?? null,
      occurredAt,
    });
  });

  const expense = await expenseRepository.findById(storeId, id);
  return { expense, wasDuplicate: false };
}

async function update(storeId, id, input) {
  const current = await expenseRepository.findById(storeId, id);
  if (!current) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');

  let categoryId = current.category_id;
  let categoryName = current.category;
  let expenseType = current.expense_type;
  if (input.category_id !== undefined) {
    if (input.category_id === null) {
      categoryId = null;
      categoryName = input.category ?? current.category;
      expenseType = input.expense_type ?? current.expense_type;
    } else {
      const category = await expenseCategoryRepository.findById(storeId, input.category_id);
      if (!category) throw ApiError.badRequest('Category not found', 'INVALID_CATEGORY');
      categoryId = category.id;
      categoryName = category.name;
      expenseType = category.expense_type;
    }
  } else {
    if (input.category !== undefined) categoryName = input.category;
    if (input.expense_type !== undefined) expenseType = input.expense_type;
  }

  const quantity =
    input.quantity !== undefined ? input.quantity : current.quantity != null ? Number(current.quantity) : null;
  const unitPrice =
    input.unit_price !== undefined
      ? input.unit_price
      : current.unit_price != null
      ? Number(current.unit_price)
      : null;
  const recalculate = input.quantity !== undefined || input.unit_price !== undefined;
  let amount = input.amount !== undefined ? input.amount : Number(current.amount);
  if (recalculate && quantity != null && unitPrice != null) {
    amount = computeTotal(quantity, unitPrice);
  }

  let supplierId = input.supplier_id !== undefined ? input.supplier_id : current.supplier_id;
  let supplierName = input.supplier_name !== undefined ? input.supplier_name : current.supplier_name;
  if (input.supplier_id) {
    const resolved = await resolveSupplier(storeId, input.supplier_id, input.supplier_name);
    supplierId = resolved.supplierId;
    supplierName = resolved.supplierName;
  }

  const newAffectsInventory =
    input.affects_inventory !== undefined
      ? Boolean(input.affects_inventory)
      : Boolean(current.affects_inventory);
  const newProductId = input.product_id !== undefined ? input.product_id : current.product_id;
  const newIngredientId =
    input.ingredient_id !== undefined ? input.ingredient_id : current.ingredient_id;
  if (input.product_id && input.ingredient_id) {
    throw ApiError.badRequest(
      'A purchase links to either a product or a supply/ingredient, not both',
      'AMBIGUOUS_INVENTORY_TARGET'
    );
  }
  if (newAffectsInventory && !newProductId && !newIngredientId) {
    throw ApiError.badRequest(
      'product_id or ingredient_id is required when affects_inventory is true',
      'PRODUCT_REQUIRED'
    );
  }
  // A product_id / ingredient_id given explicitly always wins over
  // whichever target was previously set (switching a purchase's target).
  const newIsIngredientPurchase = newAffectsInventory
    ? input.ingredient_id !== undefined
      ? Boolean(input.ingredient_id)
      : input.product_id !== undefined
      ? false
      : Boolean(current.ingredient_id)
    : false;
  const effectiveProductId = newIsIngredientPurchase ? null : newProductId;
  const effectiveIngredientId = newIsIngredientPurchase ? newIngredientId : null;

  // Whether the inventory effect of this expense needs to be reversed
  // and/or re-applied — true if the link is toggled, the target changes,
  // or the quantity changes (an amount-only edit does not touch inventory).
  const wasIngredientPurchase = Boolean(current.ingredient_id);
  const inventoryLinkChanged =
    Boolean(current.affects_inventory) !== newAffectsInventory ||
    wasIngredientPurchase !== newIsIngredientPurchase ||
    (current.product_id ?? null) !== (effectiveProductId ?? null) ||
    (current.ingredient_id ?? null) !== (effectiveIngredientId ?? null) ||
    (quantity != null && current.quantity != null && Number(current.quantity) !== Number(quantity));

  await withTransaction(async (conn) => {
    if (Boolean(current.affects_inventory) && inventoryLinkChanged) {
      if (wasIngredientPurchase) {
        await reverseIngredientPurchase(conn, storeId, id, `Reversal: expense edited (${categoryName})`);
      } else {
        await reverseInventoryMovement(conn, storeId, id, `Reversal: expense edited (${categoryName})`);
      }
    }
    if (newAffectsInventory && inventoryLinkChanged) {
      if (newIsIngredientPurchase) {
        await applyIngredientPurchase(
          conn,
          storeId,
          effectiveIngredientId,
          quantity,
          id,
          `Purchase: ${categoryName} (edited)`
        );
      } else {
        await applyInventoryMovement(
          conn,
          storeId,
          effectiveProductId,
          quantity,
          id,
          `Purchase: ${categoryName} (edited)`
        );
      }
    }

    const updated = await expenseRepository.update(conn, storeId, id, {
      category: categoryName,
      expense_type: expenseType,
      category_id: categoryId,
      description: input.description !== undefined ? input.description : current.description,
      amount,
      quantity,
      unit: input.unit !== undefined ? input.unit : current.unit,
      unit_price: unitPrice,
      supplier_id: supplierId,
      supplier_name: supplierName,
      notes: input.notes !== undefined ? input.notes : current.notes,
      product_id: newAffectsInventory ? effectiveProductId : null,
      ingredient_id: newAffectsInventory ? effectiveIngredientId : null,
      affects_inventory: newAffectsInventory ? 1 : 0,
      is_recurring:
        input.is_recurring !== undefined ? Boolean(input.is_recurring) : Boolean(current.is_recurring),
      recurring_day: input.recurring_day !== undefined ? input.recurring_day : current.recurring_day,
      occurred_at: input.occurred_at ? new Date(input.occurred_at) : current.occurred_at,
    });
    if (!updated) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
  });

  return expenseRepository.findById(storeId, id);
}

async function remove(storeId, id) {
  const current = await expenseRepository.findById(storeId, id);
  if (!current) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');

  await withTransaction(async (conn) => {
    if (current.affects_inventory) {
      await reverseInventoryMovement(
        conn,
        storeId,
        id,
        `Reversal: expense deleted (${current.category})`
      );
    }
    const removed = await expenseRepository.remove(conn, storeId, id);
    if (!removed) throw ApiError.notFound('Expense not found', 'EXPENSE_NOT_FOUND');
  });

  if (current.receipt_url) deleteExpenseReceiptFile(current.receipt_url);

  return { id };
}

async function list(storeId, query) {
  return expenseRepository.list(storeId, {
    from: query.from,
    to: query.to,
    expenseType: query.expense_type,
    categoryId: query.category_id,
    supplierId: query.supplier_id,
    unit: query.unit,
    search: query.search,
    minAmount: query.min_amount != null ? Number(query.min_amount) : undefined,
    maxAmount: query.max_amount != null ? Number(query.max_amount) : undefined,
    page: Math.max(1, Number.parseInt(query?.page, 10) || 1),
    pageSize: Math.max(1, Number.parseInt(query?.page_size, 10) || 50),
  });
}

async function monthlyReport(storeId, year, month) {
  const { start, endInclusive } = monthRange(year, month);
  const [byType, byCategory] = await Promise.all([
    expenseRepository.monthlySummaryByType(storeId, start, endInclusive),
    expenseRepository.monthlySummaryByCategory(storeId, start, endInclusive),
  ]);

  const typeTotals = { APPROVISIONNEMENT: 0, CHARGE_FIXE: 0, AUTRE: 0 };
  const typeCounts = { APPROVISIONNEMENT: 0, CHARGE_FIXE: 0, AUTRE: 0 };
  for (const row of byType) {
    typeTotals[row.expense_type] = Number(row.amount);
    typeCounts[row.expense_type] = Number(row.count);
  }
  const totalAmount = typeTotals.APPROVISIONNEMENT + typeTotals.CHARGE_FIXE + typeTotals.AUTRE;
  const totalCount = typeCounts.APPROVISIONNEMENT + typeCounts.CHARGE_FIXE + typeCounts.AUTRE;

  return {
    year,
    month,
    summary: {
      supplies: typeTotals.APPROVISIONNEMENT.toFixed(2),
      fixed: typeTotals.CHARGE_FIXE.toFixed(2),
      other: typeTotals.AUTRE.toFixed(2),
      total: totalAmount.toFixed(2),
    },
    counts: {
      supplies: typeCounts.APPROVISIONNEMENT,
      fixed: typeCounts.CHARGE_FIXE,
      other: typeCounts.AUTRE,
      total: totalCount,
    },
    count: totalCount,
    categories: byCategory.map((c) => ({
      category: c.category,
      expense_type: c.expense_type,
      amount: Number(c.amount).toFixed(2),
      count: c.count,
    })),
  };
}

async function recurringSuggestions(storeId, year, month) {
  const { start, endExclusive } = monthRange(year, month);
  return expenseRepository.recurringSuggestions(storeId, start, endExclusive);
}

async function listCategories(storeId, query) {
  return expenseCategoryRepository.list(storeId, {
    expenseType: query.expense_type,
    includeInactive: query.include_inactive === 'true' || query.include_inactive === true,
  });
}

async function createCategory(storeId, input) {
  return expenseCategoryRepository.create(storeId, {
    id: uuidv4(),
    name: input.name,
    expenseType: input.expense_type,
    isActive: true,
  });
}

async function updateCategory(storeId, id, input) {
  const updated = await expenseCategoryRepository.update(storeId, id, input);
  if (!updated) throw ApiError.notFound('Category not found', 'CATEGORY_NOT_FOUND');
  return updated;
}

async function deactivateCategory(storeId, id) {
  const removed = await expenseCategoryRepository.deactivate(storeId, id);
  if (!removed) throw ApiError.notFound('Category not found', 'CATEGORY_NOT_FOUND');
  return { id };
}

async function setReceipt(storeId, id, receiptUrl) {
  const current = await getById(storeId, id);
  if (current.receipt_url) deleteExpenseReceiptFile(current.receipt_url);
  await withTransaction(async (conn) => {
    await expenseRepository.update(conn, storeId, id, { receipt_url: receiptUrl });
  });
  return expenseRepository.findById(storeId, id);
}

async function removeReceipt(storeId, id) {
  const current = await getById(storeId, id);
  if (current.receipt_url) deleteExpenseReceiptFile(current.receipt_url);
  await withTransaction(async (conn) => {
    await expenseRepository.update(conn, storeId, id, { receipt_url: null });
  });
  return expenseRepository.findById(storeId, id);
}

/**
 * Combined Stocks + Dépenses feed — a single chronological list mixing
 * expense entries and ingredient stock movements (see
 * expenseRepository.combinedFeed for the underlying UNION query).
 */
async function feed(storeId, query = {}) {
  const page = Number(query.page) > 0 ? Number(query.page) : 1;
  const pageSize = Number(query.page_size) > 0 ? Number(query.page_size) : 30;
  return expenseRepository.combinedFeed(storeId, { page, pageSize });
}

module.exports = {
  getById,
  create,
  update,
  remove,
  list,
  monthlyReport,
  recurringSuggestions,
  listCategories,
  createCategory,
  updateCategory,
  deactivateCategory,
  setReceipt,
  removeReceipt,
  feed,
};
