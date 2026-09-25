/// Models for the cashier's PERSONAL report — `GET /reports/my-sales` and
/// `GET /reports/my-orders` (see the backend's cashierReportService.js).
///
/// These are deliberately separate from [ReportOverview] (the admin report):
/// everything here is about ONE cashier — the signed-in one, as decided by
/// the server from the auth token. Nothing in these models carries a
/// cashier id that the client could change.
library my_report;

import '../../../sales/domain/entities/sale.dart';

double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
int _i(dynamic v) => (v is num) ? v.toInt() : (int.tryParse('${v ?? 0}') ?? 0);

/// Server timestamps are naive local 'YYYY-MM-DD HH:mm:ss' strings, which
/// [DateTime.tryParse] reads as local time — the same convention as
/// [Sale.occurredAt].
DateTime _t(dynamic v) => DateTime.tryParse('${v ?? ''}') ?? DateTime.now();
DateTime? _tn(dynamic v) => v == null ? null : DateTime.tryParse('$v');

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  return (raw as List<dynamic>? ?? const [])
      .map((e) => parse(e as Map<String, dynamic>))
      .toList();
}

/// One line of an order card ("Café Americain  x2  20 DH").
class MyOrderLine {
  final String productId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  const MyOrderLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory MyOrderLine.fromJson(Map<String, dynamic> j) => MyOrderLine(
        productId: '${j['product_id'] ?? ''}',
        name: '${j['name'] ?? 'Produit'}',
        quantity: _i(j['quantity']),
        unitPrice: _d(j['unit_price']),
        subtotal: _d(j['subtotal']),
      );
}

/// One order (sale) handled by the signed-in cashier, with its serving state.
class MyOrder {
  final String id;
  final String receiptNumber;
  final DateTime occurredAt;
  final double total;
  final double paidAmount;
  final SalePaymentStatus paymentStatus;
  final String? paymentMethod;
  final bool isServed;
  final DateTime? servedAt;
  final String? servedByName;
  final DateTime? receiptPrintedAt;
  final int receiptPrintCount;
  final int itemsCount;
  final List<MyOrderLine> items;

  const MyOrder({
    required this.id,
    required this.receiptNumber,
    required this.occurredAt,
    required this.total,
    required this.paidAmount,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.isServed,
    required this.servedAt,
    required this.servedByName,
    required this.receiptPrintedAt,
    required this.receiptPrintCount,
    required this.itemsCount,
    required this.items,
  });

  bool get isPaid => paymentStatus == SalePaymentStatus.paid;

  double get remaining {
    final r = total - paidAmount;
    return r < 0 ? 0 : r;
  }

  factory MyOrder.fromJson(Map<String, dynamic> j) => MyOrder(
        id: '${j['id'] ?? ''}',
        receiptNumber: '${j['receipt_number'] ?? ''}',
        occurredAt: _t(j['occurred_at']),
        total: _d(j['total']),
        paidAmount: _d(j['paid_amount']),
        paymentStatus: SalePaymentStatusX.fromApi(j['payment_status'] as String?),
        paymentMethod: j['payment_method'] as String?,
        isServed: j['is_served'] == true,
        servedAt: _tn(j['served_at']),
        servedByName: j['served_by_name'] as String?,
        receiptPrintedAt: _tn(j['receipt_printed_at']),
        receiptPrintCount: _i(j['receipt_print_count']),
        itemsCount: _i(j['items_count']),
        items: _list(j['items'], MyOrderLine.fromJson),
      );
}

/// One page of `GET /reports/my-orders`.
class MyOrdersPage {
  final List<MyOrder> items;
  final int total;
  final int page;
  final int pageSize;

  const MyOrdersPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  bool get hasMore => page * pageSize < total;

  factory MyOrdersPage.fromJson(Map<String, dynamic> j) => MyOrdersPage(
        items: _list(j['items'], MyOrder.fromJson),
        total: _i(j['total']),
        page: _i(j['page']) == 0 ? 1 : _i(j['page']),
        pageSize: _i(j['pageSize']) == 0 ? 50 : _i(j['pageSize']),
      );
}

class MyKpis {
  final double revenue;
  final int orderCount;
  final int itemsSold;
  final double averageTicket;
  final double collected;
  final double outstanding;

  const MyKpis({
    required this.revenue,
    required this.orderCount,
    required this.itemsSold,
    required this.averageTicket,
    required this.collected,
    required this.outstanding,
  });

  static const MyKpis zero = MyKpis(
    revenue: 0,
    orderCount: 0,
    itemsSold: 0,
    averageTicket: 0,
    collected: 0,
    outstanding: 0,
  );

  factory MyKpis.fromJson(Map<String, dynamic> j) => MyKpis(
        revenue: _d(j['revenue']),
        orderCount: _i(j['order_count']),
        itemsSold: _i(j['items_sold']),
        averageTicket: _d(j['average_ticket']),
        collected: _d(j['collected']),
        outstanding: _d(j['outstanding']),
      );
}

/// A product sold by THIS cashier in the period (never store-wide).
class MyProductLine {
  final String productId;
  final String name;
  final int quantity;
  final double revenue;

