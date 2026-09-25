import '../../../pos/domain/entities/payment_method.dart';
import '../../../pos/presentation/providers/receipt_data.dart';

/// Mirrors `sales.payment_status` (see
/// store_pos_backend/migrations/001_init.sql). `pending` is what an
/// unpaid sale created via "Give receipt without paying" starts as (Sales
/// spec §2/§3) — the UI-facing label for it is always "NOT PAID"
/// ([SalePaymentStatusX.label]), never the raw enum name, per spec §4/§10
/// ("the UI and receipt must display only NOT PAID", not "PENDING").
enum SalePaymentStatus { pending, partiallyPaid, paid, refunded }

extension SalePaymentStatusX on SalePaymentStatus {
  static SalePaymentStatus fromApi(String? raw) {
    switch (raw) {
      case 'PAID':
        return SalePaymentStatus.paid;
      case 'PARTIALLY_PAID':
        return SalePaymentStatus.partiallyPaid;
      case 'REFUNDED':
        return SalePaymentStatus.refunded;
      case 'PENDING':
      default:
        return SalePaymentStatus.pending;
    }
  }

  /// User-facing label. Deliberately "NOT PAID" (never "PENDING" or
  /// "PAYMENTPENDING") — spec §4/§10/§18.
  String get label {
    switch (this) {
      case SalePaymentStatus.paid:
        return 'PAID';
      case SalePaymentStatus.partiallyPaid:
        return 'PARTIALLY PAID';
      case SalePaymentStatus.refunded:
        return 'REFUNDED';
      case SalePaymentStatus.pending:
        return 'NOT PAID';
    }
  }
}

/// One line item on a sale, as returned by GET /sales/:id or embedded in
/// GET /sales's list items.
class SaleLineItem {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  const SaleLineItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory SaleLineItem.fromJson(Map<String, dynamic> json) {
    return SaleLineItem(
      productId: json['product_id'] as String? ?? '',
      // `product_name` comes from the LEFT JOIN in saleRepository — falls
      // back to a generic label if the product was removed since.
      productName: (json['product_name'] as String?) ?? 'Product',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: double.tryParse('${json['unit_price']}') ?? 0,
      subtotal: double.tryParse('${json['subtotal']}') ?? 0,
    );
  }
}

/// One payment row against a sale (a sale can have more than one — see
/// `payments` table). [amount] follows the same convention used
/// throughout this app (payment_provider.dart / cart_panel.dart): for a
/// CASH payment it's the raw amount the customer physically handed over
/// (change is derived from it, not stored separately).
class SalePaymentRecord {
  final String id;
  final double amount;
  final PaymentMethod method;
  final DateTime createdAt;

  const SalePaymentRecord({
    required this.id,
    required this.amount,
    required this.method,
    required this.createdAt,
  });

