import 'reports_models.dart';

/// Aggregate stats for a cashier over a period — the numbers shown in the
/// stat cards on the Cashier detail screen's "Sales Report" section, for
/// both Day mode (period = one day) and Month mode's top summary (period =
/// one month). Mirrors the `summary` object returned by
/// GET /reports/cashier-sales (see backend/src/services/reportService.js
/// #cashierSalesReport) — every figure here is computed by the backend via
/// SQL aggregation, never by summing sales client-side (spec §10).
class CashierReportSummary {
  final int orders;
  final double totalSales;
  final int itemsSold;
  final double averageTicket;
  final int paidOrders;
  final int notPaidOrders;
  final int partiallyPaidOrders;

  const CashierReportSummary({
    required this.orders,
    required this.totalSales,
    this.itemsSold = 0,
    this.averageTicket = 0,
    required this.paidOrders,
    required this.notPaidOrders,
    required this.partiallyPaidOrders,
  });

  static const empty = CashierReportSummary(
    orders: 0,
    totalSales: 0,
    itemsSold: 0,
    averageTicket: 0,
    paidOrders: 0,
    notPaidOrders: 0,
    partiallyPaidOrders: 0,
  );

  factory CashierReportSummary.fromJson(Map<String, dynamic> json) {
    return CashierReportSummary(
      orders: (json['orders'] as num?)?.toInt() ?? 0,
      totalSales: double.tryParse('${json['total_sales']}') ?? 0,
      itemsSold: (json['items_sold'] as num?)?.toInt() ?? 0,
      averageTicket: double.tryParse('${json['average_ticket'] ?? 0}') ?? 0,
      paidOrders: (json['paid_orders'] as num?)?.toInt() ?? 0,
      notPaidOrders: (json['not_paid_orders'] as num?)?.toInt() ?? 0,
      partiallyPaidOrders: (json['partially_paid_orders'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One row of the Month report's daily breakdown table — a single day's
/// [CashierReportSummary] plus which calendar date it belongs to, so the
/// admin can tap it to drill into that day's receipts.
class CashierDailyBreakdown {
  final DateTime date;
  final CashierReportSummary summary;

  const CashierDailyBreakdown({required this.date, required this.summary});

  factory CashierDailyBreakdown.fromJson(Map<String, dynamic> json) {
    // Backend sends a plain 'YYYY-MM-DD' date (DATE(s.occurred_at) — see
    // saleRepository.cashierSalesByDay), which DateTime.parse reads as a
    // naive local date — consistent with how every other sale timestamp
    // in this app is treated (no UTC conversion involved, see
    // LocalDateRange's doc comment).
    return CashierDailyBreakdown(
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      summary: CashierReportSummary.fromJson(json),
    );
  }
}

/// The `cashier` profile object embedded in GET /reports/cashier-sales
/// (spec §11: cashier detail header) — id/name/email/role/active looked
/// up server-side, store-scoped (reportService.js#cashierSalesReport), so
/// this is never assembled from a client-side cashier list that could be
/// stale or belong to a different store.
class CashierProfile {
  final String id;
  final String name;
  final String? email;
  final String role;
  final bool isActive;

  const CashierProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
  });

  factory CashierProfile.fromJson(Map<String, dynamic> json) {
    return CashierProfile(
      id: '${json['id']}',
      name: '${json['name'] ?? '—'}',
      email: json['email'] as String?,
      role: '${json['role'] ?? ''}',
      isActive: json['is_active'] == true,
    );
  }
}

/// Full response of GET /reports/cashier-sales: the cashier's activity
/// over [period], used by both Day mode (no [days] breakdown requested)
/// and Month mode (`group_by=day`, so [days] is populated), and by the
/// Rapports cashier-detail drill-down (spec §11), which additionally
/// reads [cashier] and [paymentBreakdown] — both nullable so the older
/// Cashiers-screen call sites that don't need them keep working
/// unchanged.
class CashierSalesReport {
  final CashierReportSummary summary;
  final List<CashierDailyBreakdown> days;
  final CashierProfile? cashier;
  final List<PaymentBreakdownEntry> paymentBreakdown;

  const CashierSalesReport({
    required this.summary,
    this.days = const [],
    this.cashier,
    this.paymentBreakdown = const [],
  });

  factory CashierSalesReport.fromJson(Map<String, dynamic> json) {
    final summary = CashierReportSummary.fromJson(
      json['summary'] as Map<String, dynamic>? ?? const {},
    );
    final days = (json['days'] as List<dynamic>? ?? const [])
        .map((raw) => CashierDailyBreakdown.fromJson(raw as Map<String, dynamic>))
        .toList();
    final cashierJson = json['cashier'] as Map<String, dynamic>?;
    final paymentBreakdown = (json['payment_breakdown'] as List<dynamic>? ?? const [])
        .map((raw) => PaymentBreakdownEntry.fromJson(raw as Map<String, dynamic>))
        .toList();
    return CashierSalesReport(
      summary: summary,
      days: days,
      cashier: cashierJson != null ? CashierProfile.fromJson(cashierJson) : null,
      paymentBreakdown: paymentBreakdown,
    );
  }
}
