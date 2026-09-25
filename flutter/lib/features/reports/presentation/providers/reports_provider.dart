import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../../../pos/presentation/providers/sale_provider.dart';
import '../../../sales/domain/entities/sale.dart';
import '../../data/datasources/cashier_reports_api.dart';
import '../../domain/entities/cashier_sales_report.dart';
import '../../domain/entities/report_overview.dart';
import '../../domain/entities/report_period.dart';
import '../../domain/entities/reports_models.dart';

/// The Rapports screen's single filter state (spec §4). Every section
/// below watches this — one change here refreshes the whole page with
/// one consistent [start, end], never a mix of periods across cards.
final reportFilterProvider = StateProvider<ReportDateFilter>((ref) => ReportDateFilter.initial);

final reportsApiProvider = Provider<CashierReportsApi>((ref) {
  return CashierReportsApi(ref.watch(apiClientProvider));
});

/// A manual "Actualiser" bump (spec §5): incrementing this invalidates
/// every provider below without changing the filter itself — needed for
/// /reports/stock, which has no date range to react to a filter change.
final reportRefreshTickProvider = StateProvider<int>((ref) => 0);

/// The single data source of the redesigned Rapports screen AND of its
/// PDF / Excel / CSV / Print exports.
///
/// One request (`GET /reports/overview`) returns every section for the
/// selected period, computed on the server from one snapshot — so the
/// screen and every export show identical numbers, and switching the period
/// costs one round trip instead of eight. Reloads when the filter changes
/// or when [reportRefreshTickProvider] is bumped ("Actualiser").
class ReportOverviewNotifier extends StateNotifier<AsyncValue<ReportOverview>> {
  final Ref _ref;
  int _generation = 0;

  ReportOverviewNotifier(this._ref) : super(const AsyncValue.loading()) {
    _ref.listen<ReportDateFilter>(reportFilterProvider, (_, __) => load());
    _ref.listen<int>(reportRefreshTickProvider, (_, __) => load(keepPrevious: true));
    load();
  }

  /// [keepPrevious]: on a manual refresh the old numbers stay visible under
  /// a thin progress bar; on a period change they are dropped, because they
  /// would belong to a different period than the one now selected.
  Future<void> load({bool keepPrevious = false}) async {
    final filter = _ref.read(reportFilterProvider);
    if (!filter.isReady) return; // custom range not picked yet

    final generation = ++_generation;
    state = keepPrevious
        ? const AsyncLoading<ReportOverview>().copyWithPrevious(state)
        : const AsyncValue<ReportOverview>.loading();
    try {
      final data = await _ref.read(reportsApiProvider).fetchOverview(filter.toQuery());
      // A newer request (another period picked meanwhile) wins.
      if (!mounted || generation != _generation) return;
      state = AsyncValue.data(ReportOverview.fromJson(data));
    } catch (error, stack) {
      if (!mounted || generation != _generation) return;
      state = AsyncValue<ReportOverview>.error(error, stack);
    }
  }

  /// Fetches a FRESH overview including the period's full sales list, for
  /// PDF / Excel / Print, and adopts it as the on-screen data too — so what
  /// is printed and what is displayed are the very same object, even if a
  /// sale was rung up since the screen last loaded.
  Future<ReportOverview> fetchForExport() async {
    final filter = _ref.read(reportFilterProvider);
    final data = await _ref.read(reportsApiProvider).fetchOverview(
          filter.toQuery(),
          includeSales: true,
        );
    final overview = ReportOverview.fromJson(data);
    if (mounted && identical(filter, _ref.read(reportFilterProvider))) {
      _generation++;
      state = AsyncValue.data(overview);
    }
    return overview;
  }
}

final reportOverviewProvider = StateNotifierProvider.autoDispose<ReportOverviewNotifier,
    AsyncValue<ReportOverview>>((ref) => ReportOverviewNotifier(ref));

/// KPI row (spec §6). Empty (not loading forever) until a custom range
/// has both dates picked — see [ReportDateFilter.isReady].
final reportKpisProvider = FutureProvider<DashboardOverview>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) return DashboardOverview.empty;
  final data = await ref.watch(reportsApiProvider).fetchKpis(filter.toQuery());
  return DashboardOverview.fromJson(data);
});

/// Revenue evolution chart (spec §7).
final reportRevenueSeriesProvider = FutureProvider<List<RevenueBucket>>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) return const [];
  final data = await ref.watch(reportsApiProvider).fetchRevenueSeries(filter.toQuery());
  return (data['buckets'] as List<dynamic>? ?? const [])
      .map((raw) => RevenueBucket.fromJson(raw as Map<String, dynamic>))
      .toList();
});

/// Sales summary + payment analysis (spec §8/§9) — one request backs both
/// sections (see reportService.js#salesSummary).
final reportSalesSummaryProvider = FutureProvider<SalesSummaryReport>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) return SalesSummaryReport.empty;
  final data = await ref.watch(reportsApiProvider).fetchSalesSummary(filter.toQuery());
  return SalesSummaryReport.fromJson(data);
});

