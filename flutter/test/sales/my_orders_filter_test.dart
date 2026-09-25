import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/features/sales/presentation/providers/my_orders_list_provider.dart';

void main() {
  group('Ventes filters -> server query', () {
    test('Toutes: no restriction', () {
      expect(MyOrdersFilter.all.serveStatus, 'all');
      expect(MyOrdersFilter.all.paymentStatus, isNull);
    });

    test('À servir / Servies map to the serve status', () {
      expect(MyOrdersFilter.toServe.serveStatus, 'to_serve');
      expect(MyOrdersFilter.served.serveStatus, 'served');
      expect(MyOrdersFilter.toServe.paymentStatus, isNull);
      expect(MyOrdersFilter.served.paymentStatus, isNull);
    });

    test('Payées / Non payées map to the payment status and ignore serving', () {
      expect(MyOrdersFilter.paid.paymentStatus, 'PAID');
      expect(MyOrdersFilter.unpaid.paymentStatus, 'UNPAID');
      expect(MyOrdersFilter.paid.serveStatus, 'all');
      expect(MyOrdersFilter.unpaid.serveStatus, 'all');
    });
  });
}
