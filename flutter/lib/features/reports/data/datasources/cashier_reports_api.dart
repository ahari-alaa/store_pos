import '../../../../core/network/api_client.dart';

/// Talks to `/api/reports` (see
/// store_pos_backend/src/routes/reportRoutes.js).
///
/// Originally just the one cashier-activity call the Cashiers screen
/// needed (hence the class name, kept as-is rather than renamed so the
/// existing `cashierReportsApiProvider` wiring in sales_provider.dart
/// doesn't need touching) — now also the full set of `/reports/*` reads
/// the Rapports screen uses. Several of these (KPIs, cashier ranking, top
/// products, revenue series) are the exact same `/reports/dashboard-*`
/// endpoints the Accueil dashboard already calls: the two screens share
/// one backend implementation of "what does this period's activity look
/// like", just with a wider choice of periods on this screen (see
/// reportService.js#resolveRange and reports_provider.dart).
class CashierReportsApi {
  final ApiClient _client;

  const CashierReportsApi(this._client);

  /// GET /reports/overview — the ONE payload behind the Rapports screen,
  /// its PDF, its Excel/CSV export and Print (see the backend's
  /// reportOverviewService.js). Pass [includeSales] to also receive the
  /// period's full sales list (exports only).
  Future<Map<String, dynamic>> fetchOverview(
    Map<String, dynamic> periodQuery, {
    bool includeSales = false,
    int recentLimit = 10,
  }) {
    return _client.get('/reports/overview', query: {
      ...periodQuery,
      'recent_limit': recentLimit,
      if (includeSales) 'include_sales': 'true',
    });
  }

  /// GET /reports/my-sales — the signed-in CASHIER's personal report (see
  /// the backend's cashierReportService.js). There is deliberately no
  /// cashier-id parameter: the server derives the cashier from the auth
  /// token, so this can only ever return the caller's own figures.
  ///
  /// [includeOrders] also returns the period's full order list (used by the
  /// printed report, so the print shows exactly what the screen totals say).
  Future<Map<String, dynamic>> fetchMySales(
    Map<String, dynamic> periodQuery, {
    bool includeOrders = false,
  }) {
    return _client.get('/reports/my-sales', query: {
      ...periodQuery,
      if (includeOrders) 'include_orders': 'true',
    });
  }

  /// GET /reports/my-orders — one page of the signed-in cashier's orders
  /// (with their lines). [serveStatus]: `all` | `to_serve` | `served`.
  /// [paymentStatus]: PENDING | PARTIALLY_PAID | PAID | UNPAID. Omit
  /// [periodQuery] for no date bound (the "À servir" queue is never
  /// date-bound, so an unserved order of yesterday stays in it).
  Future<Map<String, dynamic>> fetchMyOrders({
    Map<String, dynamic>? periodQuery,
    String serveStatus = 'all',
    String? paymentStatus,
    String? search,
    int page = 1,
    int pageSize = 50,
  }) {
    return _client.get('/reports/my-orders', query: {
      ...?periodQuery,
      'serve_status': serveStatus,
      if (paymentStatus != null) 'payment_status': paymentStatus,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'page_size': pageSize,
    });
  }

  /// GET /reports/cashier-sales?cashier_id=&(period=|from=&to=)[&group_by=day]
  ///
  /// Either pass [period] (Rapports — one of the ReportPeriod values), or
  /// [from]/[to] built via [LocalDateRange] (the Cashiers screen's
  /// original Day/Month report contract) — the backend requires one or
  /// the other. Pass [groupBy] = 'day' to also get the daily breakdown;
  /// omit it for a summary-only call.
  ///
  /// Returns the raw `{ cashier, period, summary, payment_breakdown,
  /// days? }` payload — see CashierSalesReport.fromJson for how it's
  /// parsed.
  Future<Map<String, dynamic>> fetchCashierSalesReport({
    required String cashierId,
    String? period,
    String? from,
    String? to,
    String? groupBy,
  }) {
    return _client.get('/reports/cashier-sales', query: {
      'cashier_id': cashierId,
      if (period != null) 'period': period,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (groupBy != null) 'group_by': groupBy,
    });
  }

  /// GET /reports/dashboard-overview — KPI row (spec §6): chiffre
  /// d'affaires / commandes / articles vendus / ticket moyen. Returns the
  /// raw `{ total_revenue, sale_count, items_sold, average_sale }`
  /// payload — see DashboardOverview.fromJson.
  Future<Map<String, dynamic>> fetchKpis(Map<String, dynamic> periodQuery) {
    return _client.get('/reports/dashboard-overview', query: periodQuery);
  }

  /// GET /reports/dashboard-cashiers — "Performance des caissiers" (spec
  /// §10). Returns `{ cashiers: [...] }` — see CashierRankingEntry.
  Future<Map<String, dynamic>> fetchCashierRanking(Map<String, dynamic> periodQuery) {
    return _client.get('/reports/dashboard-cashiers', query: periodQuery);
  }

  /// GET /reports/dashboard-articles — "Articles les plus vendus" (spec
  /// §12). Returns `{ articles: [...] }` — see ArticleSoldEntry.
  Future<Map<String, dynamic>> fetchTopProducts(Map<String, dynamic> periodQuery, {int limit = 10}) {
    return _client.get('/reports/dashboard-articles', query: {...periodQuery, 'limit': limit});
  }

  /// GET /reports/dashboard-revenue — "Évolution du chiffre d'affaires"
  /// (spec §7), auto-granularity (hour/day/month) picked server-side from
  /// the resolved period's span. Returns `{ granularity, range, buckets:
  /// [...] }` — see RevenueBucket.
  Future<Map<String, dynamic>> fetchRevenueSeries(Map<String, dynamic> periodQuery) {
    return _client.get('/reports/dashboard-revenue', query: {...periodQuery, 'granularity': 'auto'});
  }

  /// GET /reports/sales — "Résumé des ventes" + "Répartition des
  /// paiements" (spec §8/§9) in one call. Returns the raw payload — see
  /// SalesSummaryReport.fromJson.
  Future<Map<String, dynamic>> fetchSalesSummary(Map<String, dynamic> periodQuery) {
    return _client.get('/reports/sales', query: periodQuery);
  }

  /// GET /reports/expenses — "Dépenses" (spec §13). Returns the raw
  /// payload — see ExpensesReport.fromJson.
  Future<Map<String, dynamic>> fetchExpenses(Map<String, dynamic> periodQuery) {
    return _client.get('/reports/expenses', query: periodQuery);
  }

  /// GET /reports/stock — "État du stock" (spec §14). Not period-based
  /// (stock has no date range, only a "now") — [threshold] is the low-
  /// stock cutoff for products (ingredients use their own per-row
  /// `min_stock`). Returns the raw payload — see StockReport.fromJson.
  Future<Map<String, dynamic>> fetchStock({int threshold = 5}) {
    return _client.get('/reports/stock', query: {'threshold': threshold});
  }
}
