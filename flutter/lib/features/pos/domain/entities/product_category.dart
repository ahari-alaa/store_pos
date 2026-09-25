/// Core ProductCategory entity used to group products in the POS grid.
///
/// Intentionally has NO Flutter imports (no IconData/Color) — the domain
/// layer stays pure Dart. Icon/color presentation mapping lives in the
/// presentation layer (see `category_style.dart`), keyed off [id].
class ProductCategory {
  final String id;
  final String name;

  /// Number of active products that belong to this category. Used to show
  /// e.g. "Drinks (35)" in the category navigation (see §26 of the POS
  /// image/category spec).
  final int count;

  const ProductCategory({
    required this.id,
    required this.name,
    this.count = 0,
  });
}
