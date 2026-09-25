import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../providers/receipt_data.dart';
import '../utils/receipt_pdf.dart';

/// Full-screen PDF preview for a receipt, with built-in print/share/save
/// buttons (from the `printing` package's [PdfPreview]). Works with any
/// regular printer via the OS print dialog — no thermal/ESC-POS hardware
/// required. Used both for a completed (paid) sale and for a
/// "Receipt without payment" preview, distinguished by [data.isPaid].
class ReceiptPreviewPage extends ConsumerWidget {
  final ReceiptData data;

  const ReceiptPreviewPage({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(receiptSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (format) async => (await buildReceiptPdf(data, settings)).save(),
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              pdfFileName: 'receipt-${data.receiptNumber}.pdf',
            ),
          ),
        ],
      ),
    );
  }
}
