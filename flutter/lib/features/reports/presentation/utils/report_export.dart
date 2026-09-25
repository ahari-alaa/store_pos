import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../domain/entities/report_overview.dart';
import '../providers/reports_provider.dart';
import 'report_pdf.dart';
import 'report_sheets.dart';
import 'xlsx_writer.dart';

enum ReportExportFormat { pdf, xlsx, csv, print }

/// PDF / Excel / CSV / Print for the Rapports screen.
///
/// All four start the same way: fetch ONE fresh [ReportOverview] (with the
/// period's full sales list) through the screen's own notifier, which also
/// puts that object on screen. The PDF, the spreadsheet and the printout are
/// then rendered from that object — the numbers cannot differ from what the
/// page shows, and they always use the period selected in the toolbar.
class ReportExporter {
  /// Returns the path the file was saved to, or null (Print, or the user
  /// cancelled the save dialog).
  static Future<String?> export({required WidgetRef ref, required ReportExportFormat format}) async {
    final overview = await ref.read(reportOverviewProvider.notifier).fetchForExport();
    final baseName = _baseName(overview);
    final dialogTitle = trRead(ref, 'reports.export_dialog_title');

    switch (format) {
      case ReportExportFormat.pdf:
        final bytes = await ReportPdf.build(overview);
        return _save(bytes, '$baseName.pdf', 'pdf', dialogTitle);
      case ReportExportFormat.print:
        final bytes = await ReportPdf.build(overview);
        // Windows print dialog with preview; same PDF as the PDF button.
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: baseName);
        return null;
      case ReportExportFormat.xlsx:
        final bytes = XlsxWriter.build(ReportSheets.build(overview));
        return _save(bytes, '$baseName.xlsx', 'xlsx', dialogTitle);
      case ReportExportFormat.csv:
        final csv = ReportSheets.toCsv(ReportSheets.build(overview));
        // BOM so Excel reads the accents as UTF-8.
        final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
        return _save(bytes, '$baseName.csv', 'csv', dialogTitle);
    }
  }

  /// `rapport_2026-09-01_2026-09-18` (or `rapport_2026-09-18` for one day).
  static String _baseName(ReportOverview d) {
    final f = DateFormat('yyyy-MM-dd');
    final start = f.format(d.period.start);
    final end = f.format(d.period.end);
    return start == end ? 'rapport_$start' : 'rapport_${start}_$end';
  }

  static Future<String?> _save(Uint8List bytes, String fileName, String extension, String title) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: title,
      fileName: fileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: [extension],
    );
    if (path == null) return null;
    // On desktop the dialog only returns the chosen path (bytes are used by
    // mobile/web), so the file is written here.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final target = path.toLowerCase().endsWith('.$extension') ? path : '$path.$extension';
      await File(target).writeAsBytes(bytes, flush: true);
      return target;
    }
    return path;
  }
}
