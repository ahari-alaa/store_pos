import 'package:flutter/material.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/status_badge.dart';
import '../../domain/entities/product.dart';
import 'category_style.dart';

/// A product tile in the POS catalog.
///
/// Reading order top to bottom: image (what is it), name (confirm it),
/// price (what it costs), availability (can I sell it). The price sits
/// with the name rather than floating above the image, because those two
/// are what the cashier matches against what the customer said.
///
/// An out-of-stock product is not hidden — a cashier needs to be able to
/// tell a customer "we have none" rather than wonder whether they are
/// searching wrong — but it is visibly inert: desaturated, not clickable,
/// and badged.
class ProductCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;

  /// Quantity of this product already in the cart, or 0. Shown as a
  /// counter on the tile so the cashier can see what they have rung up
  /// without reading back through the order panel.
  final int quantityInCart;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.quantityInCart = 0,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final product = widget.product;
    final style = CategoryStyle.of(product.category ?? 'others');
    final outOfStock = product.isOutOfStock;
    final inCart = widget.quantityInCart > 0;

    final tile = AnimatedContainer(
      duration: AppDurations.fast,
      decoration: BoxDecoration(
        color: outOfStock
            ? colors.surfaceMuted
            : (_hovered ? colors.surfaceHover : colors.surface),
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: inCart
              ? colors.primary
              : (_hovered && !outOfStock ? colors.borderStrong : colors.border),
          width: inCart ? 1.5 : 1,
        ),
        boxShadow: _hovered && !outOfStock
            ? AppShadows.hover(Theme.of(context).brightness)
            : AppShadows.none,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                          style.color.withOpacity(0.10), colors.surface),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Opacity(
                      opacity: outOfStock ? 0.45 : 1,
                      child: product.fullImageUrl != null
                          ? Image.network(
                              product.fullImageUrl!,
                              // contain, not cover — never crop part of
                              // the product out of frame; letterbox on
                              // the tinted background instead.
                              fit: BoxFit.contain,
                              // Fast-scrolling grid: reuse decoded frames
                              // instead of re-decoding the same URL. The
                              // backend gives every re-uploaded image a
                              // new filename, so there is no stale-cache
                              // case to handle.
                              cacheWidth: 240,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, error, __) => Center(
                                child: Icon(style.icon,
                                    color: style.color, size: 30),
                              ),
                            )
                          : Center(
                              child: Icon(style.icon,
                                  color: style.color, size: 30),
                            ),
                    ),
                  ),
                ),
                if (outOfStock)
                  Positioned(
                    top: AppSpacing.sm - 2,
                    left: AppSpacing.sm - 2,
                    child: StatusBadge(
                      status: 'OUT_OF_STOCK',
                      label: 'Rupture',
                      size: StatusBadgeSize.small,
                    ),
                  )
                else if (product.stockQuantity <= 5)
                  Positioned(
                    top: AppSpacing.sm - 2,
                    left: AppSpacing.sm - 2,
                    child: StatusBadge(
                      status: 'LOW_STOCK',
                      label: 'Stock ${product.stockQuantity}',
                      size: StatusBadgeSize.small,
                    ),
                  ),
                if (inCart)
                  Positioned(
                    top: AppSpacing.sm - 2,
                    right: AppSpacing.sm - 2,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${widget.quantityInCart}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.body.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: outOfStock ? colors.textMuted : colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            CurrencyFormatter.format(product.price),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.price.copyWith(
              color: outOfStock ? colors.textMuted : colors.primary,
            ),
          ),
        ],
      ),
    );

    if (outOfStock) {
      return Tooltip(
        message: '${product.name} — rupture de stock',
        child: tile,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );
  }
}
