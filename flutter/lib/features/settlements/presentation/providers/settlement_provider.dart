import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/settlement_api.dart';
import '../../domain/entities/settlement.dart';

/// State behind the cashier work-payment / settlement feature.
///
/// Every provider below watches the signed-in user's id, exactly like
/// myReportProvider (see my_report_provider.dart): if a different person
/// signs in during the same app session, the previous cashier's eligible
/// orders / settlements are dropped, never carried over or mixed in.

final settlementApiProvider = Provider<SettlementApi>((ref) {
  return SettlementApi(ref.watch(apiClientProvider));
});

/// Bumping this refreshes every cashier-side provider below without
/// tearing down the screen — used right after creating a settlement (spec
/// §7/§9: the printed orders must disappear from "disponibles" and appear
/// under "déjà justifiées" immediately).
final settlementRefreshProvider = StateProvider<int>((ref) => 0);

/// "COMMANDES DISPONIBLES POUR JUSTIFICATIF" (spec §4).
final eligibleOrdersProvider = FutureProvider.autoDispose<EligibleOrders>((ref) async {
  ref.watch(authProvider.select((s) => s.user?.id));
  ref.watch(settlementRefreshProvider);
  final data = await ref.watch(settlementApiProvider).fetchEligibleOrders();
  return EligibleOrders.fromJson(data);
});

/// KPI header (spec §18/§28).
final settlementSummaryProvider = FutureProvider.autoDispose<SettlementSummary>((ref) async {
  ref.watch(authProvider.select((s) => s.user?.id));
  ref.watch(settlementRefreshProvider);
  final data = await ref.watch(settlementApiProvider).fetchMySummary();
  return SettlementSummary.fromJson(data);
});

/// "COMMANDES DÉJÀ JUSTIFIÉES", grouped by settlement, newest first (spec
/// §18 — read-only section).
final mySettlementsProvider = FutureProvider.autoDispose<List<CashierSettlement>>((ref) async {
  ref.watch(authProvider.select((s) => s.user?.id));
  ref.watch(settlementRefreshProvider);
  final data = await ref.watch(settlementApiProvider).fetchMySettlements();
  return SettlementsPage.fromJson(data).items;
});

/// The checkboxes the cashier has ticked on the Rapport screen, by sale
/// id. Auto-disposed (and explicitly cleared after a successful print) so
/// leaving the screen — or a just-printed justificatif — never leaves a
/// stale selection referencing orders that are no longer eligible.
final selectedOrderIdsProvider = StateProvider.autoDispose<Set<String>>((ref) => <String>{});

// ---------------------------------------------------------------------
// Admin: "Paiements caissiers"
// ---------------------------------------------------------------------

class AdminSettlementFilter {
  final String? cashierId;
  final String? status;

  const AdminSettlementFilter({this.cashierId, this.status});

  AdminSettlementFilter copyWith({String? Function()? cashierId, String? Function()? status}) {
    return AdminSettlementFilter(
      cashierId: cashierId != null ? cashierId() : this.cashierId,
      status: status != null ? status() : this.status,
    );
  }
}

final adminSettlementFilterProvider =
    StateProvider.autoDispose<AdminSettlementFilter>((ref) => const AdminSettlementFilter());

final adminSettlementRefreshProvider = StateProvider<int>((ref) => 0);

final adminSettlementsProvider = FutureProvider.autoDispose<List<CashierSettlement>>((ref) async {
  ref.watch(adminSettlementRefreshProvider);
  final filter = ref.watch(adminSettlementFilterProvider);
  final data = await ref.watch(settlementApiProvider).adminFetchSettlements(
        cashierId: filter.cashierId,
        status: filter.status,
      );
  return SettlementsPage.fromJson(data).items;
});
