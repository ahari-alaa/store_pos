import 'package:flutter/material.dart';

import '../../../../core/design/design_system.dart';
import '../widgets/cart_panel.dart';
import '../widgets/category_sidebar.dart';
import '../widgets/pos_header.dart';
import '../widgets/product_grid.dart';

/// The POS screen: the surface a cashier spends their shift on, and the
/// one where every extra click costs real time at a queue.
///
/// Layout — catalog on the left, current order on the right:
///
///   ┌──────────────────────────────────────┬──────────────┐
///   │ search / scan / cashier              │              │
///   ├────────────┬─────────────────────────┤  CURRENT     │
///   │ CATEGORIES │ PRODUCT TILES           │  ORDER       │
///   │            │                         │  + payment   │
///   └────────────┴─────────────────────────┴──────────────┘
///
/// The order panel moved from the left edge to the right. Reading order
/// in this application is left-to-right — pick products, then review and
/// pay — and putting the total and the pay button in the bottom-right
/// corner places them where the eye finishes and where the pointer
/// already is after clicking through the catalog.
///
/// The cart lives outside the category/product column entirely, so
/// switching categories can never affect it.
class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this width the category rail becomes a horizontal chip
        // row above the grid rather than a column, so the catalog keeps
        // usable width instead of the tiles collapsing to two per row.
        final compact = constraints.maxWidth < AppSizes.posCompactBreakpoint;

        return ColoredBox(
          color: colors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    const PosHeader(),
                    if (compact) const CategoryChipRow(),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!compact) const CategorySidebar(),
                          const Expanded(child: ProductGrid()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              CartPanel(compact: compact),
            ],
          ),
        );
      },
    );
  }
}
