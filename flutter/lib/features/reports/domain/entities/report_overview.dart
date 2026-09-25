/// Models for `GET /reports/overview` (see the backend's
/// reportOverviewService.js) — the ONE payload the Rapports screen, the
/// PDF, the Excel/CSV export and the Print button all render. Because
/// they share this object, "dashboard = PDF = Excel" holds by construction.
library report_overview;

import '../../../sales/domain/entities/sale.dart';

double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
int _i(dynamic v) => (v is num) ? v.toInt() : (int.tryParse('${v ?? 0}') ?? 0);
DateTime _t(dynamic v) => DateTime.tryParse('${v ?? ''}') ?? DateTime.now();

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  return (raw as List<dynamic>? ?? const [])
      .map((e) => parse(e as Map<String, dynamic>))
      .toList();
}

class ReportPeriodInfo {
  final String key;
  final DateTime start;
  final DateTime end;
  final int days;

  const ReportPeriodInfo({
    required this.key,
    required this.start,
    required this.end,
    required this.days,
  });

  factory ReportPeriodInfo.fromJson(Map<String, dynamic> j) => ReportPeriodInfo(
        key: '${j['key'] ?? 'custom'}',
        start: _t(j['start']),
        end: _t(j['end']),
        days: _i(j['days']),
      );
}

class ReportStoreInfo {
  final String name;
  final String? address;
  final String? phone;

  const ReportStoreInfo({required this.name, this.address, this.phone});

  factory ReportStoreInfo.fromJson(Map<String, dynamic> j) => ReportStoreInfo(
        name: (j['name'] as String?)?.trim().isNotEmpty == true ? j['name'] as String : 'STORE POS',
        address: j['address'] as String?,
        phone: j['phone'] as String?,
      );
}

class ReportKpis {
  final double revenue;
  final int saleCount;
  final int itemsSold;
  final double averageTicket;
  final double expenses;
  final double estimatedResult;

  const ReportKpis({
    required this.revenue,
    required this.saleCount,
    required this.itemsSold,
    required this.averageTicket,
    required this.expenses,
    required this.estimatedResult,
  });

  factory ReportKpis.fromJson(Map<String, dynamic> j) => ReportKpis(
        revenue: _d(j['revenue']),
        saleCount: _i(j['sale_count']),
        itemsSold: _i(j['items_sold']),
        averageTicket: _d(j['average_ticket']),
        expenses: _d(j['expenses']),
        estimatedResult: _d(j['estimated_result']),
      );
}

class ReportTax {
  final double total;
  final double revenueExTax;
  final double discountTotal;

  const ReportTax({required this.total, required this.revenueExTax, required this.discountTotal});

  factory ReportTax.fromJson(Map<String, dynamic> j) => ReportTax(
        total: _d(j['total']),
        revenueExTax: _d(j['revenue_ex_tax']),
        discountTotal: _d(j['discount_total']),
      );
}

class ReportBucket {
  final DateTime start;
  final double revenue;
  final int saleCount;

  const ReportBucket({required this.start, required this.revenue, required this.saleCount});

  factory ReportBucket.fromJson(Map<String, dynamic> j) => ReportBucket(
        start: _t(j['bucket_start']),
        revenue: _d(j['revenue']),
        saleCount: _i(j['sale_count']),
      );
}

/// `granularity` is 'hour' | 'day' | 'month'.
class ReportRevenueSeries {
  final String granularity;
  final List<ReportBucket> buckets;

  const ReportRevenueSeries({required this.granularity, required this.buckets});

  bool get hasData => buckets.any((b) => b.saleCount > 0 || b.revenue > 0);

  factory ReportRevenueSeries.fromJson(Map<String, dynamic> j) => ReportRevenueSeries(
        granularity: '${j['granularity'] ?? 'day'}',
        buckets: _list(j['buckets'], ReportBucket.fromJson),
      );
}

class HourRow {
  final int hour;
  final String label;
  final int orders;
  final double revenue;

  const HourRow({required this.hour, required this.label, required this.orders, required this.revenue});

  factory HourRow.fromJson(Map<String, dynamic> j) => HourRow(
        hour: _i(j['hour']),
        label: '${j['label'] ?? ''}',
        orders: _i(j['orders']),
        revenue: _d(j['revenue']),
      );
}

class OrdersByHour {
  /// Always the 24 hours of the day, zero-filled.
  final List<HourRow> hours;
  final int totalOrders;
  final double totalRevenue;

  const OrdersByHour({required this.hours, required this.totalOrders, required this.totalRevenue});

  /// Rows from the first to the last hour that had an order (quiet hours
  /// in between are kept as zero rows). Empty when there was no order.
  List<HourRow> get activeRange {
    final active = hours.where((h) => h.orders > 0).toList();
    if (active.isEmpty) return const [];
    final first = active.first.hour;
    final last = active.last.hour;
    return hours.where((h) => h.hour >= first && h.hour <= last).toList();
  }

  factory OrdersByHour.fromJson(Map<String, dynamic> j) {
    final total = j['total'] as Map<String, dynamic>? ?? const {};
    return OrdersByHour(
      hours: _list(j['hours'], HourRow.fromJson),
      totalOrders: _i(total['orders']),
      totalRevenue: _d(total['revenue']),
    );
  }
}