  const MyProductLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.revenue,
  });

  factory MyProductLine.fromJson(Map<String, dynamic> j) => MyProductLine(
        productId: '${j['product_id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        quantity: _i(j['quantity']),
        revenue: _d(j['revenue']),
      );
}

class MyPaymentMethod {
  final String method;
  final double amount;
  final int count;
  final double percent;

  const MyPaymentMethod({
    required this.method,
    required this.amount,
    required this.count,
    required this.percent,
  });

  factory MyPaymentMethod.fromJson(Map<String, dynamic> j) => MyPaymentMethod(
        method: '${j['method'] ?? ''}',
        amount: _d(j['amount']),
        count: _i(j['count']),
        percent: _d(j['percent']),
      );
}

class MyPayments {
  final List<MyPaymentMethod> methods;
  final double totalCollected;
  final double changeGiven;
  final double outstanding;
  final int unpaidCount;
  final double unpaidAmount;
  final int partialCount;
  final double partialRemaining;

  const MyPayments({
    required this.methods,
    required this.totalCollected,
    required this.changeGiven,
    required this.outstanding,
    required this.unpaidCount,
    required this.unpaidAmount,
    required this.partialCount,
    required this.partialRemaining,
  });

  static const MyPayments empty = MyPayments(
    methods: [],
    totalCollected: 0,
    changeGiven: 0,
    outstanding: 0,
    unpaidCount: 0,
    unpaidAmount: 0,
    partialCount: 0,
    partialRemaining: 0,
  );

  factory MyPayments.fromJson(Map<String, dynamic> j) {
    final unpaid = (j['unpaid'] as Map<String, dynamic>?) ?? const {};
    final partial = (j['partial'] as Map<String, dynamic>?) ?? const {};
    return MyPayments(
      methods: _list(j['methods'], MyPaymentMethod.fromJson),
      totalCollected: _d(j['total_collected']),
      changeGiven: _d(j['change_given']),
      outstanding: _d(j['outstanding']),
      unpaidCount: _i(unpaid['count']),
      unpaidAmount: _d(unpaid['amount']),
      partialCount: _i(partial['count']),
      partialRemaining: _d(partial['remaining']),
    );
  }
}

/// The cashier's personal report for one period — ONE server snapshot that
/// the screen AND the printed report both render.
class MyReport {
  final DateTime generatedAt;
  final String cashierId;
  final String cashierName;
  final String periodKey;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int days;
  final String storeName;
  final String? storeAddress;
  final String? storePhone;
  final MyKpis kpis;
  final MyPayments payments;

  /// Whole "à servir" backlog (any date) — informational.
  final int toServeTotal;
  final int servedInPeriod;
  final List<MyProductLine> products;

  /// Only present when requested for printing (`include_orders`).
  final List<MyOrder>? orders;
  final bool ordersTruncated;

  const MyReport({
    required this.generatedAt,
    required this.cashierId,
    required this.cashierName,
    required this.periodKey,
    required this.periodStart,
    required this.periodEnd,
    required this.days,
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    required this.kpis,
    required this.payments,
    required this.toServeTotal,
    required this.servedInPeriod,
    required this.products,
    required this.orders,
    required this.ordersTruncated,
  });

  /// Shown until a custom range has both dates.
  static final MyReport empty = MyReport(
    generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    cashierId: '',
    cashierName: '',
    periodKey: 'today',
    periodStart: DateTime.fromMillisecondsSinceEpoch(0),
    periodEnd: DateTime.fromMillisecondsSinceEpoch(0),
    days: 0,
    storeName: '',
    storeAddress: null,
    storePhone: null,
    kpis: MyKpis.zero,
    payments: MyPayments.empty,
    toServeTotal: 0,
    servedInPeriod: 0,
    products: const [],
    orders: null,
    ordersTruncated: false,
  );

  factory MyReport.fromJson(Map<String, dynamic> j) {
    final cashier = (j['cashier'] as Map<String, dynamic>?) ?? const {};
    final period = (j['period'] as Map<String, dynamic>?) ?? const {};
    final store = (j['store'] as Map<String, dynamic>?) ?? const {};
    final serving = (j['serving'] as Map<String, dynamic>?) ?? const {};
    final storeName = '${store['name'] ?? ''}'.trim();

    return MyReport(
      generatedAt: _t(j['generated_at']),
      cashierId: '${cashier['id'] ?? ''}',
      cashierName: '${cashier['name'] ?? ''}',
      periodKey: '${period['key'] ?? 'custom'}',
      periodStart: _t(period['start']),
      periodEnd: _t(period['end']),
      days: _i(period['days']),
      storeName: storeName.isEmpty ? 'STORE POS' : storeName,
      storeAddress: store['address'] as String?,
      storePhone: store['phone'] as String?,
      kpis: MyKpis.fromJson((j['kpis'] as Map<String, dynamic>?) ?? const {}),
      payments: MyPayments.fromJson((j['payments'] as Map<String, dynamic>?) ?? const {}),
      toServeTotal: _i(serving['to_serve_total']),
      servedInPeriod: _i(serving['served_in_period']),
      products: _list(j['products'], MyProductLine.fromJson),
      orders: j['orders'] == null ? null : _list(j['orders'], MyOrder.fromJson),
      ordersTruncated: j['orders_truncated'] == true,
    );
  }
}
