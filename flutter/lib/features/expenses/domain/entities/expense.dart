import '../../../../core/config/api_config.dart';
import 'expense_type.dart';
import 'expense_unit.dart';

/// A single expense/purchase/monthly-bill row. Mirrors the extended
/// `expenses` table (see migrations/005_expenses_management.sql) and the
/// shape returned by GET /api/expenses, GET /api/expenses/:id, and the
/// create/update responses.
class Expense {
  final String id;
  final String clientOperationId;
  final ExpenseType expenseType;
  final String? categoryId;
  final String category;
  final String? description;
  final double amount;

  // Supplies-only breakdown (spec §2) — null for a plain fixed charge.
  final double? quantity;
  final ExpenseUnit? unit;
  final double? unitPrice;

  final String? supplierId;
  final String? supplierName;
  final String? notes;

  // Inventory linkage (spec §14) — a purchase restocks either a finished
  // product OR a raw supply/ingredient (spec §3), never both.
  final String? productId;
  final String? productName;
  final String? ingredientId;
  final String? ingredientName;
  final bool affectsInventory;

  // Recurring / monthly-template support (spec §5).
  final bool isRecurring;
  final int? recurringDay;

  final String? receiptUrl;
  final DateTime occurredAt;
  final DateTime createdAt;

  const Expense({
    required this.id,
    required this.clientOperationId,
    required this.expenseType,
    required this.categoryId,
    required this.category,
    required this.description,
    required this.amount,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.supplierId,
    required this.supplierName,
    required this.notes,
    required this.productId,
    required this.productName,
    required this.ingredientId,
    required this.ingredientName,
    required this.affectsInventory,
    required this.isRecurring,
    required this.recurringDay,
    required this.receiptUrl,
    required this.occurredAt,
    required this.createdAt,
  });

  /// True for a supplies-style entry with a quantity × unit price
  /// breakdown, false for a plain fixed-charge amount.
  bool get hasQuantityBreakdown => quantity != null && unit != null;

  /// True when the receipt file is a PDF rather than an image, based on
  /// its stored extension (see middleware/upload.js#ALLOWED_RECEIPT_MIME_TYPES
  /// on the backend, which is what decided the extension at upload time).
  bool get receiptIsPdf => (receiptUrl ?? '').toLowerCase().endsWith('.pdf');

  /// [receiptUrl] as returned by the backend is a relative path
  /// (`/uploads/expenses/xyz.jpg`) — resolves it against the API server's
  /// origin so `Image.network` (or a raw fetch, for a PDF) can load it
  /// directly. Mirrors Product.fullImageUrl.
  String? get fullReceiptUrl {
    final raw = receiptUrl;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    var path = raw.replaceAll('\\', '/');
    if (!path.startsWith('/')) path = '/$path';
    return '${ApiConfig.originUrl}$path';
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    bool asBool(dynamic v) => v is bool ? v : (v as num? ?? 0) != 0;
    double? asDoubleOrNull(dynamic v) => v == null ? null : double.tryParse('$v');

    return Expense(
      id: json['id'] as String,
      clientOperationId: json['client_operation_id'] as String? ?? '',
      expenseType: ExpenseType.fromApiValue(json['expense_type'] as String? ?? 'AUTRE'),
      categoryId: json['category_id'] as String?,
      category: json['category'] as String? ?? '',
      description: json['description'] as String?,
      amount: double.tryParse('${json['amount']}') ?? 0,
      quantity: asDoubleOrNull(json['quantity']),
      unit: ExpenseUnit.fromApiValue(json['unit'] as String?),
      unitPrice: asDoubleOrNull(json['unit_price']),
      supplierId: json['supplier_id'] as String?,
      supplierName: (json['supplier_name'] as String?) ??
          (json['linked_supplier_name'] as String?),
      notes: json['notes'] as String?,
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String?,
      ingredientId: json['ingredient_id'] as String?,
      ingredientName: json['ingredient_name'] as String?,
      affectsInventory: asBool(json['affects_inventory']),
      isRecurring: asBool(json['is_recurring']),
      recurringDay: (json['recurring_day'] as num?)?.toInt(),
      receiptUrl: json['receipt_url'] as String?,
      occurredAt: DateTime.tryParse(json['occurred_at'] as String? ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
