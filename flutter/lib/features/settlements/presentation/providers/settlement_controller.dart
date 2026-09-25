import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/network/api_exception.dart';
import '../../../reports/presentation/providers/my_report_provider.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../../domain/entities/settlement.dart';
import 'settlement_provider.dart';
import '../utils/settlement_pdf.dart';

/// What happened when the cashier pressed IMPRIMER LE JUSTIFICATIF.
enum SettlementCreateOutcome {
  /// Created on the server AND the OS print dialog was confirmed.
  created,

  /// Created on the server, but the print dialog was cancelled or failed.
  /// The settlement still exists — it is NOT retried and NOT rolled back
  /// (spec §6: the server creates the settlement; printing is a
  /// presentation step on top of an already-real record). The cashier can
  /// always reach it again via [SettlementApi.fetchProof] ("VOIR").
  createdPrintFailed,

  /// No orders were ticked.
  noSelection,

  /// The server rejected the request — most commonly because one of the
  /// selected orders was already settled by a concurrent request (spec
  /// §10). Nothing was created.
  rejected,

  /// No connection / unexpected failure. Nothing was created.
  failed,
}

class SettlementCreateResult {
  final SettlementCreateOutcome outcome;
  final CashierSettlement? settlement;
  final String? message;

  const SettlementCreateResult(this.outcome, {this.settlement, this.message});
}

/// Runs "IMPRIMER LE JUSTIFICATIF" (spec §6/§13/§25): create the
/// settlement first (the server is the single source of truth for what
/// counts as justified — see cashierSettlementService.createSettlement),
/// then best-effort print the result. A cancelled or failed print dialog
/// never un-creates the settlement and is never retried automatically —
/// unlike order-serving, there is deliberately no "reprint" path for the
/// cashier (spec §21/§26): the only way to see it again is [VOIR].
class SettlementController {
  final Ref _ref;

  const SettlementController(this._ref);

  /// The store's name/address for the printed header — the same
  /// receipt-settings the POS/receipt printing already uses (see
  /// order_serve_controller.dart), so a justificatif and a receipt never
  /// disagree about which store they're from.
  String get _storeName => _ref.read(receiptSettingsProvider).storeName;
  String get _storeAddress => _ref.read(receiptSettingsProvider).storeAddress;

  Future<SettlementCreateResult> createAndPrint(List<String> saleIds) async {
    if (saleIds.isEmpty) {
      return const SettlementCreateResult(SettlementCreateOutcome.noSelection);
    }

    final Map<String, dynamic> data;
    try {
      data = await _ref.read(settlementApiProvider).createSettlement(saleIds);
    } on ApiException catch (e) {
      if (e.code == 'NETWORK_ERROR') {
        return const SettlementCreateResult(SettlementCreateOutcome.failed);
      }
      return SettlementCreateResult(SettlementCreateOutcome.rejected, message: e.message);
    } catch (_) {
      return const SettlementCreateResult(SettlementCreateOutcome.failed);
    }

    final settlement = CashierSettlement.fromJson(
      (data['settlement'] as Map<String, dynamic>?) ?? const {},
    );

    // Whatever happens with printing from here, the settlement is real —
    // refresh every list that must now reflect it (orders leave
    // "disponibles", appear under "déjà justifiées" — spec §7/§9).
    refreshLists();

    try {
      final bytes = await SettlementPdf.build(settlement, storeName: _storeName, storeAddress: _storeAddress);
      final printed = await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'justificatif-${settlement.settlementNumber}',
      );
      return SettlementCreateResult(
        printed ? SettlementCreateOutcome.created : SettlementCreateOutcome.createdPrintFailed,
        settlement: settlement,
      );
    } catch (_) {
      return SettlementCreateResult(SettlementCreateOutcome.createdPrintFailed, settlement: settlement);
    }
  }

  /// "VOIR LE JUSTIFICATIF" — reprints nothing server-side, just re-fetches
  /// and re-opens the same, already-created document in the OS print/
  /// preview dialog (same viewer used for receipts — Printing.layoutPdf
  /// doubles as "view" throughout this app, there is no separate PDF
  /// viewer).
  Future<Uint8ListResult> viewAgain(String settlementId) async {
    try {
      final data = await _ref.read(settlementApiProvider).fetchProof(settlementId);
      final settlement = CashierSettlement.fromJson(
        (data['settlement'] as Map<String, dynamic>?) ?? const {},
      );
      final bytes = await SettlementPdf.build(settlement, storeName: _storeName, storeAddress: _storeAddress);
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'justificatif-${settlement.settlementNumber}',
      );
      return Uint8ListResult.ok(bytes, settlement);
    } on ApiException catch (e) {
      return Uint8ListResult.failed(e.message);
    } catch (_) {
      return const Uint8ListResult.failed(null);
    }
  }

  void refreshLists() {
    _ref.invalidate(eligibleOrdersProvider);
    _ref.invalidate(settlementSummaryProvider);
    _ref.invalidate(mySettlementsProvider);
    // Cashier and admin totals both derive from the same server figures
    // (spec §28's "déjà payé"/"à payer" mirror what admin sees), so the
    // personal report's own KPIs (order counts) stay consistent too.
    _ref.invalidate(myReportProvider);
    _ref.read(selectedOrderIdsProvider.notifier).state = <String>{};
  }
}

class Uint8ListResult {
  final List<int>? bytes;
  final CashierSettlement? settlement;
  final String? error;

  const Uint8ListResult.ok(this.bytes, this.settlement) : error = null;
  const Uint8ListResult.failed(this.error)
      : bytes = null,
        settlement = null;

  bool get isOk => bytes != null;
}

final settlementControllerProvider = Provider<SettlementController>((ref) {
  return SettlementController(ref);
});
