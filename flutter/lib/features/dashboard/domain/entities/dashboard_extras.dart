/// Extra dashboard models added alongside the existing [DashboardSummary]
/// (today-vs-yesterday tiles + 7-day chart) — these back the new
/// period selector, "Meilleur caissier", "Statut des ventes",
/// switchable revenue chart and "Ventes récentes" sections.
///
/// Mirrors the payloads from the new `/reports/dashboard-*` endpoints
/// (see store_pos_backend/src/services/reportService.js).
library dashboard_extras;

/// Aujourd'hui / Cette semaine / Ce mois — matches the `period` query
/// param accepted by every `/reports/dashboard-*` endpoint.
enum DashboardPeriod { today, week, month }

extension DashboardPeriodX on DashboardPeriod {
  /// Value sent to the backend.
  String get apiValue {
    switch (this) {
      case DashboardPeriod.today:
        return 'today';
      case DashboardPeriod.week:
        return 'week';
      case DashboardPeriod.month:
        return 'month';
    }
  }

  String labelFr() {
    switch (this) {
      case DashboardPeriod.today:
        return "Aujourd'hui";
      case DashboardPeriod.week:
        return 'Cette semaine';
      case DashboardPeriod.month:
        return 'Ce mois';
    }
  }

  String labelAr() {
    switch (this) {
      case DashboardPeriod.today:
        return 'اليوم';
      case DashboardPeriod.week:
        return 'هذا الأسبوع';
      case DashboardPeriod.month:
        return 'هذا الشهر';
    }
  }
}

/// Jour / Semaine / Mois toggle for the revenue bar chart.
enum RevenueGranularity { day, week, month }

extension RevenueGranularityX on RevenueGranularity {
  String get apiValue {
    switch (this) {
      case RevenueGranularity.day:
        return 'day';
      case RevenueGranularity.week:
        return 'week';
      case RevenueGranularity.month:
        return 'month';
    }
  }

  String labelFr() {
    switch (this) {
      case RevenueGranularity.day:
        return 'Jour';
      case RevenueGranularity.week:
        return 'Semaine';
      case RevenueGranularity.month:
        return 'Mois';
    }
  }

  String labelAr() {
    switch (this) {
      case RevenueGranularity.day:
        return 'يوم';
      case RevenueGranularity.week:
        return 'أسبوع';
      case RevenueGranularity.month:
        return 'شهر';
    }
  }
}

/// GET /reports/dashboard-overview?period=
class DashboardOverview {
  final double totalRevenue;
  final int saleCount;
  final int itemsSold;
  final double averageSale;

  const DashboardOverview({
    required this.totalRevenue,
    required this.saleCount,
    required this.itemsSold,
    required this.averageSale,
  });

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    return DashboardOverview(
      totalRevenue: double.tryParse('${json['total_revenue'] ?? 0}') ?? 0,
      saleCount: (json['sale_count'] as num?)?.toInt() ?? 0,
      itemsSold: (json['items_sold'] as num?)?.toInt() ?? 0,
      averageSale: double.tryParse('${json['average_sale'] ?? 0}') ?? 0,
    );
  }

  static const empty = DashboardOverview(
    totalRevenue: 0,
    saleCount: 0,
    itemsSold: 0,
    averageSale: 0,
  );
}

/// One row of GET /reports/dashboard-cashiers?period=
class CashierRankingEntry {
  final String cashierId;
  final String cashierName;
  final String role;
  final int saleCount;
  final int itemsSold;
  final double totalSales;
  final double averageSale;

  const CashierRankingEntry({
    required this.cashierId,
    required this.cashierName,
    required this.role,
    required this.saleCount,
    required this.itemsSold,
    required this.totalSales,
    required this.averageSale,
  });

