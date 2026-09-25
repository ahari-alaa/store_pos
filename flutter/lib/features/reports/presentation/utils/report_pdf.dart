import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/report_overview.dart';
import '../widgets/report_widgets.dart';

/// Compact, printable A4 "RAPPORT X" built from the SAME [ReportOverview]
/// the dashboard displays — nothing is recomputed here, every figure is
/// read from the object, so the PDF cannot disagree with the screen.
///
/// Black & white on purpose (archivable, prints well on a thermal or laser
/// printer): horizontal rules and aligned columns, no coloured cards.
///
/// Font note: the PDF uses the built-in Helvetica, which only covers
/// Latin-1. [_s] maps the few typographic characters outside it to ASCII
/// and replaces anything else (e.g. Arabic product names) with `?` rather
/// than printing nothing; the Excel export carries such names intact.
class ReportPdf {
  ReportPdf._();

  /// The PDF lists at most this many sales (chronological). The Excel
  /// export carries the whole list (server cap 5000).
  static const int maxSalesRows = 1000;

  static const double _font = 8.5;

  static Future<Uint8List> build(ReportOverview d) async {
    final doc = pw.Document(
      title: 'Rapport ${_periodText(d)}',
      author: _s(d.store.name),
    );

    final sales = d.sales ?? d.recentSales;
    final shownSales = sales.length > maxSalesRows ? sales.sublist(0, maxSalesRows) : sales;
    final salesCut = sales.length > maxSalesRows;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 34),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(_s('${d.store.name}  -  ${_periodText(d)}'),
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
              pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (context) => [
          ..._header(d),

          // MOYENS DE PAIEMENT
          _title('MOYENS DE PAIEMENT'),
          _tableHeader(const [_C('Moyen de paiement', 4), _C('Encaissement', 3, right: true), _C('Nombre', 2, right: true), _C('Dans le tiroir', 3, right: true)]),
          if (d.payments.methods.isEmpty) _note('Aucun encaissement sur cette période.'),
          for (final m in d.payments.methods)
            _tableRow(const [_C('', 4), _C('', 3, right: true), _C('', 2, right: true), _C('', 3, right: true)], [
              _methodLabel(m.method),
              ReportFormat.amount(m.amount),
              ReportFormat.integer(m.count),
              ReportFormat.amount(m.inDrawer),
            ]),
          _totalRow(const [_C('', 4), _C('', 3, right: true), _C('', 2, right: true), _C('', 3, right: true)], [
            'TOTAL',
            ReportFormat.amount(d.payments.totalCollected),
            ReportFormat.integer(d.payments.transactions),
            ReportFormat.amount(d.payments.inDrawer),
          ]),
          _kv('Reste à encaisser (ventes non / partiellement payées)', ReportFormat.money(d.payments.outstanding)),
          _kv('Rendu monnaie (déjà déduit des espèces)', ReportFormat.money(d.payments.changeGiven)),

          // CA NET / PANIER MOYEN / NOMBRE DE VENTES / ARTICLES VENDUS
          _title('CHIFFRE D\'AFFAIRES'),
          _kv('CA NET (TTC)', ReportFormat.money(d.kpis.revenue), bold: true),
          _kv('PANIER MOYEN', ReportFormat.money(d.kpis.averageTicket)),
          _kv('NOMBRE DE VENTES', ReportFormat.integer(d.kpis.saleCount)),
          _kv('ARTICLES VENDUS', ReportFormat.integer(d.kpis.itemsSold)),

          // TAXE
          _title('TAXE'),
          _kv('CA HT', ReportFormat.money(d.tax.revenueExTax)),
          _kv('Taxe totale', ReportFormat.money(d.tax.total)),
          _kv('CA TTC', ReportFormat.money(d.kpis.revenue)),

          // DIVERS
          _title('DIVERS'),
          _kv('Remises accordées', ReportFormat.money(d.tax.discountTotal)),
          _kv('Ventes non payées', '${ReportFormat.integer(d.alerts.unpaidCount)}  /  ${ReportFormat.money(d.alerts.unpaidAmount)}'),
          _kv('Ventes partiellement payées (reste)', '${ReportFormat.integer(d.alerts.partialCount)}  /  ${ReportFormat.money(d.alerts.partialRemaining)}'),
          _kv('Ventes annulées / remboursées (non comptées)', ReportFormat.integer(d.alerts.cancelled + d.alerts.refunded)),

          // COMMANDES PAR HEURE
          _title('COMMANDES PAR HEURE'),
          _tableHeader(const [_C('Heure', 4), _C('Commandes', 3, right: true), _C('CA (DH)', 3, right: true)]),
          if (d.ordersByHour.activeRange.isEmpty) _note('Aucune vente sur cette période.'),
          for (final h in d.ordersByHour.activeRange)
            _tableRow(const [_C('', 4), _C('', 3, right: true), _C('', 3, right: true)], [
              h.label,
              ReportFormat.integer(h.orders),
              ReportFormat.amount(h.revenue),
            ]),
          _totalRow(const [_C('', 4), _C('', 3, right: true), _C('', 3, right: true)], [
            'TOTAL',
            ReportFormat.integer(d.ordersByHour.totalOrders),
            ReportFormat.amount(d.ordersByHour.totalRevenue),
          ]),

          // CAISSIERS
          _title('CAISSIERS'),
          _tableHeader(const [_C('Caissier', 4), _C('Ventes', 2, right: true), _C('Articles', 2, right: true), _C('CA', 3, right: true), _C('Panier moyen', 3, right: true)]),
          if (d.cashiers.isEmpty) _note('Aucune vente sur cette période.'),
          for (final c in d.cashiers)
            _tableRow(const [_C('', 4), _C('', 2, right: true), _C('', 2, right: true), _C('', 3, right: true), _C('', 3, right: true)], [
              c.name,
              ReportFormat.integer(c.saleCount),
              ReportFormat.integer(c.itemsSold),
              ReportFormat.amount(c.revenue),
              ReportFormat.amount(c.averageTicket),
            ]),

          // PRODUITS LES PLUS VENDUS
          _title('PRODUITS LES PLUS VENDUS'),
          _tableHeader(const [_C('#', 1), _C('Produit', 8), _C('Quantité', 2, right: true), _C('CA', 3, right: true)]),
          if (d.topProducts.isEmpty) _note('Aucune vente sur cette période.'),
          for (var i = 0; i < d.topProducts.length; i++)
            _tableRow(const [_C('', 1), _C('', 8), _C('', 2, right: true), _C('', 3, right: true)], [
              '${i + 1}',
              d.topProducts[i].name,
              ReportFormat.integer(d.topProducts[i].quantity),
              ReportFormat.amount(d.topProducts[i].revenue),
            ]),

          // DÉPENSES
          _title('DÉPENSES'),
          _tableHeader(const [_C('Catégorie', 5), _C('%', 2, right: true), _C('Montant', 3, right: true)]),
          if (d.expenses.byCategory.isEmpty) _note('Aucune dépense sur cette période.'),
          for (final e in d.expenses.byCategory)
            _tableRow(const [_C('', 5), _C('', 2, right: true), _C('', 3, right: true)], [
              e.category,
              ReportFormat.percent(e.percent),
              ReportFormat.amount(e.amount),
            ]),
          _totalRow(const [_C('', 5), _C('', 2, right: true), _C('', 3, right: true)], [
            'TOTAL DÉPENSES',
            '',
            ReportFormat.amount(d.expenses.total),
          ]),

          // RÉSULTAT ESTIMÉ
          _title('RÉSULTAT ESTIMÉ'),
          _kv('CA NET (TTC)', ReportFormat.money(d.kpis.revenue)),
          _kv('- Dépenses', ReportFormat.money(d.kpis.expenses)),
          _kv('RÉSULTAT ESTIMÉ', ReportFormat.money(d.kpis.estimatedResult), bold: true),

          // VENTES
          _title('VENTES'),
          _tableHeader(const [_C('Ticket', 3), _C('Date', 3), _C('Heure', 2), _C('Caissier', 4), _C('Art.', 1, right: true), _C('Montant', 3, right: true), _C('Paiement', 3), _C('Statut', 3)]),
          if (shownSales.isEmpty) _note('Aucune vente sur cette période.'),
          for (final s in shownSales)
            _tableRow(const [_C('', 3), _C('', 3), _C('', 2), _C('', 4), _C('', 1, right: true), _C('', 3, right: true), _C('', 3), _C('', 3)], [
              '#${s.ticket.toUpperCase()}',
              ReportFormat.date(s.occurredAt),
              ReportFormat.time(s.occurredAt),
              s.cashierName,
              ReportFormat.integer(s.itemsCount),
              ReportFormat.amount(s.total),
              s.paymentMethod == null ? '-' : _methodLabel(s.paymentMethod!),
              _statusLabel(s),
            ]),
          if (salesCut)
            _note('Liste limitée aux ${ReportFormat.integer(maxSalesRows)} premières ventes sur ${ReportFormat.integer(sales.length)} '
                '- l\'export Excel contient la liste complète.'),
          if (d.salesTruncated)
            _note('La liste complète dépasse la limite du serveur - les totaux ci-dessus restent exacts.'),
        ],
      ),
    );

    return doc.save();
  }

  // ---- header --------------------------------------------------------

  static List<pw.Widget> _header(ReportOverview d) {
    final contact = [
      if ((d.store.address ?? '').trim().isNotEmpty) d.store.address!.trim(),
      if ((d.store.phone ?? '').trim().isNotEmpty) 'Tel : ${d.store.phone!.trim()}',
    ].join('   ');

    return [
      pw.Center(
        child: pw.Text('STORE POS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
      ),
      pw.SizedBox(height: 2),
      pw.Center(
        child: pw.Text(_s(d.store.name), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ),
      if (contact.isNotEmpty)
        pw.Center(child: pw.Text(_s(contact), style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(width: 1.2),
            bottom: pw.BorderSide(width: 1.2),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('RAPPORT X', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text(_periodText(d), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text('Édité le ${ReportFormat.dateTime(d.generatedAt)}',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
    ];
  }

  static String _periodText(ReportOverview d) {
    final start = d.period.start;
    final end = d.period.end;
    final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
    return sameDay
        ? 'Le ${ReportFormat.date(start)}'
        : 'Du ${ReportFormat.date(start)} au ${ReportFormat.date(end)}';
  }

  // ---- labels --------------------------------------------------------

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

  static String _statusLabel(ReportSaleRow s) {
    if (s.saleStatus == 'CANCELLED') return 'Annulée';
    if (s.saleStatus == 'REFUNDED') return 'Remboursée';
    switch (s.paymentStatus) {
      case 'PAID':
        return 'Payé';
      case 'PARTIALLY_PAID':
        return 'Partiel';
      case 'REFUNDED':
        return 'Remboursé';
      default:
        return 'Non payé';
    }
  }

  // ---- text safety ---------------------------------------------------

  /// Maps typographic characters outside Latin-1 to ASCII and any other
  /// unsupported character to `?` (see the class note).
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

  // ---- building blocks (plain Row/Text: stable across pdf versions) ----

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
