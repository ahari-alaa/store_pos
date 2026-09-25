import 'expense_type.dart';

/// One row of the "Dépenses par catégorie" breakdown (spec §12).
class ExpenseCategoryTotal {
  final String category;
  final ExpenseType expenseType;
  final double amount;
  final int count;

  const ExpenseCategoryTotal({
    required this.category,
    required this.expenseType,
    required this.amount,
    required this.count,
  });

  factory ExpenseCategoryTotal.fromJson(Map<String, dynamic> json) {
    return ExpenseCategoryTotal(
      category: json['category'] as String? ?? '',
      expenseType: ExpenseType.fromApiValue(json['expense_type'] as String? ?? 'AUTRE'),
      amount: double.tryParse('${json['amount']}') ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// GET /api/expenses/report/monthly response (spec §12/§18).
class ExpenseMonthlyReport {
  final int year;
  final int month;
  final double supplies;
  final double fixed;
  final double other;
  final double total;
  final int suppliesCount;
  final int fixedCount;
  final int otherCount;
  final int totalCount;
  final List<ExpenseCategoryTotal> categories;

  const ExpenseMonthlyReport({
    required this.year,
    required this.month,
    required this.supplies,
    required this.fixed,
    required this.other,
    required this.total,
    required this.suppliesCount,
    required this.fixedCount,
    required this.otherCount,
    required this.totalCount,
    required this.categories,
  });

  factory ExpenseMonthlyReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] as Map<String, dynamic>? ?? {};
    final counts = json['counts'] as Map<String, dynamic>? ?? {};
    final categoriesJson = json['categories'] as List<dynamic>? ?? [];
    double asDouble(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
    int asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

    return ExpenseMonthlyReport(
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      month: (json['month'] as num?)?.toInt() ?? DateTime.now().month,
      supplies: asDouble(summary['supplies']),
      fixed: asDouble(summary['fixed']),
      other: asDouble(summary['other']),
      total: asDouble(summary['total']),
      suppliesCount: asInt(counts['supplies']),
      fixedCount: asInt(counts['fixed']),
      otherCount: asInt(counts['other']),
      totalCount: asInt(counts['total']),
      categories: categoriesJson
          .map((c) => ExpenseCategoryTotal.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  factory ExpenseMonthlyReport.empty(int year, int month) => ExpenseMonthlyReport(
        year: year,
        month: month,
        supplies: 0,
        fixed: 0,
        other: 0,
        total: 0,
        suppliesCount: 0,
        fixedCount: 0,
        otherCount: 0,
        totalCount: 0,
        categories: const [],
      );
}
