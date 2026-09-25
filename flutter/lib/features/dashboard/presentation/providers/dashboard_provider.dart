import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../data/datasources/dashboard_api.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../../domain/entities/dashboard_summary.dart';

final dashboardApiProvider = Provider<DashboardApi>((ref) {
  return DashboardApi(ref.watch(apiClientProvider));
});

class DashboardNotifier extends StateNotifier<AsyncValue<DashboardSummary>> {
  final DashboardApi _api;

  DashboardNotifier(this._api) : super(const AsyncValue.loading()) {
    refresh();
  }

  /// Refreshes the legacy summary.
  ///
  /// Only shows the full-page spinner on the very FIRST load. A refresh
  /// triggered by pull-to-refresh or the retry button keeps the current
  /// data on screen while re-fetching, instead of flashing the whole
  /// section back to a blank loading state and then possibly to an error
  /// — which is what made a single transient hiccup look like the
  /// dashboard had died. Mirrors CashiersNotifier.refresh().
  Future<void> refresh() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final summary = await _api.fetch();
      state = AsyncValue.data(summary);
    } catch (error, stack) {
      // Keep the last good summary attached to the error state, so a
      // failed refresh degrades to "stale data + error banner" rather
      // than an empty screen.
      state = AsyncValue<DashboardSummary>.error(error, stack).copyWithPrevious(state);
    }
  }
}

final dashboardProvider =
    StateNotifierProvider<DashboardNotifier, AsyncValue<DashboardSummary>>((ref) {
  return DashboardNotifier(ref.watch(dashboardApiProvider));
});

// ---------------------------------------------------------------------
// Period-aware sections (KPI cards, "Meilleur caissier", "Statut des
// ventes", "Ventes récentes"): all driven by [dashboardPeriodProvider],
// so switching Aujourd'hui / Cette semaine / Ce mois refreshes every
// section at once. The revenue bar chart has its own independent
// Jour/Semaine/Mois toggle ([revenueGranularityProvider]) since the spec
// treats it as a separate control from the summary period selector.
// ---------------------------------------------------------------------

final dashboardPeriodProvider = StateProvider<DashboardPeriod>((ref) => DashboardPeriod.today);

final revenueGranularityProvider =
    StateProvider<RevenueGranularity>((ref) => RevenueGranularity.day);

final dashboardOverviewProvider = FutureProvider.autoDispose<DashboardOverview>((ref) {
  final api = ref.watch(dashboardApiProvider);
  final period = ref.watch(dashboardPeriodProvider);
  return api.fetchOverview(period);
});

final cashierRankingProvider = FutureProvider.autoDispose<List<CashierRankingEntry>>((ref) {
  final api = ref.watch(dashboardApiProvider);
  final period = ref.watch(dashboardPeriodProvider);
  return api.fetchCashierRanking(period);
});

final articlesSoldProvider = FutureProvider.autoDispose<List<ArticleSoldEntry>>((ref) {
  final api = ref.watch(dashboardApiProvider);
  final period = ref.watch(dashboardPeriodProvider);
  return api.fetchArticlesSold(period);
});

final salesStatusProvider = FutureProvider.autoDispose<List<SalesStatusEntry>>((ref) {
  final api = ref.watch(dashboardApiProvider);
  final period = ref.watch(dashboardPeriodProvider);
  return api.fetchSalesStatus(period);
});

final revenueSeriesProvider = FutureProvider.autoDispose<List<RevenueBucket>>((ref) {
  final api = ref.watch(dashboardApiProvider);
  final granularity = ref.watch(revenueGranularityProvider);
  return api.fetchRevenueSeries(granularity);
});

final recentSalesProvider = FutureProvider.autoDispose<List<RecentSale>>((ref) {
  final api = ref.watch(dashboardApiProvider);
  return api.fetchRecentSales(limit: 8);
});
