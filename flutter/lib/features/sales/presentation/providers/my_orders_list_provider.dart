import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../reports/domain/entities/my_report.dart';
import '../../../reports/presentation/providers/reports_provider.dart';

/// Filters of the cashier's Ventes screen (Toutes / À servir / Servies /
/// Payées / Non payées). Applied by the SERVER (`serve_status` /
/// `payment_status` on GET /reports/my-orders), so a cashier with a long
/// history never downloads everything just to see today's queue.
enum MyOrdersFilter { all, toServe, served, paid, unpaid }

extension MyOrdersFilterX on MyOrdersFilter {
  String get serveStatus {
    switch (this) {
      case MyOrdersFilter.toServe:
        return 'to_serve';
      case MyOrdersFilter.served:
        return 'served';
      case MyOrdersFilter.all:
      case MyOrdersFilter.paid:
      case MyOrdersFilter.unpaid:
        return 'all';
    }
  }

  String? get paymentStatus {
    switch (this) {
      case MyOrdersFilter.paid:
        return 'PAID';
      case MyOrdersFilter.unpaid:
        return 'UNPAID';
      case MyOrdersFilter.all:
      case MyOrdersFilter.toServe:
      case MyOrdersFilter.served:
        return null;
    }
  }
}

final myOrdersFilterProvider =
    StateProvider.autoDispose<MyOrdersFilter>((ref) => MyOrdersFilter.all);

/// Bumped after an order is served / reprinted so an open Ventes list reloads
/// in place. (Nothing happens if that screen is not open.)
final myOrdersRefreshProvider = StateProvider<int>((ref) => 0);

/// Receipt-number search (prefix match, server side).
final myOrdersSearchProvider = StateProvider.autoDispose<String>((ref) => '');

class MyOrdersListState {
  final List<MyOrder> items;
  final int total;
  final int page;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  const MyOrdersListState({
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  bool get hasMore => items.length < total;

  MyOrdersListState copyWith({
    List<MyOrder>? items,
    int? total,
    int? page,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return MyOrdersListState(
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Paged list behind the cashier's Ventes screen.
class MyOrdersListNotifier extends StateNotifier<MyOrdersListState> {
  final Ref _ref;
  int _generation = 0;

  static const int _pageSize = 30;

  MyOrdersListNotifier(this._ref) : super(const MyOrdersListState()) {
    _ref.listen<MyOrdersFilter>(myOrdersFilterProvider, (_, __) => reload());
    _ref.listen<String>(myOrdersSearchProvider, (_, __) => reload());
    _ref.listen<int>(myOrdersRefreshProvider, (_, __) => reload(keepRows: true));
    reload();
  }

  Future<MyOrdersPage> _fetch(int page) async {
    final filter = _ref.read(myOrdersFilterProvider);
    final data = await _ref.read(reportsApiProvider).fetchMyOrders(
          serveStatus: filter.serveStatus,
          paymentStatus: filter.paymentStatus,
          search: _ref.read(myOrdersSearchProvider),
          page: page,
          pageSize: _pageSize,
        );
    return MyOrdersPage.fromJson(data);
  }

  /// First page again. On a background refresh (e.g. right after serving an
  /// order) the current rows stay on screen until the new ones arrive; a new
  /// filter/search drops them because they belong to a different query.
  Future<void> reload({bool keepRows = false}) async {
    final generation = ++_generation;
    state = keepRows
        ? state.copyWith(clearError: true)
        : const MyOrdersListState(loading: true);
    try {
      final result = await _fetch(1);
      // A newer request (another filter picked meanwhile) wins.
      if (!mounted || generation != _generation) return;
      state = MyOrdersListState(
        items: result.items,
        total: result.total,
        page: 1,
        loading: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(loading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final generation = _generation;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final result = await _fetch(state.page + 1);
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        total: result.total,
        page: state.page + 1,
        loadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(loadingMore: false, error: error);
    }
  }
}

final myOrdersListProvider =
    StateNotifierProvider.autoDispose<MyOrdersListNotifier, MyOrdersListState>((ref) {
  // A different signed-in user gets a brand-new list.
  ref.watch(authProvider.select((s) => s.user?.id));
  return MyOrdersListNotifier(ref);
});
