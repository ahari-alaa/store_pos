import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../sales/domain/entities/sale.dart';
import '../../domain/entities/my_report.dart';
import '../widgets/report_widgets.dart';

/// Printable A4 "RAPPORT PERSONNEL" of ONE cashier for ONE period, built from
/// the SAME [MyReport] snapshot the Rapport screen shows (fetched with
/// `include_orders`), so the paper can never disagree with the screen.
///
/// It is the cashier's report only — never the admin report. Same look as the
/// admin PDF (black & white, rules and aligned columns: archivable, prints
/// well on a thermal or laser printer) and the same font limitation: the
/// built-in Helvetica only covers Latin-1, so [_s] maps the few typographic
/// characters outside it to ASCII and replaces anything else (e.g. Arabic
/// product names) with `?` rather than printing nothing.
class CashierReportPdf {
  CashierReportPdf._();

  static const double _font = 8.5;

  static Future<Uint8List> build(MyReport r) async {
    final doc = pw.Document(
      title: 'Rapport personnel - ${_s(r.cashierName)} - ${periodText(r)}',
      author: _s(r.storeName),
    );

    final orders = r.orders ?? const <MyOrder>[];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 34),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(_s('${r.storeName}  -  ${r.cashierName}  -  ${periodText(r)}'),
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
              pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (context) => [
          ..._header(r),

          // RÉSUMÉ
          _title('RESUME'),
          _kv('TOTAL DES VENTES', ReportFormat.money(r.kpis.revenue), bold: true),
          _kv('NOMBRE DE COMMANDES', ReportFormat.integer(r.kpis.orderCount)),
          _kv('PRODUITS VENDUS (ARTICLES)', ReportFormat.integer(r.kpis.itemsSold)),
          _kv('PANIER MOYEN', ReportFormat.money(r.kpis.averageTicket)),

          // PRODUITS VENDUS
          _title('PRODUITS VENDUS'),
          _tableHeader(const [_C('Produit', 6), _C('Quantité', 2, right: true), _C("Chiffre d'affaires", 3, right: true)]),
          if (r.products.isEmpty) _note('Aucun produit vendu sur cette période.'),
          for (final p in r.products)
            _tableRow(const [_C('', 6), _C('', 2, right: true), _C('', 3, right: true)], [
              p.name,
              ReportFormat.integer(p.quantity),
              ReportFormat.money(p.revenue),
            ]),
          if (r.products.isNotEmpty)
            _totalRow(const [_C('', 6), _C('', 2, right: true), _C('', 3, right: true)], [
              'TOTAL',
              ReportFormat.integer(r.products.fold<int>(0, (sum, p) => sum + p.quantity)),
              ReportFormat.money(r.products.fold<double>(0, (sum, p) => sum + p.revenue)),
            ]),

          // PAIEMENTS
          _title('RESUME DES PAIEMENTS'),
          _tableHeader(const [_C('Moyen de paiement', 5), _C('Encaissement', 3, right: true), _C('Nombre', 2, right: true)]),
          if (r.payments.methods.isEmpty) _note('Aucun encaissement sur cette période.'),
          for (final m in r.payments.methods)
            _tableRow(const [_C('', 5), _C('', 3, right: true), _C('', 2, right: true)], [
              _methodLabel(m.method),
              ReportFormat.money(m.amount),
              ReportFormat.integer(m.count),
            ]),
          _kv('Total encaissé', ReportFormat.money(r.payments.totalCollected), bold: true),
          _kv('Rendu monnaie (déjà déduit des espèces)', ReportFormat.money(r.payments.changeGiven)),
          _kv('Reste à encaisser', ReportFormat.money(r.payments.outstanding)),
          if (r.payments.unpaidCount > 0)
            _kv('  dont commandes non payées (${r.payments.unpaidCount})',
                ReportFormat.money(r.payments.unpaidAmount)),
          if (r.payments.partialCount > 0)
            _kv('  dont commandes partiellement payées (${r.payments.partialCount})',
                ReportFormat.money(r.payments.partialRemaining)),

          // COMMANDES
          _title('COMMANDES TRAITEES (${ReportFormat.integer(r.kpis.orderCount)})'),
          _tableHeader(const [
            _C('N°', 2),
            _C('Date / heure', 3),
            _C('Produits', 6),
            _C('Total', 2, right: true),
            _C('Paiement', 2),
            _C('Service', 2),
          ]),
          if (orders.isEmpty) _note('Aucune commande sur cette période.'),
          for (final o in orders) _orderRow(o),
          if (orders.isNotEmpty)
            _totalRow(
              const [_C('', 2), _C('', 3), _C('', 6), _C('', 2, right: true), _C('', 2), _C('', 2)],
              ['TOTAL', '', '', ReportFormat.money(r.kpis.revenue), '', ''],
            ),
          if (r.ordersTruncated)
            _note('Liste limitée aux premières commandes de la période; les totaux ci-dessus restent complets.'),
        ],
      ),
    );

    return doc.save();
  }

  /// "Aujourd'hui (18/09/2026)", "Cette semaine (14/09/2026 au 20/09/2026)"...
  static String periodText(MyReport r) {
    final start = ReportFormat.date(r.periodStart);
    final end = ReportFormat.date(r.periodEnd);
    final range = start == end ? start : '$start au $end';
    switch (r.periodKey) {
      case 'today':
        return "Aujourd'hui ($range)";
      case 'yesterday':
        return 'Hier ($range)';
      case 'week':
        return 'Cette semaine ($range)';
      case 'last_week':
        return 'Semaine précédente ($range)';
      case 'month':
        return 'Ce mois ($range)';
      case 'last_month':
        return 'Mois précédent ($range)';
      default:
        return start == end ? 'Le $start' : 'Du $start au $end';
    }
  }

  static List<pw.Widget> _header(MyReport r) => [
        pw.Text(_s(r.storeName), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        if ((r.storeAddress ?? '').trim().isNotEmpty)
          pw.Text(_s(r.storeAddress!), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        if ((r.storePhone ?? '').trim().isNotEmpty)
          pw.Text(_s(r.storePhone!), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        pw.Text('RAPPORT PERSONNEL DU CAISSIER',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        _kv('Caissier', r.cashierName, bold: true),
        _kv('Période', periodText(r)),
        _kv('Généré le', ReportFormat.dateTime(r.generatedAt)),
      ];

  static pw.Widget _orderRow(MyOrder o) {
    final lines = o.items.map((i) => '${i.quantity}x ${i.name}').join(', ');
    final served = o.isServed
        ? 'Servie${o.servedAt != null ? ' ${ReportFormat.time(o.servedAt!)}' : ''}'
        : 'A servir';
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.3, color: PdfColors.grey400)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _cell(o.receiptNumber, 2),
          _cell(ReportFormat.dateTime(o.occurredAt), 3),
          _cell(lines, 6, wrap: true),
          _cell(ReportFormat.money(o.total), 2, right: true),
          _cell(_paymentLabel(o), 2),
          _cell(served, 2),
        ],
      ),
    );
  }

  static pw.Widget _cell(String value, int flex, {bool right = false, bool wrap = false}) => pw.Expanded(
        flex: flex,
        child: pw.Padding(
          padding: const pw.EdgeInsets.only(right: 4),
          child: pw.Text(
            _s(value),
            maxLines: wrap ? null : 1,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: const pw.TextStyle(fontSize: _font),
          ),
        ),
      );

  static String _paymentLabel(MyOrder o) {
    switch (o.paymentStatus) {
      case SalePaymentStatus.paid:
        return 'Payée';
      case SalePaymentStatus.partiallyPaid:
        return 'Partielle';
      case SalePaymentStatus.refunded:
        return 'Remboursée';
      case SalePaymentStatus.pending:
        return 'Non payée';
    }
  }

  static String _methodLabel(String method) {
    switch (method) {
      case 'CASH':
        return 'Espèces';
      case 'CARD':
        return 'Carte bancaire';
      case 'TRANSFER':
        return 'Virement';
      case 'MIXED':
        return 'Mixte';
      default:
        return method.isEmpty ? '-' : method;
    }
  }

  // ---- small layout helpers (same look as the admin ReportPdf) ----

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

  static pw.Widget _title(String text) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 4),
        padding: const pw.EdgeInsets.only(bottom: 2),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.9)),
        ),
        child: pw.Row(children: [
          pw.Text(_s(text), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ]),
      );

  static pw.Widget _note(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(_s(text), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      );

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

  static pw.Widget _cells(List<_C> cols, List<String> values, pw.TextStyle style) {
    return pw.Row(
      children: [
        for (var i = 0; i < cols.length; i++)
          pw.Expanded(
            flex: cols[i].flex,
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(right: 4),
              child: pw.Text(
                _s(i < values.length ? values[i] : ''),
                maxLines: 1,
                textAlign: cols[i].right ? pw.TextAlign.right : pw.TextAlign.left,
                style: style,
              ),
            ),
          ),
      ],
    );
  }

  static pw.Widget _tableHeader(List<_C> cols) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey700)),
        ),
        child: _cells(cols, [for (final c in cols) c.label], pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      );

  static pw.Widget _tableRow(List<_C> cols, List<String> values) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.3, color: PdfColors.grey400)),
        ),
        child: _cells(cols, values, const pw.TextStyle(fontSize: _font)),
      );

  static pw.Widget _totalRow(List<_C> cols, List<String> values) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 1),
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(width: 0.9)),
        ),
        child: _cells(cols, values, pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      );
}

/// Column descriptor: header text, relative width, right alignment.
class _C {
  final String label;
  final int flex;
  final bool right;

  const _C(this.label, this.flex, {this.right = false});
}
