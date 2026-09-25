import '../../domain/entities/report_overview.dart';
import '../widgets/report_widgets.dart';
import 'xlsx_writer.dart';

/// The report as spreadsheet tables (Résumé, Commandes par heure,
/// Paiements, Caissiers, Produits, Dépenses, Évolution, Ventes), built from
/// the SAME [ReportOverview] as the screen and the PDF. Both the .xlsx and
/// the .csv export are generated from these sheets, so they cannot differ.
class ReportSheets {
  ReportSheets._();

  static XlsxCell _h(String t) => XlsxCell.header(t);
  static XlsxCell _m(double v, {bool bold = false}) => XlsxCell.money(v, bold: bold);
  static XlsxCell _b(String t) => XlsxCell(t, bold: true);

  static String methodLabel(String method) {
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
        return method;
    }
  }

  static String saleStatusLabel(ReportSaleRow s) {
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

  static List<XlsxSheet> build(ReportOverview d) {
    final period = d.period.days <= 1
        ? ReportFormat.date(d.period.start)
        : '${ReportFormat.date(d.period.start)} - ${ReportFormat.date(d.period.end)}';

    final summary = XlsxSheet('Résumé', [
      [_b(d.store.name)],
      ['Rapport X'],
      ['Période', period],
      ['Édité le', ReportFormat.dateTime(d.generatedAt)],
      [],
      [_h('Indicateur'), _h('Valeur')],
      ['Chiffre d\'affaires (CA NET TTC)', _m(d.kpis.revenue)],
      ['Nombre de ventes', d.kpis.saleCount],
      ['Articles vendus', d.kpis.itemsSold],
      ['Ticket moyen', _m(d.kpis.averageTicket)],
      ['Dépenses', _m(d.kpis.expenses)],
      [_b('Résultat estimé'), _m(d.kpis.estimatedResult, bold: true)],
      [],
      ['CA HT', _m(d.tax.revenueExTax)],
      ['Taxe totale', _m(d.tax.total)],
      ['Remises accordées', _m(d.tax.discountTotal)],
      [],
      ['Encaissé', _m(d.payments.totalCollected)],
      ['Dans le tiroir (espèces)', _m(d.payments.inDrawer)],
      ['Rendu monnaie', _m(d.payments.changeGiven)],
      ['Reste à encaisser', _m(d.payments.outstanding)],
      ['Ventes non payées (nombre)', d.alerts.unpaidCount],
      ['Ventes non payées (montant)', _m(d.alerts.unpaidAmount)],
      ['Ventes partiellement payées (nombre)', d.alerts.partialCount],
      ['Ventes partiellement payées (reste)', _m(d.alerts.partialRemaining)],
      ['Ventes annulées / remboursées (non comptées)', d.alerts.cancelled + d.alerts.refunded],
    ]);

    final hourly = XlsxSheet('Commandes par heure', [
      [_h('Heure'), _h('Nombre de commandes'), _h('CA (DH)')],
      for (final h in d.ordersByHour.hours) [h.label, h.orders, _m(h.revenue)],
      [_b('TOTAL'), XlsxCell(d.ordersByHour.totalOrders, bold: true), _m(d.ordersByHour.totalRevenue, bold: true)],
    ]);

    final payments = XlsxSheet('Paiements', [
      [_h('Moyen de paiement'), _h('Encaissement'), _h('Nombre'), _h('Dans le tiroir')],
      for (final m in d.payments.methods)
        [methodLabel(m.method), _m(m.amount), m.count, _m(m.inDrawer)],
      [
        _b('TOTAL'),
        _m(d.payments.totalCollected, bold: true),
        XlsxCell(d.payments.transactions, bold: true),
        _m(d.payments.inDrawer, bold: true),
      ],
    ]);

    final totalSales = d.cashiers.fold<int>(0, (s, c) => s + c.saleCount);
    final totalItems = d.cashiers.fold<int>(0, (s, c) => s + c.itemsSold);
    final cashiers = XlsxSheet('Caissiers', [
      [_h('Caissier'), _h('Ventes'), _h('Articles'), _h('CA'), _h('Panier moyen')],
      for (final c in d.cashiers)
        [c.name, c.saleCount, c.itemsSold, _m(c.revenue), _m(c.averageTicket)],
      [
        _b('TOTAL'),
        XlsxCell(totalSales, bold: true),
        XlsxCell(totalItems, bold: true),
        _m(d.kpis.revenue, bold: true),
        _m(totalSales > 0 ? d.kpis.revenue / totalSales : 0, bold: true),
      ],
    ]);

    final products = XlsxSheet('Produits', [
      [_h('Rang'), _h('Produit'), _h('Quantité'), _h('CA')],
      for (var i = 0; i < d.topProducts.length; i++)
        [i + 1, d.topProducts[i].name, d.topProducts[i].quantity, _m(d.topProducts[i].revenue)],
    ]);

    final expenses = XlsxSheet('Dépenses', [
      [_h('Catégorie'), _h('Nombre'), _h('Montant'), _h('%')],
      for (final e in d.expenses.byCategory) [e.category, e.count, _m(e.amount), e.percent],
      [_b('TOTAL'), XlsxCell(d.expenses.count, bold: true), _m(d.expenses.total, bold: true)],
    ]);

    final evolution = XlsxSheet('Évolution du CA', [
      [_h(d.revenueSeries.granularity == 'hour' ? 'Heure' : (d.revenueSeries.granularity == 'month' ? 'Mois' : 'Jour')), _h('CA'), _h('Nombre de ventes')],
      for (final b in d.revenueSeries.buckets)
        [
          d.revenueSeries.granularity == 'hour'
              ? ReportFormat.dateTime(b.start)
              : (d.revenueSeries.granularity == 'month' ? '${b.start.month.toString().padLeft(2, '0')}/${b.start.year}' : ReportFormat.date(b.start)),
          _m(b.revenue),
          b.saleCount,
        ],
    ]);

    final list = d.sales ?? d.recentSales;
    final salesSheet = XlsxSheet('Ventes', [
      [_h('Ticket'), _h('Date'), _h('Heure'), _h('Caissier'), _h('Articles'), _h('Total'), _h('Encaissé'), _h('Paiement'), _h('Statut')],
      for (final s in list)
        [
          '#${s.ticket.toUpperCase()}',
          ReportFormat.date(s.occurredAt),
          ReportFormat.time(s.occurredAt),
          s.cashierName,
          s.itemsCount,
          _m(s.total),
          _m(s.paidAmount),
          s.paymentMethod == null ? '' : methodLabel(s.paymentMethod!),
          saleStatusLabel(s),
        ],
      if (d.sales == null) ['(Liste partielle : ventes récentes uniquement)'],
      if (d.salesTruncated) ['(Liste tronquée par le serveur : les totaux des autres feuilles restent exacts)'],
    ]);

    return [summary, hourly, payments, cashiers, products, expenses, evolution, salesSheet];
  }

  /// Same sheets as CSV text (`;`-separated, dot decimals, one titled
  /// block per sheet) for the "CSV" option of the Excel button.
  static String toCsv(List<XlsxSheet> sheets) {
    String cell(Object? raw) {
      final value = raw is XlsxCell ? raw.value : raw;
      final text = value == null
          ? ''
          : (value is num ? (value is int ? '$value' : value.toStringAsFixed(2)) : '$value');
      if (text.contains(';') || text.contains('"') || text.contains('\n')) {
        return '"${text.replaceAll('"', '""')}"';
      }
      return text;
    }

    final buffer = StringBuffer();
    for (final sheet in sheets) {
      buffer.writeln(cell(sheet.name.toUpperCase()));
      for (final row in sheet.rows) {
        buffer.writeln(row.map(cell).join(';'));
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}
