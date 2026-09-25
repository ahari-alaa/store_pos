/// Rapports-only domain models — everything GET /reports/sales,
/// /reports/expenses and /reports/stock return, plus the shared
/// payment-breakdown shape used both store-wide (salesSummary) and
/// per-cashier (cashier_sales_report.dart's paymentBreakdown). KPIs,
/// cashier ranking, top products and the revenue chart reuse the
/// existing dashboard entities in dashboard_extras.dart instead of
/// duplicating them (spec §25) — see reports_api.dart.
library reports_models;

/// One payment method's amount/share/transaction count, for a given
/// period and (optionally) a given cashier. Mirrors reportService.js's
/// `percentOf`-computed rows — donut slice + legend row on the Rapports
/// "Répartition des paiements" section (spec §9) and the cashier-detail
/// drill-down's own payment breakdown (spec §11).
class PaymentBreakdownEntry {
  final String paymentMethod;
  final double amount;
  final int transactionCount;
  final double percent;

  const PaymentBreakdownEntry({
    required this.paymentMethod,
    required this.amount,
    required this.transactionCount,
    required this.percent,
  });

  factory PaymentBreakdownEntry.fromJson(Map<String, dynamic> json) {
    return PaymentBreakdownEntry(
      paymentMethod: '${json['payment_method'] ?? '—'}',
      amount: double.tryParse('${json['amount'] ?? 0}') ?? 0,
      transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      percent: double.tryParse('${json['percent'] ?? 0}') ?? 0,
    );
  }
}

/// Real sale_status / payment_status counts for the period (spec §8) —
/// never an invented bucket; every field here is a value the schema
/// actually defines (migrations/001_init.sql).
class SalesStatusSummary {
  final int total;
  final int completed;
  final int cancelled;
  final int refundedSales;
  final int paid;
  final int notPaid;
  final int partiallyPaid;
  final int refundedPayments;

  const SalesStatusSummary({
    required this.total,
    required this.completed,
    required this.cancelled,
    required this.refundedSales,
    required this.paid,
    required this.notPaid,
    required this.partiallyPaid,
    required this.refundedPayments,
  });

  static const empty = SalesStatusSummary(
    total: 0,
    completed: 0,
    cancelled: 0,
    refundedSales: 0,
    paid: 0,
    notPaid: 0,
    partiallyPaid: 0,
    refundedPayments: 0,
  );

