import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/features/reports/domain/entities/my_report.dart';
import 'package:store_pos/features/sales/domain/entities/sale.dart';

Map<String, dynamic> _order({bool served = false, String id = 'ab12cd34-0000-4000-8000-000000000000'}) => {
      'id': id,
      'receipt_number': id.substring(0, 8),
      'occurred_at': '2026-09-18 14:35:00',
      'total': '28.00',
      'paid_amount': '28.00',
      'payment_status': 'PAID',
      'payment_method': 'CASH',
      'is_served': served,
      'served_at': served ? '2026-09-18 14:40:00' : null,
      'served_by_name': served ? 'Ahmed' : null,
      'receipt_printed_at': served ? '2026-09-18 14:40:00' : null,
      'receipt_print_count': served ? 2 : 0,
      'items_count': 3,
      'items': [
        {'product_id': 'p1', 'name': 'Café Americain', 'quantity': 2, 'unit_price': '10.00', 'subtotal': '20.00'},
        {'product_id': 'p2', 'name': 'Croissant', 'quantity': 1, 'unit_price': '8.00', 'subtotal': '8.00'},
      ],
    };

void main() {
  group('MyOrder', () {
    test('parses an order that is still à servir', () {
      final o = MyOrder.fromJson(_order());
      expect(o.receiptNumber, 'ab12cd34');
      expect(o.total, 28.0);
      expect(o.isPaid, isTrue);
      expect(o.isServed, isFalse);
      expect(o.servedAt, isNull);
      expect(o.items.map((l) => [l.name, l.quantity]), [
        ['Café Americain', 2],
        ['Croissant', 1],
      ]);
      expect(o.itemsCount, 3);
      // naive local timestamp, like Sale.occurredAt
      expect(o.occurredAt, DateTime(2026, 9, 18, 14, 35));
    });

    test('parses a served order with its serving metadata', () {
      final o = MyOrder.fromJson(_order(served: true));
      expect(o.isServed, isTrue);
      expect(o.servedAt, DateTime(2026, 9, 18, 14, 40));
      expect(o.servedByName, 'Ahmed');
      expect(o.receiptPrintCount, 2);
    });

    test('an unpaid order keeps its payment status (serving never pays it)', () {
      final json = _order()
        ..['payment_status'] = 'PENDING'
        ..['paid_amount'] = '0.00';
      final o = MyOrder.fromJson(json);
      expect(o.paymentStatus, SalePaymentStatus.pending);
      expect(o.isPaid, isFalse);
      expect(o.remaining, 28.0);
    });
  });

  group('MyOrdersPage', () {
    test('hasMore reflects the server total', () {
      final page = MyOrdersPage.fromJson({
        'items': [_order()],
        'total': 45,
        'page': 1,
        'pageSize': 30,
      });
      expect(page.items, hasLength(1));
      expect(page.hasMore, isTrue);

      final last = MyOrdersPage.fromJson({'items': [], 'total': 30, 'page': 1, 'pageSize': 30});
      expect(last.hasMore, isFalse);
    });
  });

  group('MyReport', () {
    final json = {
      'generated_at': '2026-09-18 16:00:00',
      'cashier': {'id': 'c-1', 'name': 'Ahmed'},
      'period': {'key': 'today', 'start': '2026-09-18 00:00:00', 'end': '2026-09-18 23:59:59', 'days': 1},
      'store': {'name': 'Café Central', 'address': null, 'phone': '0600'},
      'kpis': {
        'revenue': '2450.00',
        'order_count': 42,
        'items_sold': 137,
        'average_ticket': '58.33',
        'collected': '2400.00',
        'outstanding': '50.00',
      },
      'payments': {
        'methods': [
          {'method': 'CASH', 'amount': '2000.00', 'count': 30, 'percent': 83.3},
        ],
        'total_collected': '2400.00',
        'change_given': '12.00',
        'outstanding': '50.00',
        'unpaid': {'count': 1, 'amount': '30.00'},
        'partial': {'count': 1, 'remaining': '20.00'},
      },
      'serving': {'to_serve_total': 3, 'served_in_period': 39},
      'products': [
        {'product_id': 'p1', 'name': 'Café Americain', 'quantity': 42, 'revenue': '420.00'},
        {'product_id': 'p2', 'name': 'Croissant', 'quantity': 31, 'revenue': '248.00'},
      ],
      'orders': null,
      'orders_truncated': false,
    };

    test('maps the KPIs and this cashier\'s product quantities', () {
      final r = MyReport.fromJson(json);
      expect(r.cashierId, 'c-1');
      expect(r.cashierName, 'Ahmed');
      expect(r.kpis.revenue, 2450.0);
      expect(r.kpis.orderCount, 42);
      expect(r.kpis.itemsSold, 137);
      expect(r.kpis.averageTicket, closeTo(58.33, 0.001));
      expect(r.products.map((p) => [p.name, p.quantity]), [
        ['Café Americain', 42],
        ['Croissant', 31],
      ]);
      expect(r.toServeTotal, 3);
      expect(r.servedInPeriod, 39);
      expect(r.payments.unpaidCount, 1);
      expect(r.payments.partialRemaining, 20.0);
      expect(r.orders, isNull);
      expect(r.periodKey, 'today');
    });

    test('includes the order list when the server sends it (printed report)', () {
      final r = MyReport.fromJson({
        ...json,
        'orders': [_order(), _order(served: true, id: 'ff00ff00-0000-4000-8000-000000000000')],
      });
      expect(r.orders, hasLength(2));
      expect(r.orders!.last.isServed, isTrue);
    });

    test('empty is a safe zero report', () {
      expect(MyReport.empty.kpis.revenue, 0);
      expect(MyReport.empty.products, isEmpty);
      expect(MyReport.empty.orders, isNull);
    });

    test('a blank store name falls back to STORE POS', () {
      final r = MyReport.fromJson({
        ...json,
        'store': {'name': '  '},
      });
      expect(r.storeName, 'STORE POS');
    });
  });

  group('Sale serving metadata (admin visibility)', () {
    Map<String, dynamic> saleJson(Map<String, dynamic> extra) => {
          'id': 's1',
          'payment_status': 'PAID',
          'subtotal': '28.00',
          'discount_total': '0',
          'tax_total': '0',
          'total': '28.00',
          'occurred_at': '2026-09-18 14:35:00',
          'user_id': 'c-1',
          'cashier_name': 'Ahmed',
          'items': <dynamic>[],
          'payments': <dynamic>[],
          ...extra,
        };

    test('served sale exposes who/when', () {
      final s = Sale.fromJson(saleJson({
        'served_at': '2026-09-18 14:40:00',
        'served_by_name': 'Ahmed',
        'receipt_print_count': 2,
      }));
      expect(s.isServed, isTrue);
      expect(s.servedAt, DateTime(2026, 9, 18, 14, 40));
      expect(s.servedByName, 'Ahmed');
      expect(s.receiptPrintCount, 2);
    });

    test('a sale without serving fields (old server / legacy) is simply not served', () {
      final s = Sale.fromJson(saleJson({}));
      expect(s.isServed, isFalse);
      expect(s.receiptPrintCount, 0);
      // and nothing else about the sale changed
      expect(s.total, 28.0);
      expect(s.cashierName, 'Ahmed');
    });
  });
}
