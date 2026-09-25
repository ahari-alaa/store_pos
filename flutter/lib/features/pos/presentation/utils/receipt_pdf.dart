import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/utils/currency_formatter.dart';
import '../../../settings/domain/entities/receipt_settings.dart';
import '../providers/receipt_data.dart';

/// Renders a [ReceiptData] snapshot as a printable PDF, using the current
/// [ReceiptSettings] (store info, paper size, footer, which fields to show
/// — configured from the Settings screen, never from the POS screen
/// itself). Formatted for a receipt-roll width by default, but on plain
/// paper, so it prints cleanly to any regular printer without special
/// drivers — see the "Regular printer (PDF preview + print dialog)" choice
/// for this feature.
Future<pw.Document> buildReceiptPdf(ReceiptData data, ReceiptSettings settings) async {
  final doc = pw.Document();
  final pageFormat = settings.paperSize.pdfPageFormat;

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (settings.showLogo) _logoPlaceholder(settings.storeName),
            if (settings.showLogo) pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                settings.storeName,
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (settings.receiptHeader.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(settings.receiptHeader, style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
            if (settings.storeAddress.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(settings.storeAddress, style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
            if (settings.storePhone.trim().isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(settings.storePhone, style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text('Receipt', style: const pw.TextStyle(fontSize: 10)),
            ),
            pw.SizedBox(height: 10),
            if (settings.showDateTime) _kv('Date', _formatDateTime(data.occurredAt)),
            if (settings.showReceiptNumber) _kv('Receipt #', data.receiptNumber),
            if (settings.showCashier) _kv('Cashier', data.cashierName),
            pw.SizedBox(height: 8),
            pw.Divider(),
            ...data.items.map(
              (item) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(item.product.name, style: const pw.TextStyle(fontSize: 10)),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '${item.quantity} x ${CurrencyFormatter.format(item.product.price)}',
                          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          CurrencyFormatter.format(item.lineSubtotal),
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            pw.Divider(),
            _kv('Subtotal', CurrencyFormatter.format(data.subtotal)),
            if (data.discountAmount > 0)
              _kv('Discount', '-${CurrencyFormatter.format(data.discountAmount)}'),
            if (data.taxAmount > 0) _kv('Tax', CurrencyFormatter.format(data.taxAmount)),
            pw.SizedBox(height: 4),
            _kv(
              'Total',
              CurrencyFormatter.format(data.total),
              bold: true,
              fontSize: 13,
            ),
            // Payment status/breakdown is deliberately shown ONLY when the
            // sale is paid. An unpaid sale's status belongs to the Sales
            // screen (spec §5/§18), not the printed/shared receipt — so
            // when `!data.isPaid` this section is simply omitted rather
            // than showing any "not paid" wording here.
            if (data.isPaid) ...[
              pw.SizedBox(height: 8),
              pw.Divider(),
              ...data.payments.map(
                (p) => _kv(p.method.name, CurrencyFormatter.format(p.amount)),
              ),
              if (data.change > 0) _kv('Change', CurrencyFormatter.format(data.change)),
            ],
            pw.SizedBox(height: 16),
            if (settings.footerMessage.trim().isNotEmpty)
              pw.Center(
                child: pw.Text(settings.footerMessage, style: const pw.TextStyle(fontSize: 10)),
              ),
          ],
        );
      },
    ),
  );

  return doc;
}

/// The project has no store-logo upload/asset pipeline, so "Show logo"
/// renders a simple store-initial mark instead of a raster image — this
/// avoids inventing a new asset/upload system just for this toggle.
pw.Widget _logoPlaceholder(String storeName) {
  final initial = storeName.trim().isNotEmpty ? storeName.trim()[0].toUpperCase() : 'S';
  return pw.Center(
    child: pw.Container(
      width: 34,
      height: 34,
      decoration: pw.BoxDecoration(
        color: PdfColors.green700,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(
        initial,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    ),
  );
}

pw.Widget _kv(String label, String value, {bool bold = false, double fontSize = 10}) {
  final style = pw.TextStyle(
    fontSize: fontSize,
    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(value, style: style),
      ],
    ),
  );
}

String _formatDateTime(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
