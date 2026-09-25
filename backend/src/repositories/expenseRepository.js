const { pool } = require('../config/db');

/**
 * `expenses` repository — extended for the Expenses & Supplies
 * Management System (see migrations/005_expenses_management.sql).
 *
 * create/update/remove take a transaction `conn` because expenseService
 * needs to atomically pair them with an inventory_movements write when
 * an expense affects stock (spec §14) — see inventoryRepository for the
 * matching half of that transaction.
 */

/** Whether any expense (purchase record) still points at this ingredient
 * — used by ingredientService.remove as part of the "does this ingredient
 * have history?" check (spec: deleting a supply must never orphan a
 * financial/expense record). In practice every ingredient-linked expense
 * also has a matching ingredient_stock_movements row (see
 * expenseService.applyIngredientPurchase), so this mostly duplicates that
 * check — kept as an explicit, independent guard rather than relying on
 * that always staying true. */
async function hasIngredientReference(storeId, ingredientId) {
  const [rows] = await pool.query(
    'SELECT 1 FROM expenses WHERE store_id = ? AND ingredient_id = ? LIMIT 1',
    [storeId, ingredientId]
  );
  return rows.length > 0;
}

/** Transaction-scoped variant of hasIngredientReference — used by
 * ingredientService.remove inside the same transaction as the recipe-line
 * cleanup and the hard/soft delete decision (spec §3). */
async function hasIngredientReferenceTx(conn, storeId, ingredientId) {
  const [rows] = await conn.query(
    'SELECT 1 FROM expenses WHERE store_id = ? AND ingredient_id = ? LIMIT 1',
    [storeId, ingredientId]
  );
  return rows.length > 0;
}

async function findByClientOperationId(storeId, clientOperationId) {
  const [rows] = await pool.query(
    'SELECT * FROM expenses WHERE store_id = ? AND client_operation_id = ? LIMIT 1',
    [storeId, clientOperationId]
  );
  return rows[0] || null;
}

const SELECT_WITH_JOINS = `
  SELECT e.*,
         ec.name AS category_display_name,
         s.name  AS linked_supplier_name,
         p.name  AS product_name,
         i.name  AS ingredient_name,
         i.unit  AS ingredient_unit
    FROM expenses e
    LEFT JOIN expense_categories ec ON ec.id = e.category_id
    LEFT JOIN suppliers s ON s.id = e.supplier_id
    LEFT JOIN products p ON p.id = e.product_id
    LEFT JOIN ingredients i ON i.id = e.ingredient_id
`;

async function findById(storeId, id) {
  const [rows] = await pool.query(
    `${SELECT_WITH_JOINS} WHERE e.id = ? AND e.store_id = ? LIMIT 1`,
    [id, storeId]
  );
  return rows[0] || null;
}

