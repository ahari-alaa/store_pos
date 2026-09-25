import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../providers/receipt_data.dart';
import '../utils/receipt_printer_service.dart';
import '../utils/receipt_pdf.dart';

/// Shown once a sale is completed. Offers direct receipt printing and
/// sharing, built from a [ReceiptData] snapshot taken right before the
/// cart was cleared. [receipt.isPaid] is always true here — this dialog
/// only ever shows after a real payment was recorded.
class SaleSuccessDialog extends ConsumerWidget {
  final double total;
  final double change;
  final ReceiptData receipt;

  const SaleSuccessDialog({
    super.key,
    required this.total,
    required this.change,
    required this.receipt,
  });

  Future<void> _shareReceipt(BuildContext context, WidgetRef ref) async {
    try {
      final settings = ref.read(receiptSettingsProvider);
      final bytes = await (await buildReceiptPdf(receipt, settings)).save();
      await Printing.sharePdf(bytes: bytes, filename: 'receipt-${receipt.receiptNumber}.pdf');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to share the receipt. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _printReceipt(BuildContext context, WidgetRef ref) async {
    try {
      final settings = ref.read(receiptSettingsProvider);
      final bytes = await (await buildReceiptPdf(receipt, settings)).save();
      await ref.read(receiptPrinterServiceProvider).printReceiptPdf(
            bytes: bytes,
            settings: settings,
            jobName: 'receipt-${receipt.receiptNumber}',
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt printed successfully.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } on ReceiptPrintException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer unavailable. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Sale completed', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              'Total charged: ${CurrencyFormatter.format(total)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            if (change > 0) ...[
              const SizedBox(height: 2),
              Text(
                'Change given: ${CurrencyFormatter.format(change)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _printReceipt(context, ref),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print receipt'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareReceipt(context, ref),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Share receipt'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('New sale'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
