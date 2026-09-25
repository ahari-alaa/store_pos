import '../../../pos/domain/entities/cart_item.dart';
import '../../../pos/domain/entities/product.dart';
import '../../../pos/presentation/providers/payment_provider.dart';
import '../../../pos/presentation/providers/receipt_data.dart';
import '../../domain/entities/sale.dart';

/// Rebuilds a [ReceiptData] snapshot from a stored [Sale] (Sales screen §
/// 13/§22: "View receipt / Print / Share must work for both PAID and NOT
/// PAID"), reusing the exact same [buildReceiptPdf] renderer the POS
/// screen's own post-sale receipt uses — so a receipt printed today from
/// Sales history looks identical to the one printed at the register, and
/// the "no NOT PAID banner" fix (§4) automatically applies here too.
ReceiptData receiptDataFromSale(Sale sale) {
  final items = sale.items
      .map(
        (line) => CartItem(
          product: Product(
            id: line.productId,
            name: line.productName,
            price: line.unitPrice,
            stockQuantity: 0,
          ),
          quantity: line.quantity,
        ),
      )
      .toList();

  final payments = sale.payments
      .map((p) => PaymentEntry(method: p.method, amount: p.amount))
      .toList();

  return ReceiptData(
    saleId: sale.id,
    receiptNumber: sale.receiptNumber,
    isPaid: sale.isPaid,
    occurredAt: sale.occurredAt,
    cashierName: sale.cashierName ?? 'Cashier',
    items: items,
    subtotal: sale.subtotal,
    discountAmount: sale.discountTotal,
    taxAmount: sale.taxTotal,
    total: sale.total,
    payments: payments,
    change: sale.change,
  );
}