async function create(conn, storeId, userId, expense) {
  await conn.query(
    `INSERT INTO expenses
       (id, store_id, user_id, client_operation_id, amount, category, expense_type, category_id,
        description, quantity, unit, unit_price, supplier_id, supplier_name, notes,
        product_id, ingredient_id, affects_inventory, is_recurring, recurring_day, occurred_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      expense.id,
      storeId,
      userId,
      expense.clientOperationId,
      expense.amount,
      expense.category,
      expense.expenseType,
      expense.categoryId || null,
      expense.description || null,
      expense.quantity ?? null,
      expense.unit || null,
      expense.unitPrice ?? null,
      expense.supplierId || null,
      expense.supplierName || null,
      expense.notes || null,
      expense.productId || null,
      expense.ingredientId || null,
      expense.affectsInventory ? 1 : 0,
      expense.isRecurring ? 1 : 0,
      expense.recurringDay ?? null,
      expense.occurredAt,
    ]
  );
}

async function update(conn, storeId, id, fields) {
  const columns = [];
  const params = [];
  for (const [key, value] of Object.entries(fields)) {
    columns.push(`${key} = ?`);
    params.push(value);
  }
  if (columns.length === 0) return true;

  params.push(id, storeId);
  const [result] = await conn.query(
    `UPDATE expenses SET ${columns.join(', ')} WHERE id = ? AND store_id = ?`,
    params
  );
  return result.affectedRows > 0;
}

async function remove(conn, storeId, id) {
  const [result] = await conn.query('DELETE FROM expenses WHERE id = ? AND store_id = ?', [
    id,
    storeId,
  ]);
  return result.affectedRows > 0;
}

async function list(
  storeId,
  {
    from,
    to,
    expenseType,
    categoryId,
    supplierId,
    unit,
    search,
    minAmount,
    maxAmount,
    page,
    pageSize,
  }
) {
  const where = ['e.store_id = ?'];
  const params = [storeId];
  if (from) {
    where.push('e.occurred_at >= ?');
    params.push(from);
  }
  if (to) {
    where.push('e.occurred_at <= ?');
    params.push(to);
  }
  if (expenseType) {
    where.push('e.expense_type = ?');
    params.push(expenseType);
  }
  if (categoryId) {
    where.push('e.category_id = ?');
    params.push(categoryId);
  }
  if (supplierId) {
    where.push('e.supplier_id = ?');
    params.push(supplierId);
  }
  if (unit) {
    where.push('e.unit = ?');
    params.push(unit);
  }
  if (typeof minAmount === 'number') {
    where.push('e.amount >= ?');
    params.push(minAmount);
  }
  if (typeof maxAmount === 'number') {
    where.push('e.amount <= ?');
    params.push(maxAmount);
  }
  if (search) {
    where.push(
      '(e.category LIKE ? OR e.description LIKE ? OR e.supplier_name LIKE ? OR e.notes LIKE ?)'
    );
    const like = `%${search}%`;
    params.push(like, like, like, like);
  }
  const whereSql = where.join(' AND ');
  const offset = (page - 1) * pageSize;

  const [rows] = await pool.query(
    `${SELECT_WITH_JOINS} WHERE ${whereSql} ORDER BY e.occurred_at DESC, e.created_at DESC LIMIT ? OFFSET ?`,
    [...params, pageSize, offset]
  );
  const [countRows] = await pool.query(
    `SELECT COUNT(*) AS total FROM expenses e WHERE ${whereSql}`,
    params
  );
  return { items: rows, total: countRows[0].total, page, pageSize };
}

/** Totals grouped by expense_type for the given [start, end] range. */
async function monthlySummaryByType(storeId, start, end) {
  const [rows] = await pool.query(
    `SELECT expense_type, COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount
       FROM expenses
      WHERE store_id = ? AND occurred_at BETWEEN ? AND ?
      GROUP BY expense_type`,
    [storeId, start, end]
  );
  return rows;
}

/** Totals grouped by category name for the given [start, end] range —
 * falls back to the free-text `category` column for legacy rows that
 * have no category_id. */
async function monthlySummaryByCategory(storeId, start, end) {
  const [rows] = await pool.query(
    `SELECT COALESCE(ec.name, e.category) AS category, e.expense_type,
            COUNT(*) AS count, COALESCE(SUM(e.amount), 0) AS amount
       FROM expenses e
       LEFT JOIN expense_categories ec ON ec.id = e.category_id
      WHERE e.store_id = ? AND e.occurred_at BETWEEN ? AND ?
      GROUP BY COALESCE(ec.name, e.category), e.expense_type
      ORDER BY amount DESC`,
    [storeId, start, end]
  );
  return rows;
}

/**
 * "Monthly template" suggestions (spec §5): the most recent occurrence
 * of each recurring category, but only when that category has NOT
 * already been recorded within [monthStart, monthEndExclusive) — so a
 * suggestion never re-appears once the user has created that month's
 * expense, and re-fetching this list can never itself create a
 * duplicate (it's read-only).
 */
async function recurringSuggestions(storeId, monthStart, monthEndExclusive) {
  const [rows] = await pool.query(
    `SELECT e.*
       FROM expenses e
       INNER JOIN (
         SELECT category_id, MAX(occurred_at) AS latest_occurred_at
           FROM expenses
          WHERE store_id = ? AND is_recurring = 1 AND category_id IS NOT NULL
          GROUP BY category_id
       ) latest ON latest.category_id = e.category_id AND latest.latest_occurred_at = e.occurred_at
      WHERE e.store_id = ?
        AND NOT EXISTS (
          SELECT 1 FROM expenses ex
           WHERE ex.store_id = e.store_id
             AND ex.category_id = e.category_id
             AND ex.occurred_at >= ? AND ex.occurred_at < ?
        )
      ORDER BY e.category ASC`,
    [storeId, storeId, monthStart, monthEndExclusive]
  );
  return rows;
}

/**
 * Combined chronological feed of expenses AND ingredient stock movements
 * (Stocks + Dépenses merged into a single list per product decision).
 * Uses a raw UNION ALL so pagination/sorting happens in SQL instead of
 * fetching both tables in full and merging in JS.
 */
async function combinedFeed(storeId, { page = 1, pageSize = 30 } = {}) {
  const offset = (page - 1) * pageSize;

  const [rows] = await pool.query(
    `
    SELECT * FROM (
      SELECT
        e.id                AS id,
        'EXPENSE'           AS entry_type,
        e.occurred_at       AS occurred_at,
        e.amount            AS amount,
        NULL                AS quantity_delta,
        NULL                AS unit,
        e.expense_type      AS movement_type,
        COALESCE(ec.name, e.category) AS title,
        e.description       AS description,
        COALESCE(e.supplier_name, s.name) AS related_name
      FROM expenses e
      LEFT JOIN expense_categories ec ON ec.id = e.category_id
      LEFT JOIN suppliers s ON s.id = e.supplier_id
      WHERE e.store_id = ?

      UNION ALL

      SELECT
        m.id                AS id,
        'STOCK_MOVEMENT'    AS entry_type,
        m.created_at        AS occurred_at,
        NULL                AS amount,
        m.quantity_delta    AS quantity_delta,
        i.unit              AS unit,
        m.movement_type     AS movement_type,
        i.name              AS title,
        m.note              AS description,
        NULL                AS related_name
      FROM ingredient_stock_movements m
      JOIN ingredients i ON i.id = m.ingredient_id
      WHERE m.store_id = ?
    ) combined
    ORDER BY occurred_at DESC, id DESC
    LIMIT ? OFFSET ?
    `,
    [storeId, storeId, pageSize, offset]
  );

  const [[{ total }]] = await pool.query(
    `SELECT
       (SELECT COUNT(*) FROM expenses WHERE store_id = ?) +
       (SELECT COUNT(*) FROM ingredient_stock_movements WHERE store_id = ?) AS total`,
    [storeId, storeId]
  );

  return { items: rows, total, page, pageSize };
}

module.exports = {
  hasIngredientReference,
  hasIngredientReferenceTx,
  findByClientOperationId,
  findById,
  create,
  update,
  remove,
  list,
  monthlySummaryByType,
  monthlySummaryByCategory,
  recurringSuggestions,
  combinedFeed,
};