  factory CashierRankingEntry.fromJson(Map<String, dynamic> json) {
    return CashierRankingEntry(
      cashierId: '${json['cashier_id']}',
      cashierName: '${json['cashier_name'] ?? '—'}',
      role: '${json['role'] ?? ''}',
      saleCount: (json['sale_count'] as num?)?.toInt() ?? 0,
      itemsSold: (json['items_sold'] as num?)?.toInt() ?? 0,
      totalSales: double.tryParse('${json['total_sales'] ?? 0}') ?? 0,
      averageSale: double.tryParse('${json['average_sale'] ?? 0}') ?? 0,
    );
  }
}

/// One row of GET /reports/dashboard-articles?period=&limit=
class ArticleSoldEntry {
  final String productId;
  final String name;
  final int quantitySold;
  final double revenue;

  const ArticleSoldEntry({
    required this.productId,
    required this.name,
    required this.quantitySold,
    required this.revenue,
  });

  factory ArticleSoldEntry.fromJson(Map<String, dynamic> json) {
    return ArticleSoldEntry(
      productId: '${json['product_id']}',
      name: '${json['name'] ?? '—'}',
      quantitySold: (json['quantity_sold'] as num?)?.toInt() ?? 0,
      revenue: double.tryParse('${json['revenue'] ?? 0}') ?? 0,
    );
  }
}

/// GET /reports/dashboard-sales-status?period=
class SalesStatusEntry {
  final String status; // COMPLETED | CANCELLED | REFUNDED
  final int count;

  const SalesStatusEntry({required this.status, required this.count});

  factory SalesStatusEntry.fromJson(Map<String, dynamic> json) {
    return SalesStatusEntry(
      status: '${json['status']}',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  String labelFr() {
    switch (status) {
      case 'COMPLETED':
        return 'Terminées';
      case 'CANCELLED':
        return 'Annulées';
      case 'REFUNDED':
        return 'Remboursées';
      default:
        return status;
    }
  }

  String labelAr() {
    switch (status) {
      case 'COMPLETED':
        return 'مكتملة';
      case 'CANCELLED':
        return 'ملغاة';
      case 'REFUNDED':
        return 'مسترجعة';
      default:
        return status;
    }
  }
}

/// One bucket of GET /reports/dashboard-revenue?granularity=
class RevenueBucket {
  final DateTime bucketStart;
  final double revenue;

  /// Number of completed sales in this bucket. Only present when the
  /// backend was given a `period` (Rapports' auto-granularity path —
  /// see reportService.js#revenueSeriesForRange); the Dashboard's legacy
  /// fixed-window buckets don't compute it, so it's nullable rather than
  /// defaulting to a misleading 0.
  final int? saleCount;

  const RevenueBucket({required this.bucketStart, required this.revenue, this.saleCount});

  factory RevenueBucket.fromJson(Map<String, dynamic> json) {
    return RevenueBucket(
      bucketStart: DateTime.tryParse('${json['bucket_start']}') ?? DateTime.now(),
      revenue: double.tryParse('${json['revenue'] ?? 0}') ?? 0,
      saleCount: (json['sale_count'] as num?)?.toInt(),
    );
  }
}

/// One row of GET /reports/dashboard-recent-sales
class RecentSale {
  final String id;
  final double total;
  final String saleStatus;
  final String paymentStatus;
  final DateTime occurredAt;
  final String cashierName;
  final String? paymentMethod;

  const RecentSale({
    required this.id,
    required this.total,
    required this.saleStatus,
    required this.paymentStatus,
    required this.occurredAt,
    required this.cashierName,
    this.paymentMethod,
  });

  /// Short reference shown instead of the full UUID (e.g. "#3F2A").
  String get reference => '#${id.length >= 4 ? id.substring(0, 4).toUpperCase() : id}';

  factory RecentSale.fromJson(Map<String, dynamic> json) {
    return RecentSale(
      id: '${json['id']}',
      total: double.tryParse('${json['total'] ?? 0}') ?? 0,
      saleStatus: '${json['sale_status']}',
      paymentStatus: '${json['payment_status']}',
      occurredAt: DateTime.tryParse('${json['occurred_at']}') ?? DateTime.now(),
      cashierName: '${json['cashier_name'] ?? '—'}',
      paymentMethod: json['payment_method'] as String?,
    );
  }
}