class PaymentMethodRow {
  final String method;
  final double amount;
  final int count;
  final double percent;
  final double inDrawer;

  const PaymentMethodRow({
    required this.method,
    required this.amount,
    required this.count,
    required this.percent,
    required this.inDrawer,
  });

  factory PaymentMethodRow.fromJson(Map<String, dynamic> j) => PaymentMethodRow(
        method: '${j['method'] ?? ''}',
        amount: _d(j['amount']),
        count: _i(j['count']),
        percent: _d(j['percent']),
        inDrawer: _d(j['in_drawer']),
      );
}

class ReportPayments {
  final List<PaymentMethodRow> methods;
  final double totalCollected;
  final int transactions;
  final double inDrawer;
  final double changeGiven;
  final double outstanding;

  const ReportPayments({
    required this.methods,
    required this.totalCollected,
    required this.transactions,
    required this.inDrawer,
    required this.changeGiven,
    required this.outstanding,
  });

  factory ReportPayments.fromJson(Map<String, dynamic> j) => ReportPayments(
        methods: _list(j['methods'], PaymentMethodRow.fromJson),
        totalCollected: _d(j['total_collected']),
        transactions: _i(j['transactions']),
        inDrawer: _d(j['in_drawer']),
        changeGiven: _d(j['change_given']),
        outstanding: _d(j['outstanding']),
      );
}

class ReportCashierRow {
  final String id;
  final String name;
  final int saleCount;
  final int itemsSold;
  final double revenue;
  final double averageTicket;

  const ReportCashierRow({
    required this.id,
    required this.name,
    required this.saleCount,
    required this.itemsSold,
    required this.revenue,
    required this.averageTicket,
  });

  factory ReportCashierRow.fromJson(Map<String, dynamic> j) => ReportCashierRow(
        id: '${j['cashier_id'] ?? ''}',
        name: '${j['name'] ?? '—'}',
        saleCount: _i(j['sale_count']),
        itemsSold: _i(j['items_sold']),
        revenue: _d(j['revenue']),
        averageTicket: _d(j['average_ticket']),
      );
}

class ReportProductRow {
  final String name;
  final int quantity;
  final double revenue;

  const ReportProductRow({required this.name, required this.quantity, required this.revenue});

  factory ReportProductRow.fromJson(Map<String, dynamic> j) => ReportProductRow(
        name: '${j['name'] ?? '—'}',
        quantity: _i(j['quantity']),
        revenue: _d(j['revenue']),
      );
}

class ReportExpenseRow {
  final String category;
  final double amount;
  final int count;
  final double percent;

  const ReportExpenseRow({
    required this.category,
    required this.amount,
    required this.count,
    required this.percent,
  });

  factory ReportExpenseRow.fromJson(Map<String, dynamic> j) => ReportExpenseRow(
        category: '${j['category'] ?? '—'}',
        amount: _d(j['amount']),
        count: _i(j['count']),
        percent: _d(j['percent']),
      );
}

class ReportExpenses {
  final double total;
  final int count;
  final List<ReportExpenseRow> byCategory;

  const ReportExpenses({required this.total, required this.count, required this.byCategory});

  factory ReportExpenses.fromJson(Map<String, dynamic> j) => ReportExpenses(
        total: _d(j['total']),
        count: _i(j['count']),
        byCategory: _list(j['by_category'], ReportExpenseRow.fromJson),
      );
}

class StockAlertItem {
  final String kind; // 'product' | 'ingredient'
  final String name;
  final double quantity;
  final bool outOfStock;
  final String? unit;

  const StockAlertItem({
    required this.kind,
    required this.name,
    required this.quantity,
    required this.outOfStock,
    this.unit,
  });

  factory StockAlertItem.fromJson(Map<String, dynamic> j) => StockAlertItem(
        kind: '${j['kind'] ?? 'product'}',
        name: '${j['name'] ?? '—'}',
        quantity: _d(j['quantity']),
        outOfStock: j['status'] == 'rupture',
        unit: j['unit'] as String?,
      );
}

class ReportAlerts {
  /// False when the server could not read stock (the rest of the report
  /// is still valid) — the panel then says so instead of showing zeros.
  final bool stockAvailable;
  final int outOfStock;
  final int lowStock;
  final List<StockAlertItem> stockItems;
  final int unpaidCount;
  final double unpaidAmount;
  final int partialCount;
  final double partialRemaining;
  final int cancelled;
  final int refunded;

  const ReportAlerts({
    required this.stockAvailable,
    required this.outOfStock,
    required this.lowStock,
    required this.stockItems,
    required this.unpaidCount,
    required this.unpaidAmount,
    required this.partialCount,
    required this.partialRemaining,
    required this.cancelled,
    required this.refunded,
  });

