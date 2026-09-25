import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/features/reports/domain/entities/my_report.dart';
import 'package:store_pos/features/reports/presentation/utils/cashier_report_pdf.dart';
import 'package:store_pos/features/reports/presentation/utils/cashier_report_printer.dart';

Map<String, dynamic> _order(int i, {bool served = false, String name = 'Café Americain'}) => {
      'id': '${i.toString().padLeft(8, '0')}-0000-4000-8000-000000000000',
      'receipt_number': i.toString().padLeft(8, '0'),
      'occurred_at': '2026-09-18 14:35:00',
      'total': '28.00',
      'paid_amount': '28.00',
      'payment_status': i.isEven ? 'PAID' : 'PENDING',
      'is_served': served,
      'served_at': served ? '2026-09-18 14:40:00' : null,
      'receipt_print_count': served ? 1 : 0,
      'items_count': 3,
      'items': [
        {'product_id': 'p1', 'name': name, 'quantity': 2, 'unit_price': '10.00', 'subtotal': '20.00'},
        {'product_id': 'p2', 'name': 'Croissant', 'quantity': 1, 'unit_price': '8.00', 'subtotal': '8.00'},
      ],
    };

MyReport _report({
  List<Map<String, dynamic>>? orders,
  String periodKey = 'today',
  String cashier = 'Ahmed',
  String start = '2026-09-18 00:00:00',
  String end = '2026-09-18 23:59:59',
  List<Map<String, dynamic>>? products,
}) {
  return MyReport.fromJson({
    'generated_at': '2026-09-18 16:00:00',
    'cashier': {'id': 'c-1', 'name': cashier},
    'period': {'key': periodKey, 'start': start, 'end': end, 'days': 1},
    'store': {'name': 'Café Central', 'address': '12 rue X', 'phone': '0600'},
    'kpis': {
      'revenue': '2450.00',
      'order_count': orders?.length ?? 0,
      'items_sold': 137,
      'average_ticket': '58.33',
      'collected': '2400.00',
      'outstanding': '50.00',
    },
    'payments': {
      'methods': [
        {'method': 'CASH', 'amount': '2000.00', 'count': 30, 'percent': 83.3},
        {'method': 'CARD', 'amount': '400.00', 'count': 5, 'percent': 16.7},
      ],
      'total_collected': '2400.00',
      'change_given': '12.00',
      'outstanding': '50.00',
      'unpaid': {'count': 1, 'amount': '30.00'},
      'partial': {'count': 1, 'remaining': '20.00'},
    },
    'serving': {'to_serve_total': 1, 'served_in_period': 1},
    'products': products ??
        [
          {'product_id': 'p1', 'name': 'Café Americain', 'quantity': 42, 'revenue': '420.00'},
          {'product_id': 'p2', 'name': 'Croissant', 'quantity': 31, 'revenue': '248.00'},
        ],
    'orders': orders,
    'orders_truncated': false,
  });
}

bool _isPdf(List<int> bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

void main() {
  group('CashierReportPdf.build', () {
    test('produces a PDF for a normal report', () async {
      final bytes = await CashierReportPdf.build(
        _report(orders: [_order(1), _order(2, served: true)]),
      );
      expect(_isPdf(bytes), isTrue);
      expect(bytes.length, greaterThan(1000));
    });

    test('still produces a PDF when the cashier sold nothing', () async {
      final bytes = await CashierReportPdf.build(_report(orders: [], products: []));
      expect(_isPdf(bytes), isTrue);
    });

    test('does not fail on non-Latin product names (Arabic) or on a missing order list', () async {
      final withArabic = await CashierReportPdf.build(
        _report(orders: [_order(1, name: 'قهوة أمريكية')], products: [
          {'product_id': 'p1', 'name': 'قهوة أمريكية', 'quantity': 3, 'revenue': '30.00'},
        ]),
      );
      expect(_isPdf(withArabic), isTrue);

      final noOrders = await CashierReportPdf.build(_report(orders: null));
      expect(_isPdf(noOrders), isTrue);
    });

    test('paginates a long order list without failing', () async {
      final bytes = await CashierReportPdf.build(
        _report(orders: [for (var i = 1; i <= 400; i++) _order(i, served: i.isEven)]),
      );
      expect(_isPdf(bytes), isTrue);
    });
  });

  group('CashierReportPdf.periodText', () {
    test('names the period and its dates', () {
      expect(CashierReportPdf.periodText(_report()), "Aujourd'hui (18/09/2026)");
      expect(
        CashierReportPdf.periodText(_report(
          periodKey: 'week',
          start: '2026-09-14 00:00:00',
          end: '2026-09-20 23:59:59',
        )),
        'Cette semaine (14/09/2026 au 20/09/2026)',
      );
      expect(CashierReportPdf.periodText(_report(periodKey: 'yesterday')), 'Hier (18/09/2026)');
    });

    test('a custom range reads as a range, a single custom day as one date', () {
      expect(
        CashierReportPdf.periodText(_report(
          periodKey: 'custom',
          start: '2026-09-01 00:00:00',
          end: '2026-09-10 23:59:59',
        )),
        'Du 01/09/2026 au 10/09/2026',
      );
      expect(CashierReportPdf.periodText(_report(periodKey: 'custom')), 'Le 18/09/2026');
    });
  });

  group('CashierReportPrinter.fileName', () {
    test('is filesystem-safe and names the cashier and the day', () {
      expect(CashierReportPrinter.fileName(_report()), 'rapport-ahmed-2026-09-18');
      expect(CashierReportPrinter.fileName(_report(cashier: 'Sara El Amrani')), 'rapport-sara-el-amrani-2026-09-18');
      expect(CashierReportPrinter.fileName(_report(cashier: 'قهوة')), startsWith('rapport-'));
    });
  });
}
