import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../pos/domain/entities/product.dart';

/// Stock quantity at or below this (but above zero) counts as "Low stock".
///
/// This is a UI-only heuristic for now — the backend has no per-product
/// reorder threshold yet (see `Product` entity). Once one exists, this
/// should read from the product instead of a hardcoded constant.
const int kLowStockThreshold = 10;

enum ProductAvailability { available, lowStock, outOfStock, inactive }

ProductAvailability availabilityOf(Product product) {
  if (!product.isActive) return ProductAvailability.inactive;
  if (product.stockQuantity <= 0) return ProductAvailability.outOfStock;
  if (product.stockQuantity <= kLowStockThreshold) return ProductAvailability.lowStock;
  return ProductAvailability.available;
}

class _StatusStyle {
  final String label;
  final Color color;
  final Color background;

  const _StatusStyle(this.label, this.color, this.background);
}

const Map<ProductAvailability, _StatusStyle> _styles = {
  ProductAvailability.available:
      _StatusStyle('Available', AppColors.primaryDark, AppColors.primarySurface),
  ProductAvailability.lowStock: _StatusStyle('Low stock', Color(0xFFB45309), Color(0xFFFFFBEB)),
  ProductAvailability.outOfStock: _StatusStyle('Out of stock', Color(0xFFB91C1C), Color(0xFFFEF2F2)),
  ProductAvailability.inactive:
      _StatusStyle('Inactive', AppColors.textMuted, AppColors.background),
};

/// Small pill badge used across the Products screen (table rows and the
/// detail panel) so a product's availability always reads the same way.
class ProductStatusBadge extends StatelessWidget {
  final ProductAvailability availability;

  const ProductStatusBadge({super.key, required this.availability});

  factory ProductStatusBadge.forProduct(Product product) {
    return ProductStatusBadge(availability: availabilityOf(product));
  }

  @override
  Widget build(BuildContext context) {
    final style = _styles[availability]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
          ),
          Text(
            style.label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: style.color),
          ),
        ],
      ),
    );
  }
}