  factory ReportAlerts.fromJson(Map<String, dynamic> j) {
    final stock = j['stock'] as Map<String, dynamic>? ?? const {};
    final unpaid = j['unpaid'] as Map<String, dynamic>? ?? const {};
    final partial = j['partial'] as Map<String, dynamic>? ?? const {};
    return ReportAlerts(
      stockAvailable: j['stock'] != null,
      outOfStock: _i(stock['out_of_stock']),
      lowStock: _i(stock['low_stock']),
      stockItems: _list(stock['items'], StockAlertItem.fromJson),
      unpaidCount: _i(unpaid['count']),
      unpaidAmount: _d(unpaid['amount']),
      partialCount: _i(partial['count']),
      partialRemaining: _d(partial['remaining']),
      cancelled: _i(j['cancelled']),
      refunded: _i(j['refunded']),
    );
  }
}

/// One sale line of the "Ventes récentes" panel and of the PDF/Excel
/// "Ventes" list.
class ReportSaleRow {
  final Map<String, dynamic> raw;
  final String id;
  final DateTime occurredAt;
  final String cashierName;
  final int itemsCount;
  final double total;
  final double paidAmount;
  final String? paymentMethod;
  final String paymentStatus; // PAID | PENDING | PARTIALLY_PAID | REFUNDED
  final String saleStatus; // COMPLETED | CANCELLED | REFUNDED

  const ReportSaleRow({
    required this.raw,
    required this.id,
    required this.occurredAt,
    required this.cashierName,
    required this.itemsCount,
    required this.total,
    required this.paidAmount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.saleStatus,
  });

  bool get isCompleted => saleStatus == 'COMPLETED';

  /// Same ticket number the receipt and Sales screen show.
  String get ticket => id.isEmpty ? 'N/A' : (id.length > 8 ? id.substring(0, 8) : id);

  /// Light [Sale] (no line items) to open the existing SaleDetailDialog,
  /// which loads the full sale itself.
  Sale toSale() => Sale.fromJson(raw);

  factory ReportSaleRow.fromJson(Map<String, dynamic> j) => ReportSaleRow(
        raw: j,
        id: '${j['id'] ?? ''}',
        occurredAt: _t(j['occurred_at']),
        cashierName: '${j['cashier_name'] ?? '—'}',
        itemsCount: _i(j['items_count']),
        total: _d(j['total']),
        paidAmount: _d(j['paid_amount']),
        paymentMethod: j['payment_method'] as String?,
        paymentStatus: '${j['payment_status'] ?? 'PENDING'}',
        saleStatus: '${j['sale_status'] ?? 'COMPLETED'}',
      );
}

class ReportOverview {
  final DateTime generatedAt;
  final ReportPeriodInfo period;
  final ReportStoreInfo store;
  final ReportKpis kpis;
  final ReportTax tax;
  final ReportRevenueSeries revenueSeries;
  final OrdersByHour ordersByHour;
  final ReportPayments payments;
  final List<ReportCashierRow> cashiers;
  final List<ReportProductRow> topProducts;
  final ReportExpenses expenses;
  final ReportAlerts alerts;
  final List<ReportSaleRow> recentSales;

  /// Only present when the payload was requested with `include_sales`
  /// (exports); null on the dashboard's own requests.
  final List<ReportSaleRow>? sales;
  final bool salesTruncated;
  final bool integrityOk;
  final List<String> integrityFailed;

  const ReportOverview({
    required this.generatedAt,
    required this.period,
    required this.store,
    required this.kpis,
    required this.tax,
    required this.revenueSeries,
    required this.ordersByHour,
    required this.payments,
    required this.cashiers,
    required this.topProducts,
    required this.expenses,
    required this.alerts,
    required this.recentSales,
    required this.sales,
    required this.salesTruncated,
    required this.integrityOk,
    required this.integrityFailed,
  });

  bool get hasSales => kpis.saleCount > 0;

  factory ReportOverview.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> obj(String key) => j[key] as Map<String, dynamic>? ?? const {};
    final integrity = obj('integrity');
    final salesRaw = j['sales'];
    return ReportOverview(
      generatedAt: _t(j['generated_at']),
      period: ReportPeriodInfo.fromJson(obj('period')),
      store: ReportStoreInfo.fromJson(obj('store')),
      kpis: ReportKpis.fromJson(obj('kpis')),
      tax: ReportTax.fromJson(obj('tax')),
      revenueSeries: ReportRevenueSeries.fromJson(obj('revenue_series')),
      ordersByHour: OrdersByHour.fromJson(obj('orders_by_hour')),
      payments: ReportPayments.fromJson(obj('payments')),
      cashiers: _list(j['cashiers'], ReportCashierRow.fromJson),
      topProducts: _list(j['top_products'], ReportProductRow.fromJson),
      expenses: ReportExpenses.fromJson(obj('expenses')),
      alerts: ReportAlerts.fromJson(obj('alerts')),
      recentSales: _list(j['recent_sales'], ReportSaleRow.fromJson),
      sales: salesRaw == null ? null : _list(salesRaw, ReportSaleRow.fromJson),
      salesTruncated: j['sales_truncated'] == true,
      integrityOk: integrity['ok'] != false,
      integrityFailed: (integrity['failed'] as List<dynamic>? ?? const []).map((e) => '$e').toList(),
    );
  }
}
