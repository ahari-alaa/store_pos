import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/datasources/cashier_reports_api.dart';
import '../../domain/entities/my_report.dart';
import '../../domain/entities/report_period.dart';
import 'reports_provider.dart';

/// State behind the cashier's PERSONAL Rapport screen.
///
/// Everything here is fetched from `/reports/my-*`, which the server always
/// computes for the signed-in cashier (from the auth token). Nothing on the
/// client chooses a cashier id, and every provider below also watches the
/// signed-in user's id, so if another person signs in during the same app
/// session the previous cashier's data is dropped, never re-shown.

/// The period picked on the Rapport screen. Auto-disposed so leaving the
/// screen and coming back starts again on "Aujourd'hui".
final myReportFilterProvider = StateProvider.autoDispose<ReportDateFilter>(
  (ref) => const ReportDateFilter(period: ReportPeriod.today),
);

/// KPIs + products sold (+ payment summary) for the selected period — one
/// server snapshot. Empty (not loading forever) until a custom range has
/// both dates.
final myReportProvider = FutureProvider.autoDispose<MyReport>((ref) async {
  ref.watch(authProvider.select((s) => s.user?.id));
  final filter = ref.watch(myReportFilterProvider);
  if (!filter.isReady) return MyReport.empty;
  final data = await ref.watch(reportsApiProvider).fetchMySales(filter.toQuery());
  return MyReport.fromJson(data);
});

/// Hard stop for paging loops (100 orders/page → 2 000 orders) so a
/// pathological backlog can never spin forever.
const int _maxPages = 20;

Future<List<MyOrder>> _fetchAllOrders(
  CashierReportsApi api, {
  required String serveStatus,
  Map<String, dynamic>? periodQuery,
}) async {
  final out = <MyOrder>[];
  for (var page = 1; page <= _maxPages; page++) {
    final data = await api.fetchMyOrders(
      periodQuery: periodQuery,
      serveStatus: serveStatus,
      page: page,
      pageSize: 100,
    );
    final result = MyOrdersPage.fromJson(data);
    out.addAll(result.items);
    if (!result.hasMore || result.items.isEmpty) break;
  }
  return out;
}

/// "À SERVIR": every order of this cashier that still has to be printed /
/// served, oldest first. Deliberately NOT bound to the selected period — an
/// unserved order from yesterday must stay in the queue.
final myToServeProvider = FutureProvider.autoDispose<List<MyOrder>>((ref) async {
  ref.watch(authProvider.select((s) => s.user?.id));
  return _fetchAllOrders(ref.watch(reportsApiProvider), serveStatus: 'to_serve');
});

/// "SERVIES": this cashier's orders of the selected period that were already
/// served (newest first).
final myServedProvider = FutureProvider.autoDispose<List<MyOrder>>((ref) async {
  ref.watch(authProvider.select((s) => s.user?.id));
  final filter = ref.watch(myReportFilterProvider);
  if (!filter.isReady) return const [];
  return _fetchAllOrders(
    ref.watch(reportsApiProvider),
    serveStatus: 'served',
    periodQuery: filter.toQuery(),
  );
});
