import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../data/datasources/recipe_api.dart';
import '../../domain/entities/recipe.dart';

final recipeApiProvider = Provider<RecipeApi>((ref) {
  return RecipeApi(ref.watch(apiClientProvider));
});

class RecipeNotifier extends StateNotifier<AsyncValue<ProductRecipe>> {
  final RecipeApi _api;
  final String productId;

  RecipeNotifier(this._api, this.productId) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final recipe = await _api.fetch(productId);
      state = AsyncValue.data(recipe);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// "+ Add supply" dialog.
  Future<void> addLine(String ingredientId, double quantity, {String? unit}) async {
    final recipe = await _api.addLine(productId, ingredientId: ingredientId, quantity: quantity, unit: unit);
    state = AsyncValue.data(recipe);
  }

  /// "Edit recipe supply" dialog.
  Future<void> updateLine(String ingredientId, double quantity, {String? unit}) async {
    final recipe = await _api.updateLine(productId, ingredientId, quantity: quantity, unit: unit);
    state = AsyncValue.data(recipe);
  }

  Future<void> removeLine(String ingredientId) async {
    final recipe = await _api.removeLine(productId, ingredientId);
    state = AsyncValue.data(recipe);
  }
}

final recipeProvider =
    StateNotifierProvider.family<RecipeNotifier, AsyncValue<ProductRecipe>, String>(
  (ref, productId) => RecipeNotifier(ref.watch(recipeApiProvider), productId),
);
