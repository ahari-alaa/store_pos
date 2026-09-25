import '../../../../core/network/api_client.dart';
import '../../domain/entities/recipe.dart';

/// Talks to /api/products/:id/ingredients (recipe sub-resource — see
/// store_pos_backend/src/routes/productRoutes.js).
class RecipeApi {
  final ApiClient _client;

  const RecipeApi(this._client);

  Future<ProductRecipe> fetch(String productId) async {
    final data = await _client.get('/products/$productId/ingredients');
    return ProductRecipe.fromJson(data['recipe'] as Map<String, dynamic>);
  }

  /// Legacy whole-list replace — still used by the "submit everything at
  /// once" recipe editor.
  Future<ProductRecipe> replace(
    String productId,
    List<Map<String, dynamic>> lines,
  ) async {
    final data = await _client.put('/products/$productId/ingredients', body: {'lines': lines});
    return ProductRecipe.fromJson(data['recipe'] as Map<String, dynamic>);
  }

  /// "+ Add supply" — adds ONE line without touching the rest of the
  /// recipe.
  Future<ProductRecipe> addLine(
    String productId, {
    required String ingredientId,
    required double quantity,
    String? unit,
  }) async {
    final data = await _client.post('/products/$productId/ingredients', body: {
      'ingredient_id': ingredientId,
      'quantity': quantity,
      if (unit != null) 'unit': unit,
    });
    return ProductRecipe.fromJson(data['recipe'] as Map<String, dynamic>);
  }

  /// "Edit recipe supply" — updates the quantity/unit of ONE existing
  /// line.
  Future<ProductRecipe> updateLine(
    String productId,
    String ingredientId, {
    required double quantity,
    String? unit,
  }) async {
    final data = await _client.put('/products/$productId/ingredients/$ingredientId', body: {
      'quantity': quantity,
      if (unit != null) 'unit': unit,
    });
    return ProductRecipe.fromJson(data['recipe'] as Map<String, dynamic>);
  }

  Future<ProductRecipe> removeLine(String productId, String ingredientId) async {
    final data = await _client.delete('/products/$productId/ingredients/$ingredientId');
    return ProductRecipe.fromJson(data['recipe'] as Map<String, dynamic>);
  }
}
