import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/providers.dart';
import '../../../../core/utils/local_date_range.dart';
import '../../../pos/presentation/providers/sale_provider.dart';
import '../../../reports/data/datasources/cashier_reports_api.dart';
import '../../../reports/domain/entities/cashier_sales_report.dart';
import '../../domain/entities/sale.dart';

/// Filter shown on the Sales screen (spec §15: "All / Paid / Not Paid").
/// "Not Paid" covers both a brand-new unpaid sale (`pending`) and one
/// that's been topped up but not fully settled (`partiallyPaid`) — both
/// are, from the cashier's point of view, still money the customer owes.
enum SaleStatusFilter { all, paid, notPaid }

/// Free-text search box (spec §15: receipt number / cashier / date). All
/// filtering happens client-side over the already-fetched list — the same
/// pattern already used by the Cashiers and Products screens in this app
/// — so typing a search term never triggers a network round trip.
final saleSearchQueryProvider = StateProvider<String>((ref) => '');
final saleStatusFilterProvider = StateProvider<SaleStatusFilter>((ref) => SaleStatusFilter.all);

class SalesNotifier extends StateNotifier<AsyncValue<List<Sale>>> {
  final Ref _ref;

  SalesNotifier(this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  /// Reloads every sale for the store (newest first — spec §16). Only
  /// shows the full-screen spinner on the very first load; a background
  /// refresh (e.g. right after paying a sale) keeps the current list on
  /// screen while it re-fetches, matching CashiersNotifier.refresh.
  Future<void> refresh() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final api = _ref.read(salesApiProvider);
      final raw = await api.fetchSales();
      final sales = raw.map((json) => Sale.fromJson(json)).toList()
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      state = AsyncValue.data(sales);
    } catch (error, stack) {
      state = AsyncValue<List<Sale>>.error(error, stack).copyWithPrevious(state);
    }
  }
}

final salesProvider = StateNotifierProvider<SalesNotifier, AsyncValue<List<Sale>>>((ref) {
  return SalesNotifier(ref);
});

/// The list actually rendered by the Sales screen: [salesProvider]'s data
/// narrowed by [saleSearchQueryProvider] and [saleStatusFilterProvider].
final filteredSalesProvider = Provider<List<Sale>>((ref) {
  final sales = ref.watch(salesProvider).valueOrNull ?? const <Sale>[];
  final query = ref.watch(saleSearchQueryProvider).trim().toLowerCase();
  final filter = ref.watch(saleStatusFilterProvider);

  return sales.where((sale) {
    final matchesStatus = switch (filter) {
      SaleStatusFilter.all => true,
      SaleStatusFilter.paid => sale.status == SalePaymentStatus.paid,
      SaleStatusFilter.notPaid =>
        sale.status == SalePaymentStatus.pending || sale.status == SalePaymentStatus.partiallyPaid,
    };
    if (!matchesStatus) return false;
    if (query.isEmpty) return true;

    final receiptMatch = sale.receiptNumber.toLowerCase().contains(query);
    final cashierMatch = sale.cashierName?.toLowerCase().contains(query) ?? false;
    final noteMatch = sale.note?.toLowerCase().contains(query) ?? false;
    final dateMatch = _dateSearchString(sale.occurredAt).contains(query);
    return receiptMatch || cashierMatch || noteMatch || dateMatch;
  }).toList();
});

String _dateSearchString(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

final cashierReportsApiProvider = Provider<CashierReportsApi>((ref) {
  return CashierReportsApi(ref.watch(apiClientProvider));
});

/// One cashier's receipts for a single calendar day, newest first — powers
/// the Cashier detail screen's Day view (both its own receipt list, and
/// the day drill-down opened from Month view). Fetched straight from the
/// backend with `user_id`/`from`/`to` filters (saleRepository.list already
/// supports all three) rather than downloading every sale in the store and
/// filtering client-side — the store could have thousands of sales overall
/// even for one cashier's one day (spec §10).
final cashierDaySalesProvider =
    FutureProvider.family<List<Sale>, ({String cashierId, DateTime day})>((ref, params) async {
  final api = ref.watch(salesApiProvider);
  final raw = await api.fetchSales(
    userId: params.cashierId,
    from: LocalDateRange.dayStart(params.day),
    to: LocalDateRange.dayEnd(params.day),
  );
  final sales = raw.map((json) => Sale.fromJson(json)).toList()
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return sales;
});

/// Aggregate stats for one cashier on one day — the stat cards at the top
/// of the Cashier detail screen's Day view. Computed by the backend via
/// SQL aggregation (GET /reports/cashier-sales, no `group_by`) instead of
/// summing [cashierDaySalesProvider]'s list client-side, so it stays cheap
/// even for a cashier with a very busy day.
final cashierDaySummaryProvider =
    FutureProvider.family<CashierReportSummary, ({String cashierId, DateTime day})>(
        (ref, params) async {
  final api = ref.watch(cashierReportsApiProvider);
  final data = await api.fetchCashierSalesReport(
    cashierId: params.cashierId,
    from: LocalDateRange.dayStart(params.day),
    to: LocalDateRange.dayEnd(params.day),
  );
  return CashierReportSummary.fromJson(data['summary'] as Map<String, dynamic>? ?? const {});
});

/// One cashier's full month report — top summary + the daily breakdown
/// table (Cashier detail screen's Month view). A single backend call
/// (`group_by=day`) returns both, so switching months never means Flutter
/// re-downloads and re-sums the month's individual sales itself (spec
/// §7/§10).
final cashierMonthReportProvider =
    FutureProvider.family<CashierSalesReport, ({String cashierId, DateTime month})>(
        (ref, params) async {
  final api = ref.watch(cashierReportsApiProvider);
  final data = await api.fetchCashierSalesReport(
    cashierId: params.cashierId,
    from: LocalDateRange.monthStart(params.month),
    to: LocalDateRange.monthEnd(params.month),
    groupBy: 'day',
  );
  return CashierSalesReport.fromJson(data);
});

/// Handles paying an existing NOT-PAID/PARTIALLY-PAID sale (spec §6/§7):
/// posts to POST /api/payments (saleService.addPayment), which updates the
/// SAME sale row rather than creating a new one, then refreshes both the
/// list and returns the updated [Sale] so the caller (e.g. the detail
/// dialog) can show it immediately without waiting for [SalesNotifier] to
/// finish its background refresh.
final salePaymentControllerProvider = Provider<SalePaymentController>((ref) {
  return SalePaymentController(ref);
});

class SalePaymentController {
  final Ref _ref;
  const SalePaymentController(this._ref);

  static const _uuid = Uuid();

  Future<Sale> pay({
    required String saleId,
    required double amount,
    required String paymentMethod,
  }) async {
    final api = _ref.read(salesApiProvider);
    final result = await api.payForSale(
      clientOperationId: _uuid.v4(),
      saleId: saleId,
      amount: amount,
      paymentMethod: paymentMethod,
    );
    final sale = Sale.fromJson(result['sale'] as Map<String, dynamic>);
    // Refresh in the background so the Sales list reflects the new status
    // without blocking on it — the caller already has the fresh [Sale].
    unawaited(_ref.read(salesProvider.notifier).refresh());
    return sale;
  }
}
