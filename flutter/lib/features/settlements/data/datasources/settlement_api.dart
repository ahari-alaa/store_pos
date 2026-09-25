import '../../../../core/network/api_client.dart';

/// Talks to `/api/cashier-settlements` (the cashier's OWN work-payment
/// justificatifs — spec §1-§21) and `/api/admin/cashier-settlements`
/// ("Paiements caissiers" — spec §22-§23, §26, §33). Two prefixes, one
/// class, exactly mirroring the two Express route files
/// (cashierSettlementRoutes.js / adminCashierSettlementRoutes.js) they
/// call.
class SettlementApi {
  final ApiClient _client;

  const SettlementApi(this._client);

  // ---- cashier ----------------------------------------------------

  /// GET /cashier-settlements/eligible-orders — "commandes disponibles
  /// pour justificatif" (spec §4). No cashier id: the server always
  /// resolves the caller from the auth token.
  Future<Map<String, dynamic>> fetchEligibleOrders() {
    return _client.get('/cashier-settlements/eligible-orders');
  }

  /// GET /cashier-settlements/my-summary — Rapport KPI header (spec §28).
  Future<Map<String, dynamic>> fetchMySummary() {
    return _client.get('/cashier-settlements/my-summary');
  }

  /// GET /cashier-settlements/my — "commandes déjà justifiées", grouped by
  /// settlement (spec §18).
  Future<Map<String, dynamic>> fetchMySettlements({String? status}) {
    return _client.get('/cashier-settlements/my', query: {
      if (status != null) 'status': status,
    });
  }

  /// POST /cashier-settlements — "IMPRIMER LE JUSTIFICATIF" (spec §6):
  /// creates the settlement out of [saleIds]. The backend re-verifies
  /// ownership/eligibility/no-duplicate itself inside one transaction —
  /// this call is never trusted blindly by the server, only proposed by
  /// the client.
  Future<Map<String, dynamic>> createSettlement(List<String> saleIds) {
    return _client.post('/cashier-settlements', body: {'sale_ids': saleIds});
  }

  /// GET /cashier-settlements/:id/proof — "VOIR LE JUSTIFICATIF" (spec
  /// §20/§21). Deliberately the only "view again" call on the cashier
  /// side — there is no reprint endpoint here at all.
  Future<Map<String, dynamic>> fetchProof(String id) {
    return _client.get('/cashier-settlements/$id/proof');
  }

  // ---- admin --------------------------------------------------------

  /// GET /admin/cashier-settlements — "Paiements caissiers" list (spec
  /// §22).
  Future<Map<String, dynamic>> adminFetchSettlements({
    String? cashierId,
    String? status,
  }) {
    return _client.get('/admin/cashier-settlements', query: {
      if (cashierId != null) 'cashier_id': cashierId,
      if (status != null) 'status': status,
    });
  }

  Future<Map<String, dynamic>> adminFetchSettlement(String id) {
    return _client.get('/admin/cashier-settlements/$id');
  }

  /// POST /admin/cashier-settlements/:id/mark-paid — "MARQUER COMME PAYÉ"
  /// (spec §23). The cashier's WORK payment; never touches a customer's
  /// payment status.
  Future<Map<String, dynamic>> adminMarkPaid(String id) {
    return _client.post('/admin/cashier-settlements/$id/mark-paid');
  }

  /// POST /admin/cashier-settlements/:id/cancel — keeps full history
  /// (spec §33); never deletes.
  Future<Map<String, dynamic>> adminCancel(String id, {String? reason}) {
    return _client.post('/admin/cashier-settlements/$id/cancel', body: {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  /// POST /admin/cashier-settlements/:id/reprint — admin-only duplicate
  /// (spec §26). The caller MUST render the result clearly marked COPIE /
  /// DUPLICATA — see SettlementPdf.build(copy: true).
  Future<Map<String, dynamic>> adminReprint(String id) {
    return _client.post('/admin/cashier-settlements/$id/reprint');
  }
}
