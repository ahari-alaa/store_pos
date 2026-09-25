import 'package:uuid/uuid.dart';

import '../../../../core/network/api_client.dart';

/// Talks to `/api/inventory` (see store_pos_backend/src/routes/inventoryRoutes.js).
///
/// Sales create their own SALE movements server-side; this datasource is
/// for everything else a store manages manually — most commonly receiving
/// new stock from a supplier ("restock").
class InventoryApi {
  final ApiClient _client;
  static const _uuid = Uuid();

  const InventoryApi(this._client);

  /// Adjusts [productId]'s stock by [quantityDelta] (positive to add stock,
  /// negative for damage/write-off/correction). `client_operation_id` is a
  /// fresh idempotency key per call, matching the backend's offline-sync
  /// design (see inventoryService.js#adjust).
  Future<Map<String, dynamic>> adjustStock({
    required String productId,
    required int quantityDelta,
    required String movementType,
    String? note,
  }) {
    return _client.post('/inventory/adjust', body: {
      'client_operation_id': _uuid.v4(),
      'product_id': productId,
      'quantity_delta': quantityDelta,
      'movement_type': movementType,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }
}
