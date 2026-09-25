import '../../../../core/network/api_client.dart';
import '../../domain/entities/product.dart';

/// Talks to `/api/products` (see store_pos_backend/src/routes/productRoutes.js).
class ProductsApi {
  final ApiClient _client;

  const ProductsApi(this._client);

  /// Fetches every active product for the cashier's store, paging through
  /// the API's `page`/`page_size` (max 200 per page — see
  /// validators/productValidators.js) until all results are collected.
  Future<List<Product>> fetchActiveProducts() async {
    final products = <Product>[];
    const pageSize = 200;
    var page = 1;

    while (true) {
      final data = await _client.get('/products', query: {
        'is_active': true,
        'page': page,
        'page_size': pageSize,
      });

      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => Product.fromJson(raw as Map<String, dynamic>))
          .toList();
      products.addAll(items);

      final total = (data['total'] as num?)?.toInt() ?? products.length;
      if (items.isEmpty || products.length >= total) break;
      page++;
    }

    return products;
  }

  /// Fetches every product (active AND inactive) for the Products
  /// management screen — unlike [fetchActiveProducts], which the POS grid
  /// uses and which deliberately hides deactivated products.
  Future<List<Product>> fetchAllProducts({String? search}) async {
    final products = <Product>[];
    const pageSize = 200;
    var page = 1;

    while (true) {
      final data = await _client.get('/products', query: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      });

      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => Product.fromJson(raw as Map<String, dynamic>))
          .toList();
      products.addAll(items);

      final total = (data['total'] as num?)?.toInt() ?? products.length;
      if (items.isEmpty || products.length >= total) break;
      page++;
    }

    return products;
  }

  /// Creates a product. `input` mirrors
  /// store_pos_backend/src/validators/productValidators.js#createProduct.
  Future<Product> createProduct(Map<String, dynamic> input) async {
    final data = await _client.post('/products', body: input);
    return Product.fromJson(data['product'] as Map<String, dynamic>);
  }

  /// Partially updates a product (only the fields present in `input`).
  Future<Product> updateProduct(String id, Map<String, dynamic> input) async {
    final data = await _client.put('/products/$id', body: input);
    return Product.fromJson(data['product'] as Map<String, dynamic>);
  }

  /// Soft-deletes (deactivates) a product — see productRepository.softDelete.
  /// Deletes the product outright. If it has sales history, the backend
  /// can't hard-delete it (would corrupt historical sales/reporting) and
  /// deactivates it instead — this returns `true` when that fallback
  /// happened, so the UI can tell the user which one actually occurred.
  Future<bool> deleteProduct(String id) async {
    final data = await _client.delete('/products/$id');
    return data['deactivated'] == true;
  }

  /// Uploads/replaces a product's photo (JPEG/PNG/WebP, 5MB max — see
  /// backend's middleware/upload.js) and returns the updated product.
  Future<Product> uploadImage(String productId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final data = await _client.postMultipart(
      '/products/$productId/image',
      fieldName: 'image',
      bytes: bytes,
      filename: filename,
      mimeType: _mimeTypeForFilename(filename),
    );
    return Product.fromJson(data['product'] as Map<String, dynamic>);
  }

  /// Removes a product's photo.
  Future<Product> deleteImage(String productId) async {
    final data = await _client.delete('/products/$productId/image');
    return Product.fromJson(data['product'] as Map<String, dynamic>);
  }

  /// Matches backend's middleware/upload.js#ALLOWED_MIME_TYPES — the
  /// server rejects anything else, so this must stay in sync with it.
  String _mimeTypeForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg'; // covers .jpg / .jpeg, and is the safest default
  }
}