/// Cashier performance table (spec §10). Client-side sortable (see
/// cashier_performance_section.dart) — the full ranking is fetched once
/// per period rather than re-fetched per sort column.
final reportCashierRankingProvider = FutureProvider<List<CashierRankingEntry>>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) return const [];
  final data = await ref.watch(reportsApiProvider).fetchCashierRanking(filter.toQuery());
  return (data['cashiers'] as List<dynamic>? ?? const [])
      .map((raw) => CashierRankingEntry.fromJson(raw as Map<String, dynamic>))
      .toList();
});

/// Top products (spec §12).
final reportTopProductsProvider = FutureProvider<List<ArticleSoldEntry>>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) return const [];
  final data = await ref.watch(reportsApiProvider).fetchTopProducts(filter.toQuery(), limit: 10);
  return (data['articles'] as List<dynamic>? ?? const [])
      .map((raw) => ArticleSoldEntry.fromJson(raw as Map<String, dynamic>))
      .toList();
});

/// Expenses (spec §13).
final reportExpensesProvider = FutureProvider<ExpensesReport>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) return ExpensesReport.empty;
  final data = await ref.watch(reportsApiProvider).fetchExpenses(filter.toQuery());
  return ExpensesReport.fromJson(data);
});

/// Stock (spec §14) — not period-based (a snapshot of "now"), so this
/// only reacts to [reportRefreshTickProvider], never to [reportFilterProvider].
final reportStockProvider = FutureProvider<StockReport>((ref) async {
  ref.watch(reportRefreshTickProvider);
  final data = await ref.watch(reportsApiProvider).fetchStock();
  return StockReport.fromJson(data);
});

/// Cashier-detail drill-down (spec §11) — tapping a row in the
/// performance table. Family-keyed so switching cashiers doesn't refetch
/// the whole ranking, and keyed on the filter's query string so it
/// refreshes when the manager changes the period while the detail screen
/// is open.
final reportCashierDetailProvider =
    FutureProvider.family<CashierSalesReport, String>((ref, cashierId) async {
  final filter = ref.watch(reportFilterProvider);
  if (!filter.isReady) {
    return const CashierSalesReport(summary: CashierReportSummary.empty);
  }
  final query = filter.toQuery();
  final data = await ref.watch(reportsApiProvider).fetchCashierSalesReport(
        cashierId: cashierId,
        period: query['period'] as String?,
        from: query['from'] as String?,
        to: query['to'] as String?,
        groupBy: 'day',
      );
  return CashierSalesReport.fromJson(data);
});

/// Pagination state for "Transactions récentes" (spec §15/§21): a
/// StateNotifier (rather than a plain FutureProvider) because it needs to
/// remember which page it's on AND reset to page 1 whenever the filter
/// changes — a stale "page 4" surviving a period switch would silently
/// show the wrong data instead of the requested period's start.
class ReportTransactionsState {
  final List<Sale> items;
  final int page;
  final int pageSize;
  final int total;

  const ReportTransactionsState({
    this.items = const [],
    this.page = 1,
    this.pageSize = 10,
    this.total = 0,
  });

  int get pageCount => total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
}

class ReportTransactionsNotifier extends StateNotifier<AsyncValue<ReportTransactionsState>> {
  final Ref _ref;
  static const _pageSize = 10;

  ReportTransactionsNotifier(this._ref) : super(const AsyncValue.loading()) {
    _ref.listen<ReportDateFilter>(reportFilterProvider, (_, __) => load(page: 1));
    load(page: 1);
  }

  Future<void> load({required int page}) async {
    final filter = _ref.read(reportFilterProvider);
    if (!filter.isReady) {
      state = const AsyncValue.data(ReportTransactionsState());
      return;
    }
    state = const AsyncValue.loading();
    try {
      final query = filter.toQuery();
      final api = _ref.read(salesApiProvider);
      final data = await api.fetchSalesPage(
        period: query['period'] as String?,
        from: query['from'] as String?,
        to: query['to'] as String?,
        page: page,
        pageSize: _pageSize,
      );
      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => Sale.fromJson(raw as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(ReportTransactionsState(
        items: items,
        page: (data['page'] as num?)?.toInt() ?? page,
        pageSize: (data['pageSize'] as num?)?.toInt() ?? _pageSize,
        total: (data['total'] as num?)?.toInt() ?? items.length,
      ));
    } catch (error, stack) {
      state = AsyncValue<ReportTransactionsState>.error(error, stack).copyWithPrevious(state);
    }
  }

  void goToPage(int page) => load(page: page);
}

final reportTransactionsProvider =
    StateNotifierProvider<ReportTransactionsNotifier, AsyncValue<ReportTransactionsState>>((ref) {
  return ReportTransactionsNotifier(ref);
});