  factory SalePaymentRecord.fromJson(Map<String, dynamic> json) {
    return SalePaymentRecord(
      id: json['id'] as String? ?? '',
      amount: double.tryParse('${json['amount']}') ?? 0,
      method: _methodFromApi(json['payment_method'] as String?),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  static PaymentMethod _methodFromApi(String? raw) {
    switch (raw) {
      case 'CARD':
        return PaymentMethod.card;
      case 'TRANSFER':
        return PaymentMethod.transfer;
      case 'CASH':
      default:
        return PaymentMethod.cash;
    }
  }
}

/// A full sale/receipt, as shown on the Sales screen (spec §1) and its
/// detail view (spec §14). Mirrors the `sales` row + its `items` +
/// `payments` (see saleRepository.findById / .list).
class Sale {
  final String id;
  final SalePaymentStatus status;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;

  /// The sale's ORIGINAL creation time. Never changes once the sale is
  /// paid later — spec §8 ("sale time must not change").
  final DateTime occurredAt;
  final String? cashierId;
  final String? cashierName;
  final String? note;
  final List<SaleLineItem> items;
  final List<SalePaymentRecord> payments;

  /// Raw `payment_method` string the backend now derives directly on
  /// GET /sales list rows (saleRepository.list — 'MIXED' for more than
  /// one distinct method, null for an unpaid sale). [items]/[payments]
  /// are empty on a list row (only GET /sales/:id embeds them), so
  /// [primaryPaymentMethod] can't be computed there — this is the only
  /// payment-method signal a *list* row carries. Used by the Rapports
  /// "Transactions récentes" table (spec §15), which reuses this same
  /// GET /sales list rather than fetching each sale's full detail just
  /// to show a payment-method column.
  final String? rawPaymentMethod;

  /// Serving metadata (backend migration 012). Purely informational: it
  /// never changes the sale's totals, payment status or any report.
  /// [servedAt] == null means "à servir". [servedByName] is null for a sale
  /// served before this workflow existed (legacy) or not served yet.
  final DateTime? servedAt;
  final String? servedByName;
  final DateTime? receiptPrintedAt;
  final int receiptPrintCount;

  const Sale({
    required this.id,
    required this.status,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.occurredAt,
    required this.cashierId,
    required this.cashierName,
    required this.note,
    required this.items,
    required this.payments,
    this.rawPaymentMethod,
    this.servedAt,
    this.servedByName,
    this.receiptPrintedAt,
    this.receiptPrintCount = 0,
  });

  bool get isServed => servedAt != null;

  /// Short receipt number derived from the sale id — same helper used by
  /// the POS "sale completed" / "receipt without paying" flows, so the
  /// number shown here always matches what was printed at the register.
  String get receiptNumber => receiptNumberForSaleId(id);

  bool get isPaid => status == SalePaymentStatus.paid;

  /// Only a sale that isn't already fully paid (or refunded) can be paid —
  /// spec §13 ("Do not show 'Pay' for already paid sales").
  bool get canPay => status == SalePaymentStatus.pending || status == SalePaymentStatus.partiallyPaid;

  /// Raw sum of every payment row. For a sale that was paid with cash
  /// overpayment (e.g. total 150, customer handed 200), this is 200, not
  /// 150 — see the class doc on [SalePaymentRecord.amount].
  double get rawPaidAmount => payments.fold(0.0, (sum, p) => sum + p.amount);

  /// Amount actually applied toward the sale total (never more than
  /// [total]) — this is the "Paid" figure shown on the Sales screen (spec
  /// §7: "Paid = 150 DH" even though "Amount received = 200 DH").
  double get appliedAmount => rawPaidAmount >= total ? total : rawPaidAmount;

  /// What the customer still owes.
  double get remaining {
    final r = total - appliedAmount;
    return r < 0 ? 0 : r;
  }

  /// Sum of CASH payments only — "Cash received" on the detail view
  /// (spec §14).
  double get cashReceived => payments
      .where((p) => p.method == PaymentMethod.cash)
      .fold(0.0, (sum, p) => sum + p.amount);

  /// Change given back, derived the same way the POS register itself
  /// computes it (amount handed over minus the total) — only meaningful
  /// once the sale is fully paid.
  double get change {
    if (!isPaid) return 0;
    final c = rawPaidAmount - total;
    return c < 0 ? 0 : c;
  }

  /// When the sale was (fully) paid — the most recent payment's
  /// timestamp. Null while still NOT PAID. Kept separate from
  /// [occurredAt], which never changes (spec §8).
  DateTime? get paidAt {
    if (payments.isEmpty) return null;
    return payments.map((p) => p.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// The method of the payment that (most recently) moved this sale
  /// toward/into PAID — shown as "Payment method" on the detail view.
  PaymentMethod? get primaryPaymentMethod {
    if (payments.isEmpty) return null;
    return payments.last.method;
  }

  factory Sale.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const [])
        .map((raw) => SaleLineItem.fromJson(raw as Map<String, dynamic>))
        .toList();
    final payments = (json['payments'] as List<dynamic>? ?? const [])
        .map((raw) => SalePaymentRecord.fromJson(raw as Map<String, dynamic>))
        .toList();

    return Sale(
      id: json['id'] as String? ?? '',
      status: SalePaymentStatusX.fromApi(json['payment_status'] as String?),
      subtotal: double.tryParse('${json['subtotal']}') ?? 0,
      discountTotal: double.tryParse('${json['discount_total']}') ?? 0,
      taxTotal: double.tryParse('${json['tax_total']}') ?? 0,
      total: double.tryParse('${json['total']}') ?? 0,
      occurredAt: DateTime.tryParse(json['occurred_at'] as String? ?? '') ?? DateTime.now(),
      cashierId: json['user_id'] as String?,
      cashierName: json['cashier_name'] as String?,
      note: json['note'] as String?,
      items: items,
      payments: payments,
      rawPaymentMethod: json['payment_method'] as String?,
      servedAt: _optionalTime(json['served_at']),
      servedByName: json['served_by_name'] as String?,
      receiptPrintedAt: _optionalTime(json['receipt_printed_at']),
      receiptPrintCount: (json['receipt_print_count'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _optionalTime(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse('$raw');
  }
}
