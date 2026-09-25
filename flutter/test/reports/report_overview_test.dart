import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/features/reports/domain/entities/report_overview.dart';
import 'package:store_pos/features/reports/presentation/utils/report_pdf.dart';
import 'package:store_pos/features/reports/presentation/utils/report_sheets.dart';
import 'package:store_pos/features/reports/presentation/utils/xlsx_writer.dart';
import 'package:store_pos/features/reports/presentation/widgets/report_widgets.dart';

/// `fixtures/overview_sample.json` is a real payload produced by the
/// backend's reportOverviewService on a hand-computed dataset (6 completed
/// sales, 265.00 revenue, 250.00 expenses).
ReportOverview loadSample() {
  final raw = File('test/reports/fixtures/overview_sample.json').readAsStringSync();
  return ReportOverview.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  group('ReportOverview parsing', () {
    test('reads the KPIs and the period', () {
      final d = loadSample();
      expect(d.kpis.revenue, 265.0);
      expect(d.kpis.saleCount, 6);
      expect(d.kpis.itemsSold, 11);
      expect(d.kpis.estimatedResult, 15.0);
      expect(d.period.days, 2);
      expect(d.period.start, DateTime(2026, 9, 17));
    });

    test('every section adds up to the same totals (dashboard = PDF = Excel)', () {
      final d = loadSample();
      expect(d.ordersByHour.totalOrders, d.kpis.saleCount);
      expect(d.ordersByHour.totalRevenue, d.kpis.revenue);
      expect(d.ordersByHour.hours.fold<int>(0, (s, h) => s + h.orders), d.kpis.saleCount);
      expect(d.cashiers.fold<int>(0, (s, c) => s + c.saleCount), d.kpis.saleCount);
      expect(d.cashiers.fold<double>(0, (s, c) => s + c.revenue), closeTo(d.kpis.revenue, 0.001));
      expect(d.revenueSeries.buckets.fold<double>(0, (s, b) => s + b.revenue), closeTo(d.kpis.revenue, 0.001));
      expect(d.payments.totalCollected + d.payments.outstanding, closeTo(d.kpis.revenue, 0.001));
      expect(d.expenses.total, d.kpis.expenses);
      expect(d.integrityOk, isTrue);
    });

    test('the hourly table keeps 24 rows but shows only the active hour range', () {
      final d = loadSample();
      expect(d.ordersByHour.hours.length, 24);
      final active = d.ordersByHour.activeRange;
      expect(active.first.hour, 8);
      expect(active.last.hour, 23);
      expect(active.firstWhere((h) => h.hour == 12).orders, 2);
    });

    test('an empty period has no active hours', () {
      final d = loadSample();
      final empty = OrdersByHour(hours: d.ordersByHour.hours.map((h) => HourRow(hour: h.hour, label: h.label, orders: 0, revenue: 0)).toList(), totalOrders: 0, totalRevenue: 0);
      expect(empty.activeRange, isEmpty);
    });

    test('builds a light Sale for the existing detail dialog', () {
      final d = loadSample();
      final sale = d.recentSales.first.toSale();
      expect(sale.id, d.recentSales.first.id);
    });
  });

  group('ReportFormat', () {
    test('groups thousands with spaces and keeps two decimals', () {
      expect(ReportFormat.amount(1420), '1 420.00');
      expect(ReportFormat.amount(24580.5), '24 580.50');
      expect(ReportFormat.amount(-1234.5), '-1 234.50');
      expect(ReportFormat.money(75.86), '75.86 DH');
      expect(ReportFormat.integer(1234567), '1 234 567');
      expect(ReportFormat.percent(80), '80 %');
      expect(ReportFormat.percent(33.3), '33.3 %');
    });
  });

  group('Exports render the same overview', () {
    test('PDF is a valid document', () async {
      final bytes = await ReportPdf.build(loadSample());
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(1500));
    });

    test('xlsx is a zip with one worksheet per sheet', () {
      final sheets = ReportSheets.build(loadSample());
      final bytes = XlsxWriter.build(sheets);
      expect(bytes[0], 0x50); // 'P'
      expect(bytes[1], 0x4B); // 'K'
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.contains('xl/worksheets/sheet${sheets.length}.xml'), isTrue);
      expect(text.contains('xl/workbook.xml'), isTrue);
    });

    test('csv carries the same totals as the screen', () {
      final d = loadSample();
      final csv = ReportSheets.toCsv(ReportSheets.build(d));
      expect(csv.contains('265.00'), isTrue);
      expect(csv.contains('TOTAL;6;265.00'), isTrue);
      expect(csv.contains('COMMANDES PAR HEURE'), isTrue);
    });
  });
}
