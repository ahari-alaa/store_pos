import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../pos/domain/entities/payment_method.dart';
import '../../../pos/presentation/providers/sale_provider.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../../../pos/presentation/utils/receipt_pdf.dart';
import '../../domain/entities/sale.dart';
import '../utils/sale_receipt.dart';
import 'pay_sale_dialog.dart';
import 'sale_status_badge.dart';

/// Full sale/receipt detail view (spec §14), with the same
/// print/share/pay actions available from the Sales list row (spec §13).
class SaleDetailDialog extends ConsumerStatefulWidget {
  final Sale sale;

  const SaleDetailDialog({super.key, required this.sale});

  @override
  ConsumerState<SaleDetailDialog> createState() => _SaleDetailDialogState();
}

class _SaleDetailDialogState extends ConsumerState<SaleDetailDialog> {
  late Sale _sale;
  bool _busy = false;
  // The Sales-screen list row [widget.sale] comes from GET /sales, which
  // deliberately never embeds each sale's line items (see
  // saleRepository.list vs .findById — a real join across every row on
  // every page load would be needlessly expensive). So the object this
  // dialog opens with always has `items: []`, and the "Products" section
  // below would render as an empty gap forever unless something loads
  // the full sale (GET /sales/:id, via SalesApi.fetchSaleById) first.
  bool _loadingItems = true;

  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
    _loadFullSale();
  }

  Future<void> _loadFullSale() async {
    try {
      final api = ref.read(salesApiProvider);
      final data = await api.fetchSaleById(widget.sale.id);
      if (!mounted) return;
      setState(() {
        _sale = Sale.fromJson(data);
        _loadingItems = false;
      });
    } catch (_) {
      // Keep showing the light `widget.sale` we already had (cashier,
      // total, status) — losing the item list on a connectivity hiccup
      // shouldn't also blank out everything else already on screen.
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _pay() async {
    final updated = await showDialog<Sale>(
      context: context,
      builder: (_) => PaySaleDialog(sale: _sale),
    );
    if (updated == null || !mounted) return;
    setState(() => _sale = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Receipt #${updated.receiptNumber} marked PAID.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Future<void> _viewReceipt() async {
    Navigator.of(context).pop();
    await context.push('/receipt-preview', extra: receiptDataFromSale(_sale));
  }

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      final settings = ref.read(receiptSettingsProvider);
      final bytes = await (await buildReceiptPdf(receiptDataFromSale(_sale), settings)).save();
      await Printing.layoutPdf(onLayout: (format) async => bytes, name: 'receipt-${_sale.receiptNumber}');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer unavailable. Please check the printer and try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final settings = ref.read(receiptSettingsProvider);
      final bytes = await (await buildReceiptPdf(receiptDataFromSale(_sale), settings)).save();
      await Printing.sharePdf(bytes: bytes, filename: 'receipt-${_sale.receiptNumber}.pdf');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share the receipt. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = _sale;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Receipt #${sale.receiptNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                  ),
                  SaleStatusBadge(status: sale.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDateTime(sale.occurredAt),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (sale.cashierName != null) _row('Cashier', sale.cashierName!),
                      const SizedBox(height: 12),
                      const Text('Products', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      if (_loadingItems && sale.items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else
                        ...sale.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.productName}  ${item.quantity} × ${CurrencyFormatter.format(item.unitPrice)}',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                Text(
                                  CurrencyFormatter.format(item.subtotal),
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: 20),
                      if (sale.discountTotal > 0)
                        _row('Discount', '-${CurrencyFormatter.format(sale.discountTotal)}'),
                      if (sale.taxTotal > 0) _row('Tax', CurrencyFormatter.format(sale.taxTotal)),
                      _row('Total', CurrencyFormatter.format(sale.total), bold: true),
                      const SizedBox(height: 10),
                      const Text('Payment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      _row('Payment status', sale.status.label),
                      if (sale.isPaid) ...[
                        if (sale.paidAt != null) _row('Paid at', _formatDateTime(sale.paidAt!)),
                        if (sale.primaryPaymentMethod != null)
                          _row('Payment method', sale.primaryPaymentMethod!.label),
                        if (sale.primaryPaymentMethod == PaymentMethod.cash) ...[
                          _row('Cash received', CurrencyFormatter.format(sale.cashReceived)),
                          if (sale.change > 0) _row('Change', CurrencyFormatter.format(sale.change)),
                        ],
                      ] else if (sale.status == SalePaymentStatus.partiallyPaid) ...[
                        _row('Paid so far', CurrencyFormatter.format(sale.appliedAmount)),
                        _row('Remaining', CurrencyFormatter.format(sale.remaining)),
                      ],
                      // Serving / receipt tracking (cashier workflow). Read-only
                      // information: serving never changes the sale, its
                      // payments or any report figure.
                      const SizedBox(height: 10),
                      const Text('Service', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      _row('Service status', sale.isServed ? 'Served' : 'Not served yet'),
                      if (sale.isServed) ...[
                        _row('Served at', _formatDateTime(sale.servedAt!)),
                        _row('Served by', sale.servedByName ?? 'Before tracking (legacy)'),
                      ],
                      if (sale.receiptPrintCount > 0)
                        _row('Receipt printed', '${sale.receiptPrintCount}×'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _viewReceipt,
                      icon: const Icon(Icons.receipt_long_outlined, size: 16),
                      label: const Text('View'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _print,
                      icon: const Icon(Icons.print_outlined, size: 16),
                      label: const Text('Print'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _share,
                      icon: const Icon(Icons.ios_share_rounded, size: 16),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
              if (sale.canPay) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _pay,
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Pay', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 14 : 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}
