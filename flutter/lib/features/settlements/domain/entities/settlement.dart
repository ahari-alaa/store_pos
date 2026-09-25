/// Models for the cashier work-payment / settlement system
/// (`/api/cashier-settlements/*` and `/api/admin/cashier-settlements/*` —
/// see the backend's cashierSettlementService.js).
///
/// VERY IMPORTANT DISTINCTION, carried through every model here: this is
/// the cashier's WORK payment (how many orders he handled, so the manager
/// can pay him), never the CUSTOMER's payment for an order
/// ([Sale.paymentStatus] / [MyOrder.paymentStatus]). A [SettlementOrder]
/// keeps its own `paymentStatus` alongside `settlementId` precisely so the
/// UI can show both, clearly separated, on the same row.
library settlement;

double _d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
int _i(dynamic v) => (v is num) ? v.toInt() : (int.tryParse('${v ?? 0}') ?? 0);
DateTime _t(dynamic v) => DateTime.tryParse('${v ?? ''}') ?? DateTime.now();
DateTime? _tn(dynamic v) => v == null ? null : DateTime.tryParse('$v');

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) {
  return (raw as List<dynamic>? ?? const [])
      .map((e) => parse(e as Map<String, dynamic>))
      .toList();
}

/// One order line as it appears inside a settlement (its own detail, and
/// the printed justificatif) — a summary row, not the full receipt. To see
/// products/quantities, open the order itself (spec §27 — this system
/// never removes that).
class SettlementOrder {
  final String id;
  final String receiptNumber;
  final DateTime occurredAt;
  final double total;
  final String paymentStatus;

  const SettlementOrder({
    required this.id,
    required this.receiptNumber,
    required this.occurredAt,
    required this.total,
    required this.paymentStatus,
  });

  factory SettlementOrder.fromJson(Map<String, dynamic> j) => SettlementOrder(
        id: '${j['id'] ?? ''}',
        receiptNumber: '${j['receipt_number'] ?? ''}',
        occurredAt: _t(j['occurred_at']),
        total: _d(j['total']),
        paymentStatus: '${j['payment_status'] ?? ''}',
      );
}

/// `PRINTED` (à payer) | `PAID` | `CANCELLED`. Kept as the raw backend
/// value (not an enum) so an unrecognised future value degrades to
/// "unknown" instead of throwing — same policy as [StatusBadge].
class CashierSettlement {
  final String id;
  final String settlementNumber;
  final String cashierId;
  final String cashierName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int orderCount;
  final double totalAmount;
  final String status;
  final DateTime createdAt;
  final DateTime printedAt;
  final DateTime? paidAt;
  final String? paidByName;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final int reprintCount;
  final DateTime? lastReprintedAt;
  final String? lastReprintedByName;
  final List<SettlementOrder>? orders;

  const CashierSettlement({
    required this.id,
    required this.settlementNumber,
    required this.cashierId,
    required this.cashierName,
    required this.periodStart,
    required this.periodEnd,
    required this.orderCount,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.printedAt,
    required this.paidAt,
    required this.paidByName,
    required this.cancelledAt,
    required this.cancelReason,
    required this.reprintCount,
    required this.lastReprintedAt,
    required this.lastReprintedByName,
    required this.orders,
  });

  bool get isPrinted => status == 'PRINTED'; // "à payer"
  bool get isPaid => status == 'PAID';
  bool get isCancelled => status == 'CANCELLED';

  factory CashierSettlement.fromJson(Map<String, dynamic> j) {
    final period = (j['period'] as Map<String, dynamic>?) ?? const {};
    return CashierSettlement(
      id: '${j['id'] ?? ''}',
      settlementNumber: '${j['settlement_number'] ?? ''}',
      cashierId: '${j['cashier_id'] ?? ''}',
      cashierName: '${j['cashier_name'] ?? ''}',
      periodStart: _t(period['start']),
      periodEnd: _t(period['end']),
      orderCount: _i(j['order_count']),
      totalAmount: _d(j['total_amount']),
      status: '${j['status'] ?? ''}',
      createdAt: _t(j['created_at']),
      printedAt: _t(j['printed_at']),
      paidAt: _tn(j['paid_at']),
      paidByName: j['paid_by_name'] as String?,
      cancelledAt: _tn(j['cancelled_at']),
      cancelReason: j['cancel_reason'] as String?,
      reprintCount: _i(j['reprint_count']),
      lastReprintedAt: _tn(j['last_reprinted_at']),
      lastReprintedByName: j['last_reprinted_by_name'] as String?,
      orders: j['orders'] == null ? null : _list(j['orders'], SettlementOrder.fromJson),
    );
  }
}

/// `GET /cashier-settlements/eligible-orders` — "COMMANDES DISPONIBLES
/// POUR JUSTIFICATIF" (spec §4/§5): the cashier's own completed orders not
/// yet attached to any settlement, with their running total.
class EligibleOrders {
  final List<SettlementOrder> items;
  final int count;
  final double totalAmount;

  const EligibleOrders({required this.items, required this.count, required this.totalAmount});

  static const EligibleOrders empty = EligibleOrders(items: [], count: 0, totalAmount: 0);

  factory EligibleOrders.fromJson(Map<String, dynamic> j) => EligibleOrders(
        items: _list(j['items'], SettlementOrder.fromJson),
        count: _i(j['count']),
        totalAmount: _d(j['total_amount']),
      );
}

/// `GET /cashier-settlements/my-summary` — the Rapport KPI header (spec
/// §18/§28): Commandes réalisées / déjà justifiées / disponibles, à payer /
/// déjà payé.
class SettlementSummary {
  final int ordersDone;
  final int ordersAvailable;
  final int ordersJustified;
  final double justifiedRevenue;
  final int settlementCount;
  final double toPay;
  final double alreadyPaid;

  const SettlementSummary({
    required this.ordersDone,
    required this.ordersAvailable,
    required this.ordersJustified,
    required this.justifiedRevenue,
    required this.settlementCount,
    required this.toPay,
    required this.alreadyPaid,
  });

  static const SettlementSummary zero = SettlementSummary(
    ordersDone: 0,
    ordersAvailable: 0,
    ordersJustified: 0,
    justifiedRevenue: 0,
    settlementCount: 0,
    toPay: 0,
    alreadyPaid: 0,
  );

  factory SettlementSummary.fromJson(Map<String, dynamic> j) => SettlementSummary(
        ordersDone: _i(j['orders_done']),
        ordersAvailable: _i(j['orders_available']),
        ordersJustified: _i(j['orders_justified']),
        justifiedRevenue: _d(j['justified_revenue']),
        settlementCount: _i(j['settlement_count']),
        toPay: _d(j['to_pay']),
        alreadyPaid: _d(j['already_paid']),
      );
}

/// One page of `GET /cashier-settlements/my` or `GET
/// /admin/cashier-settlements`.
class SettlementsPage {
  final List<CashierSettlement> items;
  final int total;

  const SettlementsPage({required this.items, required this.total});

  static const SettlementsPage empty = SettlementsPage(items: [], total: 0);

  factory SettlementsPage.fromJson(Map<String, dynamic> j) => SettlementsPage(
        items: _list(j['items'], CashierSettlement.fromJson),
        total: _i(j['total']),
      );
}