  factory SalesStatusSummary.fromJson(Map<String, dynamic> json) {
    return SalesStatusSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      refundedSales: (json['refunded_sales'] as num?)?.toInt() ?? 0,
      paid: (json['paid'] as num?)?.toInt() ?? 0,
      notPaid: (json['not_paid'] as num?)?.toInt() ?? 0,
      partiallyPaid: (json['partially_paid'] as num?)?.toInt() ?? 0,
      refundedPayments: (json['refunded_payments'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One day of the sales-summary's `by_day` breakdown — the raw data the
/// revenue evolution chart could also be built from, but is not: the
/// chart uses /reports/dashboard-revenue's auto-granularity buckets
/// instead, since a multi-month period needs monthly bars, not one bar
/// per day (see revenue_evolution_chart.dart).
class SalesByDayEntry {
  final DateTime day;
  final int saleCount;
  final double revenue;

  const SalesByDayEntry({required this.day, required this.saleCount, required this.revenue});

  factory SalesByDayEntry.fromJson(Map<String, dynamic> json) {
    return SalesByDayEntry(
      day: DateTime.tryParse('${json['day']}') ?? DateTime.now(),
      saleCount: (json['sale_count'] as num?)?.toInt() ?? 0,
      revenue: double.tryParse('${json['revenue'] ?? 0}') ?? 0,
    );
  }
}

/// GET /reports/sales?period= — backs both the "Résumé des ventes" (spec
/// §8) and "Répartition des paiements" (spec §9) sections from a single
/// request, per the performance note in spec §21.
class SalesSummaryReport {
  final int saleCount;
  final double totalRevenue;
  final double totalDiscount;
  final double totalTax;
  final double averageSale;
  final List<SalesByDayEntry> byDay;
  final List<PaymentBreakdownEntry> byPaymentMethod;
  final SalesStatusSummary statusSummary;

  const SalesSummaryReport({
    required this.saleCount,
    required this.totalRevenue,
    required this.totalDiscount,
    required this.totalTax,
    required this.averageSale,
    required this.byDay,
    required this.byPaymentMethod,
    required this.statusSummary,
  });

  static const empty = SalesSummaryReport(
    saleCount: 0,
    totalRevenue: 0,
    totalDiscount: 0,
    totalTax: 0,
    averageSale: 0,
    byDay: [],
    byPaymentMethod: [],
    statusSummary: SalesStatusSummary.empty,
  );

  factory SalesSummaryReport.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return SalesSummaryReport(
      saleCount: (totals['sale_count'] as num?)?.toInt() ?? 0,
      totalRevenue: double.tryParse('${totals['total_revenue'] ?? 0}') ?? 0,
      totalDiscount: double.tryParse('${totals['total_discount'] ?? 0}') ?? 0,
      totalTax: double.tryParse('${totals['total_tax'] ?? 0}') ?? 0,
      averageSale: double.tryParse('${totals['average_sale'] ?? 0}') ?? 0,
      byDay: (json['by_day'] as List<dynamic>? ?? const [])
          .map((raw) => SalesByDayEntry.fromJson(raw as Map<String, dynamic>))
          .toList(),
      byPaymentMethod: (json['by_payment_method'] as List<dynamic>? ?? const [])
          .map((raw) => PaymentBreakdownEntry.fromJson(raw as Map<String, dynamic>))
          .toList(),
      statusSummary: SalesStatusSummary.fromJson(
        json['status_summary'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

/// One row of GET /reports/expenses's `by_category` (spec §13).
class ExpenseCategoryEntry {
  final String category;
  final double amount;
  final int count;

  const ExpenseCategoryEntry({required this.category, required this.amount, required this.count});

  factory ExpenseCategoryEntry.fromJson(Map<String, dynamic> json) {
    return ExpenseCategoryEntry(
      category: '${json['category'] ?? '—'}',
      amount: double.tryParse('${json['amount'] ?? 0}') ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// GET /reports/expenses?period= (spec §13).
class ExpensesReport {
  final int expenseCount;
  final double totalAmount;
  final List<ExpenseCategoryEntry> byCategory;

  const ExpensesReport({
    required this.expenseCount,
    required this.totalAmount,
    required this.byCategory,
  });

  static const empty = ExpensesReport(expenseCount: 0, totalAmount: 0, byCategory: []);

  factory ExpensesReport.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>? ?? const {};
    return ExpensesReport(
      expenseCount: (totals['expense_count'] as num?)?.toInt() ?? 0,
      totalAmount: double.tryParse('${totals['total_amount'] ?? 0}') ?? 0,
      byCategory: (json['by_category'] as List<dynamic>? ?? const [])
          .map((raw) => ExpenseCategoryEntry.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// A stock-status severity, derived the exact same way
/// StatusBadge.stock computes it client-side (quantity <= 0 → rupture,
/// <= threshold → faible) — the raw backend `status` string is kept only
/// as a secondary signal (e.g. for CSV/PDF export, which has no badge
/// widget to fall back on).
enum StockSeverity { outOfStock, low }

/// One low/out-of-stock product or ingredient row (spec §14). Products
/// and ingredients share this shape even though they come from two
/// different backend tables (`products` vs `ingredients`), because the
/// Rapports "État du stock" section shows them in one combined view.
class StockItemEntry {
  final String id;
  final String name;

  /// Product category, or the ingredient's unit (g/kg/ml/l/unit) —
  /// whichever this row is. A secondary label shown next to the name,
  /// never used to filter or group.
  final String? secondaryLabel;
  final double stockQuantity;
  final double minimum;
  final String rawStatus;

  const StockItemEntry({
    required this.id,
    required this.name,
    required this.secondaryLabel,
    required this.stockQuantity,
    required this.minimum,
    required this.rawStatus,
  });

  StockSeverity get severity => stockQuantity <= 0 ? StockSeverity.outOfStock : StockSeverity.low;

  factory StockItemEntry.fromProductJson(Map<String, dynamic> json, {required double threshold}) {
    return StockItemEntry(
      id: '${json['id']}',
      name: '${json['name'] ?? '—'}',
      secondaryLabel: json['category'] as String?,
      stockQuantity: double.tryParse('${json['stock_quantity'] ?? 0}') ?? 0,
      minimum: threshold,
      rawStatus: '${json['status'] ?? ''}',
    );
  }

  /// Ingredients carry their own `min_stock` per row (unlike products,
  /// which only have the shared threshold query param — see
  /// reportService.js#stockReport's doc comment).
  factory StockItemEntry.fromIngredientJson(Map<String, dynamic> json) {
    return StockItemEntry(
      id: '${json['id']}',
      name: '${json['name'] ?? '—'}',
      secondaryLabel: json['unit'] as String?,
      stockQuantity: double.tryParse('${json['stock_quantity'] ?? 0}') ?? 0,
      minimum: double.tryParse('${json['min_stock'] ?? 0}') ?? 0,
      rawStatus: '${json['status'] ?? ''}',
    );
  }
}

/// GET /reports/stock?threshold= (spec §14).
class StockReport {
  final double threshold;
  final List<StockItemEntry> products;
  final List<StockItemEntry> ingredients;

  const StockReport({required this.threshold, required this.products, required this.ingredients});

  static const empty = StockReport(threshold: 5, products: [], ingredients: []);

  int get outOfStockCount =>
      products.where((p) => p.severity == StockSeverity.outOfStock).length +
      ingredients.where((i) => i.severity == StockSeverity.outOfStock).length;

  int get lowStockCount =>
      products.where((p) => p.severity == StockSeverity.low).length +
      ingredients.where((i) => i.severity == StockSeverity.low).length;

  factory StockReport.fromJson(Map<String, dynamic> json) {
    final threshold = double.tryParse('${json['threshold'] ?? 5}') ?? 5;
    return StockReport(
      threshold: threshold,
      products: (json['products'] as List<dynamic>? ?? const [])
          .map((raw) => StockItemEntry.fromProductJson(
                raw as Map<String, dynamic>,
                threshold: threshold,
              ))
          .toList(),
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .map((raw) => StockItemEntry.fromIngredientJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }
}
