import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/network/api_exception.dart';
import '../../../settings/presentation/providers/receipt_settings_provider.dart';
import '../../domain/entities/settlement.dart';
import 'settlement_provider.dart';
import '../utils/settlement_pdf.dart';

/// "Paiements caissiers" admin actions (spec §22-§23, §26, §33): mark a
/// settlement paid, cancel it, or print an admin-only duplicate copy.
/// Every call here hits `/admin/cashier-settlements/*`, which the backend
/// refuses outright for a cashier role regardless of what this screen
/// shows (see authorize.js's 'cashier_settlements.manage').
class AdminSettlementController {
  final Ref _ref;

  const AdminSettlementController(this._ref);

  void _refresh() {
    _ref.read(adminSettlementRefreshProvider.notifier).state++;
  }

  Future<CashierSettlement?> markPaid(String id) async {
    try {
      final data = await _ref.read(settlementApiProvider).adminMarkPaid(id);
      _refresh();
      return CashierSettlement.fromJson((data['settlement'] as Map<String, dynamic>?) ?? const {});
    } on ApiException {
      rethrow;
    }
  }

  Future<CashierSettlement?> cancel(String id, {String? reason}) async {
    try {
      final data = await _ref.read(settlementApiProvider).adminCancel(id, reason: reason);
      _refresh();
      return CashierSettlement.fromJson((data['settlement'] as Map<String, dynamic>?) ?? const {});
    } on ApiException {
      rethrow;
    }
  }

  /// "RÉIMPRIMER UNE COPIE" — fetches the reprint-flagged settlement, then
  /// prints it clearly marked COPIE / DUPLICATA (spec §26). Never used for
  /// the original print (that only ever happens once, from the cashier's
  /// own IMPRIMER LE JUSTIFICATIF — see SettlementController).
  Future<bool> reprintCopy(String id) async {
    final data = await _ref.read(settlementApiProvider).adminReprint(id);
    _refresh();
    final settlement = CashierSettlement.fromJson(
      (data['settlement'] as Map<String, dynamic>?) ?? const {},
    );
    final settings = _ref.read(receiptSettingsProvider);
    final bytes = await SettlementPdf.build(
      settlement,
      storeName: settings.storeName,
      storeAddress: settings.storeAddress,
      copy: true,
    );
    return Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'justificatif-${settlement.settlementNumber}-copie',
    );
  }
}

final adminSettlementControllerProvider = Provider<AdminSettlementController>((ref) {
  return AdminSettlementController(ref);
});
