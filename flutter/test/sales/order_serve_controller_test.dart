import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/core/network/api_exception.dart';
import 'package:store_pos/core/network/connection_status.dart';
import 'package:store_pos/features/pos/data/datasources/sales_api.dart';
import 'package:store_pos/features/pos/presentation/providers/sale_provider.dart';
import 'package:store_pos/features/sales/presentation/providers/order_serve_controller.dart';

/// Records what the controller asks the server to do.
class _FakeSalesApi extends Fake implements SalesApi {
  bool served = false;
  int fetches = 0;
  int serves = 0;
  int reprints = 0;
  final List<String> serveOperationIds = [];

  ApiException? fetchError;
  ApiException? reprintError;

  /// Consumed one per serveSale call (null = success).
  final List<ApiException?> serveResults = [];

  @override
  Future<Map<String, dynamic>> fetchSaleById(String id) async {
    fetches++;
    final e = fetchError;
    if (e != null) throw e;
    return {
      'id': id,
      'payment_status': 'PAID',
      'subtotal': '28.00',
      'total': '28.00',
      'occurred_at': '2026-09-18 14:35:00',
      'served_at': served ? '2026-09-18 14:40:00' : null,
      'items': <dynamic>[],
      'payments': <dynamic>[],
    };
  }

  @override
  Future<Map<String, dynamic>> serveSale({
    required String saleId,
    required String clientOperationId,
  }) async {
    serves++;
    serveOperationIds.add(clientOperationId);
    final e = serveResults.isEmpty ? null : serveResults.removeAt(0);
    if (e != null) throw e;
    return {'sale': <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> reprintSale(String saleId) async {
    reprints++;
    final e = reprintError;
    if (e != null) throw e;
    return {'sale': <String, dynamic>{}};
  }
}

const _network = ApiException(code: 'NETWORK_ERROR', message: 'unreachable');
const _alreadyServed = ApiException(
  statusCode: 409,
  code: 'SALE_ALREADY_SERVED',
  message: 'Cette commande a déjà été servie.',
);

void main() {
  late _FakeSalesApi api;
  late ProviderContainer container;
  late int printCalls;
  late bool printConfirmed;
  late bool printThrows;

  OrderServeController controller() {
    final provider = Provider<OrderServeController>((ref) {
      return OrderServeController(
        ref,
        printer: (sale) async {
          printCalls++;
          if (printThrows) throw StateError('printer unavailable');
          return printConfirmed;
        },
      );
    });
    return container.read(provider);
  }

  setUp(() {
    api = _FakeSalesApi();
    container = ProviderContainer(overrides: [salesApiProvider.overrideWithValue(api)]);
    printCalls = 0;
    printConfirmed = true;
    printThrows = false;
  });

  tearDown(() => container.dispose());

  group('IMPRIMER / SERVIR', () {
    test('prints, THEN marks the order served (once, with an idempotency key)', () async {
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.served);
      expect(printCalls, 1);
      expect(api.serves, 1);
      expect(api.serveOperationIds.single, isNotEmpty);
    });

    test('a cancelled print dialog does NOT mark the order served', () async {
      printConfirmed = false;
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.cancelled);
      expect(printCalls, 1);
      expect(api.serves, 0);
    });

    test('a printer / PDF failure does NOT mark the order served', () async {
      printThrows = true;
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.printFailed);
      expect(api.serves, 0);
    });

    test('an order already served elsewhere is not printed again', () async {
      api.served = true;
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.alreadyServed);
      expect(printCalls, 0);
      expect(api.serves, 0);
    });

    test('losing the race at the server (409) is reported as already served', () async {
      api.serveResults.add(_alreadyServed);
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.alreadyServed);
      expect(api.serves, 1);
    });

    test('known offline: nothing is loaded, printed or served', () async {
      container.read(connectionStatusProvider.notifier).reportUnreachable();
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.offline);
      expect(api.fetches, 0);
      expect(printCalls, 0);
      expect(api.serves, 0);
    });

    test('network failure while loading the order: offline, nothing printed', () async {
      api.fetchError = _network;
      final result = await controller().printAndServe('sale-1');

      expect(result.outcome, ServeOutcome.offline);
      expect(printCalls, 0);
      expect(api.serves, 0);
    });

    test('printed but the server is unreachable: retry records it WITHOUT printing again, same key', () async {
      api.serveResults.add(_network);
      final c = controller();

      final first = await c.printAndServe('sale-1');
      expect(first.outcome, ServeOutcome.printedNotRecorded);
      expect(first.operationId, isNotNull);
      expect(printCalls, 1);

      final retry = await c.markServed('sale-1', operationId: first.operationId!);
      expect(retry.outcome, ServeOutcome.served);

      expect(printCalls, 1, reason: 'the receipt must not be printed a second time');
      expect(api.serves, 2);
      expect(api.serveOperationIds.toSet(), hasLength(1), reason: 'both attempts carry the SAME operation id');
    });
  });

  group('RÉIMPRIMER', () {
    test('prints again and records the reprint; never touches the served state', () async {
      api.served = true;
      final result = await controller().reprint('sale-1');

      expect(result.outcome, ServeOutcome.reprinted);
      expect(printCalls, 1);
      expect(api.reprints, 1);
      expect(api.serves, 0, reason: 'reprint must never call the serve endpoint');
    });

    test('a cancelled print is not recorded', () async {
      api.served = true;
      printConfirmed = false;
      final result = await controller().reprint('sale-1');

      expect(result.outcome, ServeOutcome.cancelled);
      expect(api.reprints, 0);
    });

    test('a printer failure is not recorded', () async {
      api.served = true;
      printThrows = true;
      final result = await controller().reprint('sale-1');

      expect(result.outcome, ServeOutcome.printFailed);
      expect(api.reprints, 0);
    });

    test('an order that is not served yet is not reprinted', () async {
      api.served = false;
      final result = await controller().reprint('sale-1');

      expect(result.outcome, ServeOutcome.failed);
      expect(printCalls, 0);
      expect(api.reprints, 0);
    });

    test('paper printed but the audit call failed: reported, nothing else affected', () async {
      api.served = true;
      api.reprintError = _network;
      final result = await controller().reprint('sale-1');

      expect(result.outcome, ServeOutcome.reprintedNotRecorded);
      expect(api.serves, 0);
    });

    test('known offline: nothing is printed', () async {
      container.read(connectionStatusProvider.notifier).reportUnreachable();
      final result = await controller().reprint('sale-1');

      expect(result.outcome, ServeOutcome.offline);
      expect(printCalls, 0);
    });
  });
}
