import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/providers.dart';
import '../../../../core/widgets/product_image.dart';
import '../../data/datasources/products_api.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_category.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// "All" is a UI-only pseudo-category id, not a real category value.
const String kAllCategoryId = 'all';

final productsApiProvider = Provider<ProductsApi>((ref) {
  return ProductsApi(ref.watch(apiClientProvider));
});

/// All active products for the current store.
///
/// Products are fetched only after authentication is ready.
/// When the authentication state changes, this provider is recreated and
/// the products are fetched again using the current access token.
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final authState = ref.watch(authProvider);

  // Do not call the protected endpoint when the user is logged out.
  if (!authState.isAuthenticated) {
    return const <Product>[];
  }

  final api = ref.watch(productsApiProvider);

  // The auth provider has confirmed that the user is authenticated.
  // The ApiClient will obtain the current token from secure storage.
  final products = await api.fetchActiveProducts();

  // See clearProductImageCache: retries any photo that failed to load
  // earlier instead of leaving it stuck on the placeholder icon for the
  // rest of the session.
  clearProductImageCache();
  return products;
});

/// Categories are derived from the distinct, non-empty `category` values
/// present in the fetched products, each carrying the count of active
/// products in it (§26 of the POS image/category spec).
final categoriesProvider = Provider<List<ProductCategory>>((ref) {
  final productsAsync = ref.watch(productsProvider);

  final products = productsAsync.valueOrNull ?? const <Product>[];

  final counts = <String, int>{};

  for (final product in products) {
    final id = product.category?.trim();
    if (id == null || id.isEmpty) continue;
    counts[id] = (counts[id] ?? 0) + 1;
  }

  final categories = counts.entries
      .map((entry) => ProductCategory(id: entry.key, name: entry.key, count: entry.value))
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return categories;
});

/// Total active product count, used for the "All" entry in the category
/// navigation.
final allProductsCountProvider = Provider<int>((ref) {
  return (ref.watch(productsProvider).valueOrNull ?? const <Product>[]).length;
});

/// Currently selected category filter in the POS grid.
final selectedCategoryProvider = StateProvider<String>((ref) => kAllCategoryId);

/// Free-text search query typed into the POS search box.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Products filtered by category and search query.
///
/// Name matches are scoped to the selected category (typing "Coca" while
/// "Drinks" is selected only searches drinks). Barcode matches are always
/// global regardless of the selected category — a scanned/typed barcode is
/// exact enough that scoping it to a category would only hide the product
/// the cashier is trying to ring up (§27 of the POS image/category spec).
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];

  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();

  return products.where((product) {
    if (query.isNotEmpty) {
      final matchesBarcode = product.barcode?.toLowerCase().contains(query) ?? false;
      if (matchesBarcode) return true;
    }

    final matchesCategory = category == kAllCategoryId || product.category == category;
    final matchesName = query.isEmpty || product.name.toLowerCase().contains(query);

    return matchesCategory && matchesName;
  }).toList();
});
