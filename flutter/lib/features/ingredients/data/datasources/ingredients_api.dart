import '../../../../core/network/api_client.dart';
import '../../domain/entities/ingredient.dart';

/// Talks to /api/ingredients (see store_pos_backend/src/routes/ingredientRoutes.js).
class IngredientsApi {
  final ApiClient _client;

  const IngredientsApi(this._client);

  Future<List<Ingredient>> fetchAll({String? search}) async {
    final data = await _client.get('/ingredients', query: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    });
    return (data['ingredients'] as List<dynamic>? ?? const [])
        .map((raw) => Ingredient.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<Ingredient> create(Map<String, dynamic> input) async {
    final data = await _client.post('/ingredients', body: input);
    return Ingredient.fromJson(data['ingredient'] as Map<String, dynamic>);
  }

  Future<Ingredient> update(String id, Map<String, dynamic> input) async {
    final data = await _client.put('/ingredients/$id', body: input);
    return Ingredient.fromJson(data['ingredient'] as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _client.delete('/ingredients/$id');
  }

  /// Safe alternative to [delete] when the backend reports the ingredient
  /// is in use or has stock history (see ingredientController.deactivate).
  /// Sets is_active = false server-side: the ingredient disappears from
  /// active supply/recipe selection but every existing recipe line, sale
  /// and stock movement keeps pointing at it.
  Future<Ingredient> deactivate(String id) async {
    final data = await _client.post('/ingredients/$id/deactivate');
    return Ingredient.fromJson(data['ingredient'] as Map<String, dynamic>);
  }

  /// Records a stock movement (Nouveau stock / restock after a delivery).
  Future<Ingredient> addMovement(
    String id, {
    required double quantityDelta,
    required String movementType,
    String? note,
  }) async {
    final data = await _client.post('/ingredients/$id/movements', body: {
      'quantity_delta': quantityDelta,
      'movement_type': movementType,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
    return Ingredient.fromJson(data['ingredient'] as Map<String, dynamic>);
  }
}
