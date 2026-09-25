import '../../../../core/config/api_config.dart';

/// Core Product entity.
///
/// Field names mirror the `products` table / API payload from
/// store_pos_backend (see migrations/001_init.sql and
/// src/validators/productValidators.js) so mapping stays trivial:
///   id, name, category, barcode, sku, price, cost, stock_quantity,
///   tax_rate, is_active, image_url.
///
/// `category` is a plain free-text string on the backend (there is no
/// categories endpoint / foreign key in Milestone 1's API) — the POS
/// screen derives its category chips from the distinct values it sees
/// across the product list (see presentation/providers/pos_providers.dart).
class Product {
  final String id;
  final String name;
  final String? category;
  final String? barcode;
  final String? sku;
  final double price;
  final double cost;
  final int stockQuantity;
  final double taxRate; // e.g. 0.10 for 10%
  final bool isActive;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.name,
    this.category,
    this.barcode,
    this.sku,
    required this.price,
    this.cost = 0,
    required this.stockQuantity,
    this.taxRate = 0,
    this.isActive = true,
    this.imageUrl,
  });

  bool get isOutOfStock => stockQuantity <= 0;

  /// [imageUrl] as returned by the backend is a relative path
  /// (`/uploads/products/xyz.jpg`) — this resolves it against the API
  /// server's origin so `Image.network` can load it directly.
  ///
  /// Defensive normalization: a backend running on Windows can end up
  /// storing `\`-separated paths (e.g. `\uploads\products\xyz.jpg`) if it
  /// builds the stored value from a filesystem path instead of a URL
  /// path, and some callers may omit the leading slash entirely. Both
  /// would silently produce a URL `Image.network` can't fetch, which
  /// looks identical to "image doesn't display" — so normalize instead
  /// of trusting the raw value.
  String? get fullImageUrl {
    final raw = imageUrl;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    var path = raw.replaceAll('\\', '/');
    if (!path.startsWith('/')) path = '/$path';
    return '${ApiConfig.originUrl}$path';
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String?,
      barcode: json['barcode'] as String?,
      sku: json['sku'] as String?,
      price: _toDouble(json['price']),
      cost: _toDouble(json['cost']),
      stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
      taxRate: _toDouble(json['tax_rate']),
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active'] as num? ?? 1) != 0,
      imageUrl: json['image_url'] as String?,
    );
  }

  // The backend keeps money/rate columns as DECIMAL and returns them as
  // JSON strings (decimalNumbers: false in config/db.js, to avoid float
  // rounding on money), so this needs to handle both strings and numbers.
  static double _toDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
