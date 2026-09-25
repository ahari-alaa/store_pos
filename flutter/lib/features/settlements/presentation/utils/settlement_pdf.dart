import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../reports/presentation/widgets/report_widgets.dart';
import '../../domain/entities/settlement.dart';

/// Printable A4 "JUSTIFICATIF DE TRAVAIL DU CAISSIER" (spec §19) — the
/// cashier work-payment proof, built from the SAME [CashierSettlement]
/// snapshot (with its `orders`) the app just received from the server.
///
/// This is NOT a customer receipt and NOT the personal activity report
/// (CashierReportPdf): it exists to answer one question for the manager —
/// exactly which orders is this settlement number covering, and how much
/// do they total.
///
/// [copy]: when true (the ADMIN-ONLY duplicate — spec §26), the document
/// is stamped "COPIE / DUPLICATA" in an unmissable place, top and bottom,
/// so it can never be presented as if it were the original.
class SettlementPdf {
  SettlementPdf._();

  static Future<Uint8List> build(
    CashierSettlement s, {
    required String storeName,
    String? storeAddress,
    bool copy = false,
  }) async {
    final orders = s.orders ?? const <SettlementOrder>[];
    final doc = pw.Document(
      title: 'Justificatif ${_s(s.settlementNumber)}${copy ? ' (copie)' : ''}',
      author: _s(storeName),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 34),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (copy)
                pw.Text('COPIE / DUPLICATA',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
              pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (context) => [
          if (copy)
            pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              margin: const pw.EdgeInsets.only(bottom: 10),
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2, color: PdfColors.red)),
              child: pw.Text('COPIE / DUPLICATA - NE PEUT SE SUBSTITUER A L\'ORIGINAL',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
            ),
          pw.Text(_s(storeName), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          if ((storeAddress ?? '').trim().isNotEmpty)
            pw.Text(_s(storeAddress!), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text('JUSTIFICATIF DE TRAVAIL DU CAISSIER',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 10),

          _kv('Caissier', s.cashierName, bold: true),
          _kv('Justificatif', s.settlementNumber, bold: true),
          _kv(
            'Période',
            '${ReportFormat.date(s.periodStart)}  →  ${ReportFormat.date(s.periodEnd)}',
          ),
          _kv("Date d'impression", ReportFormat.dateTime(copy ? DateTime.now() : s.printedAt)),
          if (copy && s.printedAt != s.periodStart) _kv('Original imprimé le', ReportFormat.dateTime(s.printedAt)),

          pw.SizedBox(height: 6),
          pw.Container(decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.9)))),
          pw.SizedBox(height: 8),

          pw.Text('COMMANDES TRAITEES', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          for (final o in orders) _orderRow(o),

          pw.SizedBox(height: 8),
          pw.Container(decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.9)))),
          pw.SizedBox(height: 8),

          _kv('NOMBRE DE COMMANDES', ReportFormat.integer(s.orderCount), bold: true),
          _kv('TOTAL DES VENTES', ReportFormat.money(s.totalAmount), bold: true),

          pw.SizedBox(height: 8),
          pw.Container(decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.9)))),
          pw.SizedBox(height: 10),

          _kv('Justificatif', s.settlementNumber, bold: true),
          pw.SizedBox(height: 4),
          pw.Text(
            "Ce justificatif ne peut pas etre utilise une deuxieme fois.",
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),

          pw.SizedBox(height: 26),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Signature caissier: ________________', style: const pw.TextStyle(fontSize: 9.5)),
              pw.Text('Signature responsable: ________________', style: const pw.TextStyle(fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _orderRow(SettlementOrder o) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.3, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(flex: 2, child: pw.Text(_s('#${o.receiptNumber}'), style: const pw.TextStyle(fontSize: 9))),
          pw.Expanded(
            flex: 3,
            child: pw.Text(_s(ReportFormat.dateTime(o.occurredAt)), style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(_s(ReportFormat.money(o.total)),
                textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kv(String label, String value, {bool bold = false}) {
    final style = bold
        ? pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)
        : const pw.TextStyle(fontSize: 9.5);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(_s(label), style: style),
          pw.Text(_s(value), style: style),
        ],
      ),
    );
  }

  /// Same Latin-1 sanitization as CashierReportPdf/ReportPdf: the built-in
  /// Helvetica has no glyph beyond Latin-1, so typographic punctuation is
  /// mapped to ASCII and anything else (e.g. Arabic names) becomes `?`
  /// rather than printing nothing.
  static String _s(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      if (rune == 0x2019 || rune == 0x2018) {
        out.write("'");
      } else if (rune == 0x2013 || rune == 0x2014 || rune == 0x2212) {
        out.write('-');
      } else if (rune == 0x2192) {
        out.write('>');
      } else if (rune == 0x0153) {
        out.write('oe');
      } else if (rune == 0x0152) {
        out.write('OE');
      } else if (rune == 0x00A0 || rune == 0x202F) {
        out.write(' ');
      } else if (rune < 0x20) {
        out.write(' ');
      } else if (rune <= 0xFF) {
        out.writeCharCode(rune);
      } else {
        out.write('?');
      }
    }
    return out.toString();
  }
}
