import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../../pos/presentation/providers/pos_providers.dart';
import '../../../pos/presentation/providers/products_manage_provider.dart';
import '../../data/datasources/ingredients_api.dart';
import '../../domain/entities/ingredient.dart';
import 'recipe_provider.dart';

final ingredientsApiProvider = Provider<IngredientsApi>((ref) {
  return IngredientsApi(ref.watch(apiClientProvider));
});

class IngredientsNotifier extends StateNotifier<AsyncValue<List<Ingredient>>> {
  final IngredientsApi _api;
  final Ref _ref;

  IngredientsNotifier(this._api, this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final ingredients = await _api.fetchAll();
      state = AsyncValue.data(ingredients);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> createIngredient(Map<String, dynamic> input) async {
    await _api.create(input);
    await refresh();
  }

  Future<void> updateIngredient(String id, Map<String, dynamic> input) async {
    await _api.update(id, input);
    await refresh();
  }

  /// Deletes an ingredient (spec §1/§18). The backend always removes it
  /// from every product recipe first, then either hard-deletes it or
  /// (if it has stock/purchase history) deactivates it — either way it
  /// disappears from the active Ingredients screen and from new-recipe
  /// selection immediately. Any product recipe screen currently open for
  /// a product that used this ingredient must reflect the removal
  /// without needing an app restart, so this invalidates the recipe
  /// (per-product, family-wide), Products management and POS grid
  /// providers in addition to refreshing this list.
  Future<void> deleteIngredient(String id) async {
    await _api.delete(id);
    await refresh();
    _syncDependents();
  }

  Future<void> deactivateIngredient(String id) async {
    await _api.deactivate(id);
    await refresh();
    _syncDependents();
  }

  Future<void> addStock(String id, double quantity, {String? note}) async {
    await _api.addMovement(id, quantityDelta: quantity, movementType: 'PURCHASE', note: note);
    await refresh();
    _syncDependents();
  }

  /// Invalidates every screen/provider whose data can change as a side
  /// effect of an ingredient write: recipe panels (a deleted ingredient's
  /// line disappears from every product that used it), the Products
  /// management list and the POS grid (possible-production / product
  /// availability depend on ingredient stock — spec §13/§18).
  void _syncDependents() {
    _ref.invalidate(recipeProvider);
    _ref.invalidate(productsManageProvider);
    _ref.invalidate(productsProvider);
  }
}

final ingredientsProvider =
    StateNotifierProvider<IngredientsNotifier, AsyncValue<List<Ingredient>>>((ref) {
  return IngredientsNotifier(ref.watch(ingredientsApiProvider), ref);
});
