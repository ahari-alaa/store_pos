import '../../../../core/network/api_client.dart';

/// Talks to `/api/sales` and `/api/payments` (see
/// store_pos_backend/src/routes/saleRoutes.js and paymentRoutes.js).
class SalesApi {
  final ApiClient _client;

  const SalesApi(this._client);

  /// Creates a sale (+ its items + payments + inventory deduction, all in
  /// one backend transaction — see services/saleService.js).
  ///
  /// [payments] may be an empty list — this is what creates an unpaid sale
  /// ("Give receipt without paying", Sales spec §2/§3): the backend then
  /// records it with `payment_status = PENDING` instead of requiring the
  /// total to be covered up front.
  ///
  /// [clientOperationId] is the idempotency key: retrying the same sale
  /// (e.g. after a timed-out request) with the same id is safe and will
  /// never create a duplicate sale.
  ///
  /// Returns `{ sale, was_duplicate }`.
  Future<Map<String, dynamic>> createSale({
    required String clientOperationId,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> payments = const [],
    double discountTotal = 0,
    double taxTotal = 0,
    String? note,
  }) {
    return _client.post('/sales', body: {
      'client_operation_id': clientOperationId,
      'items': items,
      'payments': payments,
      'discount_total': discountTotal,
      'tax_total': taxTotal,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  /// Fetches sales for the Sales screen (spec §1), paging through
  /// `page`/`page_size` the same way [ProductsApi.fetchActiveProducts]
  /// does. [search] matches receipt number/cashier/note (backend §15);
  /// [paymentStatus] is one of PENDING/PARTIALLY_PAID/PAID/REFUNDED, or
  /// null for "All".
  ///
  /// [userId]/[from]/[to] narrow the request server-side (saleRepository
  /// .list already supports all three) — used by the Cashier report's Day
  /// view and its per-day drill-down from Month view, so an admin never has
  /// to download the WHOLE store's sales history just to see one cashier's
  /// receipts for one day (spec §10/§16).
  Future<List<Map<String, dynamic>>> fetchSales({
    String? search,
    String? paymentStatus,
    String? userId,
    String? from,
    String? to,
  }) async {
    final sales = <Map<String, dynamic>>[];
    const pageSize = 200;
    var page = 1;

    while (true) {
      final data = await _client.get('/sales', query: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        if (paymentStatus != null) 'payment_status': paymentStatus,
        if (userId != null) 'user_id': userId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      });

      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => raw as Map<String, dynamic>)
          .toList();
      sales.addAll(items);

      final total = (data['total'] as num?)?.toInt() ?? sales.length;
      if (items.isEmpty || sales.length >= total) break;
      page++;
    }

    return sales;
  }

  /// One page of sales, raw (`{items, total, page, page_size}`, unlike
  /// [fetchSales] which pages through everything and flattens it into a
  /// single list). Backs the Rapports "Transactions récentes" table (spec
  /// §15/§21): a busy store's selected period can hold thousands of
  /// sales, so that table paginates server-side through this instead of
  /// downloading the whole period like [fetchSales] does for the Sales
  /// screen's own (client-side-filtered) list.
  ///
  /// Pass [period] (a ReportPeriod's apiValue) so this resolves the exact
  /// same date range every other Rapports section uses; [from]/[to] are
  /// only required when [period] is 'custom' (or omitted entirely).
  Future<Map<String, dynamic>> fetchSalesPage({
    String? period,
    String? from,
    String? to,
    int page = 1,
    int pageSize = 10,
  }) {
    return _client.get('/sales', query: {
      if (period != null) 'period': period,
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      'page': page,
      'page_size': pageSize,
    });
  }

  /// Refetches a single sale (with its items/payments), e.g. right after
  /// paying it, to show its up-to-date status without a full list reload.
  Future<Map<String, dynamic>> fetchSaleById(String id) async {
    final data = await _client.get('/sales/$id');
    return data['sale'] as Map<String, dynamic>;
  }

  /// Pays an existing (NOT PAID / partially paid) sale (Sales spec §6/§7):
  /// posts to POST /api/payments, which updates the SAME sale row rather
  /// than creating a new one (see saleService.addPayment — spec §9/§20).
  ///
  /// [clientOperationId] makes this safe to retry after a timeout without
  /// recording the payment twice.
  Future<Map<String, dynamic>> payForSale({
    required String clientOperationId,
    required String saleId,
    required double amount,
    required String paymentMethod,
  }) {
    return _client.post('/payments', body: {
      'client_operation_id': clientOperationId,
      'sale_id': saleId,
      'amount': amount,
      'payment_method': paymentMethod,
    });
  }

  /// POST /sales/:id/serve — "IMPRIMER / SERVIR": marks the signed-in
  /// cashier's own order as served. Only the sale's serving columns change
  /// on the server; the sale, its items and its payments are untouched.
  ///
  /// [clientOperationId] makes a retry safe: if the first request reached
  /// the server but its response was lost, repeating it with the same id
  /// succeeds (`already_applied: true`) instead of failing as "already
  /// served", and never records a second serve.
  ///
  /// Throws [ApiException] with code `SALE_ALREADY_SERVED` when another
  /// client served it first.
  Future<Map<String, dynamic>> serveSale({
    required String saleId,
    required String clientOperationId,
  }) {
    return _client.post('/sales/$saleId/serve', body: {
      'client_operation_id': clientOperationId,
    });
  }

  /// POST /sales/:id/reprint — records that an ALREADY SERVED order's
  /// receipt was printed again. Does not change `served_at`.
  Future<Map<String, dynamic>> reprintSale(String saleId) {
    return _client.post('/sales/$saleId/reprint', body: const <String, dynamic>{});
  }
}
