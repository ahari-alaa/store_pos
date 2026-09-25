import '../../../../core/network/api_client.dart';
import '../../domain/entities/supplier.dart';

/// Talks to `/api/suppliers` (see store_pos_backend/src/routes/supplierRoutes.js).
class SuppliersApi {
  final ApiClient _client;

  const SuppliersApi(this._client);

  Future<List<Supplier>> fetchAll({String? search}) async {
    final suppliers = <Supplier>[];
    const pageSize = 200;
    var page = 1;

    while (true) {
      final data = await _client.get('/suppliers', query: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      });

      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => Supplier.fromJson(raw as Map<String, dynamic>))
          .toList();
      suppliers.addAll(items);

      final total = (data['total'] as num?)?.toInt() ?? suppliers.length;
      if (items.isEmpty || suppliers.length >= total) break;
      page++;
    }

    return suppliers;
  }

  Future<Supplier> create(Map<String, dynamic> input) async {
    final data = await _client.post('/suppliers', body: input);
    return Supplier.fromJson(data['supplier'] as Map<String, dynamic>);
  }

  Future<Supplier> update(String id, Map<String, dynamic> input) async {
    final data = await _client.put('/suppliers/$id', body: input);
    return Supplier.fromJson(data['supplier'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _client.delete('/suppliers/$id');
  }
}
