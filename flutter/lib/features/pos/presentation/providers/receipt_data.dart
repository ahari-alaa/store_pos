import '../../domain/entities/cart_item.dart';
import 'cart_provider.dart';
import 'payment_provider.dart';

/// Short, human-friendly receipt number derived from a real backend sale
/// id (the first 8 chars of its UUID). Shared by every place that needs to
/// show a sale's receipt number — the POS "sale completed" flow, the
/// "Give receipt without paying" flow, and the Sales screen — so they can
/// never drift out of sync with each other (spec §24: reuse, don't
/// duplicate this kind of small business rule).
String receiptNumberForSaleId(String saleId) {
  if (saleId.isEmpty) return 'N/A';
  return saleId.length > 8 ? saleId.substring(0, 8) : saleId;
}

/// Snapshot of everything a receipt needs.
///
/// Two ways this gets built:
///  - [ReceiptData.fromSaleResponse], after a REAL sale was created on the
///    backend — either paid (cart_panel.dart#_completeSale) or unpaid
///    (cart_panel.dart#_giveReceiptWithoutPaying, Sales spec §2/§12) —
///    with [saleId]/[receiptNumber] coming from that real backend sale
///    row either way.
///  - [ReceiptData.fromCart], for the POS screen's own Print/Share buttons,
///    which preview the CURRENT cart before any sale is created at all —
///    [isPaid] = false, no backend call is made, and [receiptNumber] is a
///    client-side "PND-" reference (see the note on it) so it can never
///    collide with, or consume, a real sale number.
class ReceiptData {
  final String saleId;
  final String receiptNumber;
  final bool isPaid;
  final DateTime occurredAt;
  final String cashierName;
  final List<CartItem> items;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final List<PaymentEntry> payments;
  final double change;

  const ReceiptData({
    required this.saleId,
    required this.receiptNumber,
    required this.isPaid,
    required this.occurredAt,
    required this.cashierName,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.payments,
    required this.change,
  });

  /// Builds a NOT-PAID receipt straight from the current cart/discount
  /// state, without touching the sale/payment API at all.
  ///
  /// [receiptNumber] uses a "PND-" (pending) prefix followed by a
  /// timestamp, deliberately distinct in shape from real backend sale ids
  /// (see saleControllerProvider / POST /sales) — an unpaid receipt must
  /// never consume or collide with the real sale numbering sequence, since
  /// no sale has actually been created yet.
  factory ReceiptData.fromCart({
    required List<CartItem> items,
    required CartTotals totals,
    required String cashierName,
  }) {
    final now = DateTime.now();
    return ReceiptData(
      saleId: '',
      receiptNumber: 'PND-${_timestampTag(now)}',
      isPaid: false,
      occurredAt: now,
      cashierName: cashierName,
      items: items,
      subtotal: totals.subtotal,
      discountAmount: totals.discountAmount,
      taxAmount: totals.taxAmount,
      total: totals.total,
      payments: const [],
      change: 0,
    );
  }

  static String _timestampTag(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}-${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }

  /// Builds a receipt snapshot from a REAL sale the backend just created
  /// or returned (POST /sales or GET /sales/:id) — used for both a paid
  /// sale and an unpaid one, since the only difference is [isPaid] and
  /// [payments]/[change] (see the class doc above).
  factory ReceiptData.fromSaleResponse({
    required Map<String, dynamic> sale,
    required List<CartItem> items,
    required CartTotals totals,
    required String cashierName,
    List<PaymentEntry> payments = const [],
    double change = 0,
  }) {
    final saleId = (sale['id'] as String?) ?? '';
    return ReceiptData(
      saleId: saleId,
      receiptNumber: receiptNumberForSaleId(saleId),
      isPaid: (sale['payment_status'] as String?) == 'PAID',
      occurredAt: DateTime.tryParse((sale['occurred_at'] as String?) ?? '') ?? DateTime.now(),
      cashierName: cashierName,
      items: items,
      subtotal: totals.subtotal,
      discountAmount: totals.discountAmount,
      taxAmount: totals.taxAmount,
      total: totals.total,
      payments: payments,
      change: change < 0 ? 0 : change,
    );
  }
}
