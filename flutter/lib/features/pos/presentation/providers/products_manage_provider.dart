import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/providers.dart';
import '../../../../core/widgets/product_image.dart';
import '../../data/datasources/inventory_api.dart';
import '../../data/datasources/products_api.dart';
import '../../domain/entities/product.dart';
import 'pos_providers.dart';

final inventoryApiProvider = Provider<InventoryApi>((ref) {
  return InventoryApi(ref.watch(apiClientProvider));
});

/// IDs of products currently mid-delete. Kept separate from the main
/// `AsyncValue<List<Product>>` state so a single row can show a spinner /
/// disabled button without the rest of the Products screen (and its
/// scroll position) being torn down and rebuilt as a loading state.
final deletingProductIdsProvider = StateProvider<Set<String>>((ref) => const {});

/// Full product list (active + inactive) for the Products management
/// screen. Deliberately separate from [productsProvider] (POS grid, active
/// only) so deactivating a product here doesn't make it vanish from this
/// screen's own list.
class ProductsManageNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  final ProductsApi _api;
  final Ref _ref;

  ProductsManageNotifier(this._api, this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    try {
      final products = await _api.fetchAllProducts();
      // See clearProductImageCache: makes sure a photo that failed to
      // load earlier (e.g. before the backend was serving /uploads) gets
      // retried now instead of staying a placeholder for the whole
      // session.
      clearProductImageCache();
      state = AsyncValue.data(products);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// After any write, re-fetch this list AND invalidate the POS grid's
  /// [productsProvider] so a price/stock/status change shows up there too
  /// without requiring an app restart.
  void _syncPos() {
    _ref.invalidate(productsProvider);
  }

  Future<String> createProduct(Map<String, dynamic> input) async {
    final product = await _api.createProduct(input);
    _syncPos();
    await refresh();
    return product.id;
  }

  Future<void> updateProduct(String id, Map<String, dynamic> input) async {
    await _api.updateProduct(id, input);
    _syncPos();
    await refresh();
  }

  /// Deletes a product. Actually removes the row (and its image, backend
  /// side) unless the product has sales history, in which case the
  /// backend deactivates it instead to protect historical sales data.
  ///
  /// Guarantees:
  ///   * Never leaves [state] partially updated on failure — [refresh] (and
  ///     therefore the loading flash it causes) only runs after the delete
  ///     call itself has succeeded.
  ///   * Always throws either the original [ApiException] or a normalized
  ///     one — never lets a raw, un-messaged error escape — so the caller
  ///     (see `products_page.dart`) can always show something readable in
  ///     a SnackBar instead of the exception propagating unhandled.
  ///   * Re-entrant calls for the same id are guarded here too (in
  ///     addition to the UI-level guard), so a duplicate tap can never
  ///     fire two DELETE requests for the same product.
  /// Returns `true` if the product was deactivated instead of actually
  /// deleted (it has sales history the DB won't let us delete through —
  /// see productService.remove on the backend).
  Future<bool> deactivateProduct(String id) async {
    final deletingIds = _ref.read(deletingProductIdsProvider);
    if (deletingIds.contains(id)) return false;
    _ref.read(deletingProductIdsProvider.notifier).update((s) => {...s, id});

    bool wasDeactivatedInstead = false;
    try {
      wasDeactivatedInstead = await _api.deleteProduct(id);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(
        code: 'UNKNOWN_ERROR',
        message: 'Could not delete this product: $error',
      );
    } finally {
      _ref.read(deletingProductIdsProvider.notifier).update(
            (s) => {...s}..remove(id),
          );
    }

    // Only reached on success: safe to refresh the list and the POS grid.
    _syncPos();
    await refresh();
    return wasDeactivatedInstead;
  }

  Future<void> restock(String productId, int quantity, {String? note}) async {
    await _ref.read(inventoryApiProvider).adjustStock(
          productId: productId,
          quantityDelta: quantity,
          movementType: 'PURCHASE',
          note: note,
        );
    _syncPos();
    await refresh();
  }

  Future<void> uploadImage(String productId, {
    required List<int> bytes,
    required String filename,
  }) async {
    await _api.uploadImage(productId, bytes: bytes, filename: filename);
    _syncPos();
    await refresh();
  }

  Future<void> removeImage(String productId) async {
    await _api.deleteImage(productId);
    _syncPos();
    await refresh();
  }
}

final productsManageProvider =
    StateNotifierProvider<ProductsManageNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductsManageNotifier(ref.watch(productsApiProvider), ref);
});
