import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/connection_status.dart';
import '../../../pos/presentation/providers/sale_provider.dart';
import '../../../pos/presentation/utils/receipt_pdf.dart';
import '../../../reports/presentation/providers/my_report_provider.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../../domain/entities/sale.dart';
import '../utils/sale_receipt.dart';
import 'my_orders_list_provider.dart';

/// What happened when the cashier pressed IMPRIMER / SERVIR or RÉIMPRIMER.
enum ServeOutcome {
  /// Printed AND recorded as served. The order moves to "Servies".
  served,

  /// Reprinted a served order (and the reprint was recorded).
  reprinted,

  /// Reprinted, but recording the reprint failed. Nothing else is affected.
  reprintedNotRecorded,

  /// Another client already served this order. Nothing was printed here.
  alreadyServed,

  /// The cashier closed the print dialog. Nothing changed.
  cancelled,

  /// No connection. Nothing was printed and nothing changed.
  offline,

  /// The receipt could not be generated / sent to the printer. The order was
  /// NOT marked as served.
  printFailed,

  /// The receipt WAS printed but the server did not record it as served
  /// (connection lost, server error). Only the "record" step must be
  /// retried — never the print — with the same [ServeResult.operationId].
  printedNotRecorded,

  /// The order could not be loaded / the server refused the request.
  failed,
}

class ServeResult {
  final ServeOutcome outcome;

  /// Server message for [ServeOutcome.failed] / [ServeOutcome.printedNotRecorded].
  final String? message;

  /// Idempotency key of the serve request, kept so a retry after
  /// [ServeOutcome.printedNotRecorded] can never record a second serve.
  final String? operationId;

  const ServeResult(this.outcome, {this.message, this.operationId});
}

/// Runs the cashier's print-and-serve workflow.
///
/// The order matters and is the whole point of this class:
///
///  1. load the sale, generate the receipt;
///  2. send it to the OS print dialog — the existing mechanism, and the same
///     one the POS uses ([Printing.layoutPdf] returns whether the cashier
///     actually confirmed the print);
///  3. ONLY if printing was confirmed, tell the server to mark it served.
///
/// So a cancelled dialog, a printer error or a PDF error can never leave an
/// order marked as served. The server-side serve only touches the serving
/// columns of the sale — nothing is deleted and no report figure changes.
///
/// Serving needs the server (there is no local write queue in this app), so
/// when the connection is known to be down the action is refused up-front
/// instead of printing something that could not be recorded.
class OrderServeController {
  final Ref _ref;

  /// Replaces the real OS print dialog. Only tests pass one, to exercise the
  /// "print confirmed / cancelled / failed" branches without a printer.
  final Future<bool> Function(Sale sale)? _printer;

  const OrderServeController(this._ref, {Future<bool> Function(Sale sale)? printer})
      : _printer = printer;

  static const _uuid = Uuid();

  Future<Sale> _loadSale(String saleId) async {
    final json = await _ref.read(salesApiProvider).fetchSaleById(saleId);
    return Sale.fromJson(json);
  }

  /// true = the cashier confirmed the print, false = cancelled. Throws if the
  /// PDF cannot be built or the printer/OS refuses.
  Future<bool> _print(Sale sale) async {
    final injected = _printer;
    if (injected != null) return injected(sale);
    final settings = _ref.read(receiptSettingsProvider);
    final bytes = await (await buildReceiptPdf(receiptDataFromSale(sale), settings)).save();
    return Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'receipt-${sale.receiptNumber}',
    );
  }

  bool get _knownOffline =>
      _ref.read(connectionStatusProvider) == ConnectionStatus.offline;

  ServeResult _fromApiError(ApiException e) {
    if (e.code == 'NETWORK_ERROR') return const ServeResult(ServeOutcome.offline);
    if (e.code == 'SALE_ALREADY_SERVED') {
      return ServeResult(ServeOutcome.alreadyServed, message: e.message);
    }
    return ServeResult(ServeOutcome.failed, message: e.message);
  }

  /// Refreshes every cashier list so the order leaves "À servir" and shows up
  /// under "Servies" immediately, without restarting the app.
  void refreshLists() {
    _ref.invalidate(myReportProvider);
    _ref.invalidate(myToServeProvider);
    _ref.invalidate(myServedProvider);
    // The Ventes list (a paged notifier) reloads itself in place, keeping its
    // rows on screen meanwhile; if that screen is not open this is a no-op.
    final tick = _ref.read(myOrdersRefreshProvider.notifier);
    tick.state = tick.state + 1;
  }

  /// IMPRIMER / SERVIR.
  Future<ServeResult> printAndServe(String saleId) async {
    if (_knownOffline) return const ServeResult(ServeOutcome.offline);

    final Sale sale;
    try {
      sale = await _loadSale(saleId);
    } on ApiException catch (e) {
      return _fromApiError(e);
    }

    // Served meanwhile by another client: do not print it a second time.
    if (sale.isServed) {
      refreshLists();
      return const ServeResult(ServeOutcome.alreadyServed);
    }

    final bool printed;
    try {
      printed = await _print(sale);
    } catch (_) {
      return const ServeResult(ServeOutcome.printFailed);
    }
    if (!printed) return const ServeResult(ServeOutcome.cancelled);

    return markServed(saleId, operationId: _uuid.v4());
  }

  /// Records the serve on the server. Also used on its own to RETRY after
  /// [ServeOutcome.printedNotRecorded] (the receipt is already printed, so
  /// only this call is repeated). Safe to repeat: the same [operationId] is
  /// applied at most once by the server.
  Future<ServeResult> markServed(String saleId, {required String operationId}) async {
    try {
      await _ref.read(salesApiProvider).serveSale(
            saleId: saleId,
            clientOperationId: operationId,
          );
      refreshLists();
      return ServeResult(ServeOutcome.served, operationId: operationId);
    } on ApiException catch (e) {
      if (e.code == 'SALE_ALREADY_SERVED') {
        refreshLists();
        return ServeResult(ServeOutcome.alreadyServed, message: e.message);
      }
      // Printed, but not recorded: keep the key for the retry.
      return ServeResult(
        ServeOutcome.printedNotRecorded,
        message: e.code == 'NETWORK_ERROR' ? null : e.message,
        operationId: operationId,
      );
    }
  }

  /// RÉIMPRIMER: prints the receipt of an already served order again. The
  /// served state and its timestamp are never modified.
  Future<ServeResult> reprint(String saleId) async {
    if (_knownOffline) return const ServeResult(ServeOutcome.offline);

    final Sale sale;
    try {
      sale = await _loadSale(saleId);
    } on ApiException catch (e) {
      return _fromApiError(e);
    }
    if (!sale.isServed) {
      // Should not happen (the button only exists for served orders); refresh
      // so the UI shows the order where it really is.
      refreshLists();
      return const ServeResult(ServeOutcome.failed);
    }

    final bool printed;
    try {
      printed = await _print(sale);
    } catch (_) {
      return const ServeResult(ServeOutcome.printFailed);
    }
    if (!printed) return const ServeResult(ServeOutcome.cancelled);

    try {
      await _ref.read(salesApiProvider).reprintSale(saleId);
      refreshLists();
      return const ServeResult(ServeOutcome.reprinted);
    } on ApiException {
      // The paper is out; only the audit counter is missing.
      return const ServeResult(ServeOutcome.reprintedNotRecorded);
    }
  }
}

final orderServeControllerProvider = Provider<OrderServeController>((ref) {
  return OrderServeController(ref);
});
