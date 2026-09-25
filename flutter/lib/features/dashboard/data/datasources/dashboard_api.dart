import '../../../../core/network/api_client.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../../domain/entities/dashboard_summary.dart';

/// Talks to GET /api/reports/dashboard and the newer period-aware
/// /api/reports/dashboard-* endpoints (see
/// store_pos_backend/src/routes/reportRoutes.js).
class DashboardApi {
  final ApiClient _client;

  const DashboardApi(this._client);

  Future<DashboardSummary> fetch() async {
    final data = await _client.get('/reports/dashboard');
    return DashboardSummary.fromJson(data);
  }

  Future<DashboardOverview> fetchOverview(DashboardPeriod period) async {
    final data = await _client.get(
      '/reports/dashboard-overview',
      query: {'period': period.apiValue},
    );
    return DashboardOverview.fromJson(data);
  }

  Future<List<CashierRankingEntry>> fetchCashierRanking(DashboardPeriod period) async {
    final data = await _client.get(
      '/reports/dashboard-cashiers',
      query: {'period': period.apiValue},
    );
    final list = data['cashiers'] as List<dynamic>? ?? const [];
    return list.map((raw) => CashierRankingEntry.fromJson(raw as Map<String, dynamic>)).toList();
  }

  Future<List<ArticleSoldEntry>> fetchArticlesSold(DashboardPeriod period, {int limit = 8}) async {
    final data = await _client.get(
      '/reports/dashboard-articles',
      query: {'period': period.apiValue, 'limit': limit},
    );
    final list = data['articles'] as List<dynamic>? ?? const [];
    return list.map((raw) => ArticleSoldEntry.fromJson(raw as Map<String, dynamic>)).toList();
  }

  Future<List<SalesStatusEntry>> fetchSalesStatus(DashboardPeriod period) async {
    final data = await _client.get(
      '/reports/dashboard-sales-status',
      query: {'period': period.apiValue},
    );
    final list = data['statuses'] as List<dynamic>? ?? const [];
    return list.map((raw) => SalesStatusEntry.fromJson(raw as Map<String, dynamic>)).toList();
  }

  Future<List<RevenueBucket>> fetchRevenueSeries(RevenueGranularity granularity) async {
    final data = await _client.get(
      '/reports/dashboard-revenue',
      query: {'granularity': granularity.apiValue},
    );
    final list = data['buckets'] as List<dynamic>? ?? const [];
    return list.map((raw) => RevenueBucket.fromJson(raw as Map<String, dynamic>)).toList();
  }

  Future<List<RecentSale>> fetchRecentSales({int limit = 8}) async {
    final data = await _client.get(
      '/reports/dashboard-recent-sales',
      query: {'limit': limit},
    );
    final list = data['sales'] as List<dynamic>? ?? const [];
    return list.map((raw) => RecentSale.fromJson(raw as Map<String, dynamic>)).toList();
  }
}
