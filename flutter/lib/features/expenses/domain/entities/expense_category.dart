import 'expense_type.dart';

/// A configurable expense category (spec §1) — e.g. "Café" under
/// Approvisionnement, or "Électricité" under Charge fixe. Mirrors
/// GET /api/expenses/categories.
class ExpenseCategory {
  final String id;
  final String name;
  final ExpenseType expenseType;
  final bool isActive;

  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.expenseType,
    required this.isActive,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) {
    return ExpenseCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      expenseType: ExpenseType.fromApiValue(json['expense_type'] as String),
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active'] as num? ?? 1) != 0,
    );
  }
}
