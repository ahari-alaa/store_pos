import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../domain/entities/my_report.dart';
import '../providers/my_report_provider.dart';
import '../providers/reports_provider.dart';
import 'cashier_report_pdf.dart';

/// "IMPRIMER LE RAPPORT" — prints the signed-in cashier's OWN report for the
/// period currently selected on the Rapport screen. It is NOT order printing
/// (that is IMPRIMER / SERVIR on an order card, which also marks the order
/// served); printing a report changes nothing on the server.
///
/// It uses the project's existing print mechanism: the PDF goes to
/// [Printing.layoutPdf] (the OS print dialog / print preview), exactly like
/// the admin report and the receipts.
class CashierReportPrinter {
  CashierReportPrinter._();

  /// Fetches a FRESH snapshot (with the full order list) so the printout is
  /// consistent with itself, builds the PDF and opens the print dialog.
  ///
  /// Returns the report that was printed, or null if the selected period is
  /// not complete yet (custom range without both dates). Throws on network /
  /// PDF failures — the caller shows the message.
  static Future<MyReport?> print(WidgetRef ref) async {
    final filter = ref.read(myReportFilterProvider);
    if (!filter.isReady) return null;

    final data = await ref
        .read(reportsApiProvider)
        .fetchMySales(filter.toQuery(), includeOrders: true);
    final report = MyReport.fromJson(data);
    final bytes = await CashierReportPdf.build(report);

    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: fileName(report),
    );
    return report;
  }

  /// `rapport-ahmed-2026-09-18` (used as the print job / save-as name).
  static String fileName(MyReport r) {
    final who = r.cashierName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final day = '${r.periodStart.year.toString().padLeft(4, '0')}-'
        '${r.periodStart.month.toString().padLeft(2, '0')}-'
        '${r.periodStart.day.toString().padLeft(2, '0')}';
    return 'rapport-${who.isEmpty ? 'caissier' : who}-$day';
  }
}
