/// Mirrors the `ingredients` table / API payload from store_pos_backend
/// (see migrations/006_ingredients.sql and
/// src/validators/ingredientValidators.js).
enum IngredientUnit { g, kg, ml, l, unit }

IngredientUnit ingredientUnitFromString(String raw) {
  return IngredientUnit.values.firstWhere(
    (u) => u.name == raw,
    orElse: () => IngredientUnit.unit,
  );
}

enum IngredientStockStatus { normal, faible, rupture }

class Ingredient {
  final String id;
  final String name;
  final IngredientUnit unit;
  final double stockQuantity;
  final double minStock;
  final double costPerUnit;
  final bool isActive;
  final IngredientStockStatus status;

  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.stockQuantity,
    required this.minStock,
    required this.costPerUnit,
    required this.isActive,
    required this.status,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: json['id'] as String,
      name: json['name'] as String,
      unit: ingredientUnitFromString('${json['unit'] ?? 'unit'}'),
      stockQuantity: double.tryParse('${json['stock_quantity'] ?? 0}') ?? 0,
      minStock: double.tryParse('${json['min_stock'] ?? 0}') ?? 0,
      costPerUnit: double.tryParse('${json['cost_per_unit'] ?? 0}') ?? 0,
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['is_active'] as num? ?? 1) != 0,
      status: IngredientStockStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => IngredientStockStatus.normal,
      ),
    );
  }
}
