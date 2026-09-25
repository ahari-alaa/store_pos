/// Mirrors the payload from GET /api/reports/dashboard
/// (see store_pos_backend/src/services/reportService.js#dashboard).
class DashboardSummary {
  final double totalSalesToday;
  final int orderCountToday;
  final double averageTicketToday;
  final double totalExpensesToday;
  final double salesPercentVsYesterday;
  final double ordersPercentVsYesterday;
  final double expensesPercentVsYesterday;
  final List<DailySales> salesLast7Days;
  final List<TopProduct> topProducts;
  final List<LowStockProduct> lowStockProducts;
  final List<LowStockIngredient> lowStockIngredients;

  const DashboardSummary({
    required this.totalSalesToday,
    required this.orderCountToday,
    required this.averageTicketToday,
    required this.totalExpensesToday,
    required this.salesPercentVsYesterday,
    required this.ordersPercentVsYesterday,
    required this.expensesPercentVsYesterday,
    required this.salesLast7Days,
    required this.topProducts,
    required this.lowStockProducts,
    required this.lowStockIngredients,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final today = json['today'] as Map<String, dynamic>? ?? const {};
    final vsYesterday = today['vs_yesterday'] as Map<String, dynamic>? ?? const {};
    return DashboardSummary(
      totalSalesToday: double.tryParse('${today['total_sales'] ?? 0}') ?? 0,
      orderCountToday: (today['order_count'] as num?)?.toInt() ?? 0,
      averageTicketToday: double.tryParse('${today['average_ticket'] ?? 0}') ?? 0,
      totalExpensesToday: double.tryParse('${today['total_expenses'] ?? 0}') ?? 0,
      salesPercentVsYesterday:
          double.tryParse('${vsYesterday['total_sales_percent'] ?? 0}') ?? 0,
      ordersPercentVsYesterday:
          double.tryParse('${vsYesterday['order_count_percent'] ?? 0}') ?? 0,
      expensesPercentVsYesterday:
          double.tryParse('${vsYesterday['total_expenses_percent'] ?? 0}') ?? 0,
      salesLast7Days: (json['sales_last_7_days'] as List<dynamic>? ?? const [])
          .map((raw) => DailySales.fromJson(raw as Map<String, dynamic>))
          .toList(),
      topProducts: (json['top_products'] as List<dynamic>? ?? const [])
          .map((raw) => TopProduct.fromJson(raw as Map<String, dynamic>))
          .toList(),
      lowStockProducts: (json['low_stock_products'] as List<dynamic>? ?? const [])
          .map((raw) => LowStockProduct.fromJson(raw as Map<String, dynamic>))
          .toList(),
      lowStockIngredients: (json['low_stock_ingredients'] as List<dynamic>? ?? const [])
          .map((raw) => LowStockIngredient.fromJson(raw as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DailySales {
  final DateTime day;
  final double revenue;

  const DailySales({required this.day, required this.revenue});

  factory DailySales.fromJson(Map<String, dynamic> json) {
    return DailySales(
      day: DateTime.tryParse('${json['day']}') ?? DateTime.now(),
      revenue: double.tryParse('${json['revenue'] ?? 0}') ?? 0,
    );
  }
}

class TopProduct {
  final String productId;
  final String name;
  final int quantitySold;
  final double revenue;

  const TopProduct({
    required this.productId,
    required this.name,
    required this.quantitySold,
    required this.revenue,
  });

  factory TopProduct.fromJson(Map<String, dynamic> json) {
    return TopProduct(
      productId: '${json['product_id']}',
      name: '${json['name']}',
      quantitySold: (json['quantity_sold'] as num?)?.toInt() ?? 0,
      revenue: double.tryParse('${json['revenue'] ?? 0}') ?? 0,
    );
  }
}

class LowStockProduct {
  final String id;
  final String name;
  final int stockQuantity;
  final String? category;

  const LowStockProduct({
    required this.id,
    required this.name,
    required this.stockQuantity,
    this.category,
  });

  factory LowStockProduct.fromJson(Map<String, dynamic> json) {
    return LowStockProduct(
      id: '${json['id']}',
      name: '${json['name']}',
      stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 0,
      category: json['category'] as String?,
    );
  }
}

class LowStockIngredient {
  final String id;
  final String name;
  final String unit;
  final double stockQuantity;
  final double minStock;

  const LowStockIngredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.stockQuantity,
    required this.minStock,
  });

  factory LowStockIngredient.fromJson(Map<String, dynamic> json) {
    return LowStockIngredient(
      id: '${json['id']}',
      name: '${json['name']}',
      unit: '${json['unit'] ?? 'unit'}',
      stockQuantity: double.tryParse('${json['stock_quantity'] ?? 0}') ?? 0,
      minStock: double.tryParse('${json['min_stock'] ?? 0}') ?? 0,
    );
  }
}
