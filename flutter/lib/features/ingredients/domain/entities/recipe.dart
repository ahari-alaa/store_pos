/// Mirrors GET/POST/PUT/DELETE /api/products/:id/ingredients
/// (see store_pos_backend/src/services/recipeService.js).
class RecipeLine {
  final String ingredientId;
  final String ingredientName;
  final String ingredientUnit;
  final double ingredientStock;
  final double quantity;
  /// This line's own unit — may differ from [ingredientUnit] (e.g. a
  /// recipe entered in `g` for an ingredient stocked in `kg`). Falls
  /// back to the ingredient's unit when the line has none set.
  final String unit;
  final double costPerUnit;
  final double lineCost;
  /// floor(ingredientStock / quantity), converted to a common unit —
  /// null when the line's quantity is 0 (no limit).
  final int? possibleProduction;

  const RecipeLine({
    required this.ingredientId,
    required this.ingredientName,
    required this.ingredientUnit,
    required this.ingredientStock,
    required this.quantity,
    required this.unit,
    required this.costPerUnit,
    required this.lineCost,
    required this.possibleProduction,
  });

  factory RecipeLine.fromJson(Map<String, dynamic> json) {
    final ingredientUnit = '${json['ingredient_unit'] ?? 'unit'}';
    final quantity = double.tryParse('${json['quantity'] ?? 0}') ?? 0;
    final costPerUnit = double.tryParse('${json['cost_per_unit'] ?? 0}') ?? 0;
    return RecipeLine(
      ingredientId: '${json['ingredient_id']}',
      ingredientName: '${json['ingredient_name']}',
      ingredientUnit: ingredientUnit,
      ingredientStock: double.tryParse('${json['ingredient_stock'] ?? 0}') ?? 0,
      quantity: quantity,
      unit: '${json['unit'] ?? ingredientUnit}',
      costPerUnit: costPerUnit,
      lineCost: double.tryParse('${json['line_cost'] ?? quantity * costPerUnit}') ?? 0,
      possibleProduction: json['possible_production'] == null
          ? null
          : (json['possible_production'] as num).toInt(),
    );
  }
}

class ProductRecipe {
  final String productId;
  final List<RecipeLine> lines;
  final double ingredientsCost;
  final double salePrice;
  final double margin;
  final int marginPercent;
  /// Max units sellable right now given current supply stock — the
  /// minimum across all recipe lines (spec §7). 0 when the recipe is
  /// empty.
  final int possibleProduction;
  /// Name of the ingredient that determines [possibleProduction] — null
  /// when the recipe is empty.
  final String? limitingIngredient;

  const ProductRecipe({
    required this.productId,
    required this.lines,
    required this.ingredientsCost,
    required this.salePrice,
    required this.margin,
    required this.marginPercent,
    required this.possibleProduction,
    required this.limitingIngredient,
  });

  factory ProductRecipe.fromJson(Map<String, dynamic> json) {
    return ProductRecipe(
      productId: '${json['product_id']}',
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .map((raw) => RecipeLine.fromJson(raw as Map<String, dynamic>))
          .toList(),
      ingredientsCost: double.tryParse('${json['ingredients_cost'] ?? 0}') ?? 0,
      salePrice: double.tryParse('${json['sale_price'] ?? 0}') ?? 0,
      margin: double.tryParse('${json['margin'] ?? 0}') ?? 0,
      marginPercent: (json['margin_percent'] as num?)?.toInt() ?? 0,
      possibleProduction: (json['possible_production'] as num?)?.toInt() ?? 0,
      limitingIngredient: json['limiting_ingredient'] as String?,
    );
  }
}
