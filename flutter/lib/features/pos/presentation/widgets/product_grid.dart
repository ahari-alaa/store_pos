import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/ui/app_states.dart';
import '../providers/cart_provider.dart';
import '../providers/pos_providers.dart';
import 'product_card.dart';

/// The product catalog.
///
/// Three things changed beyond styling:
///
///  * loading shows a skeleton grid rather than a centred spinner, so the
///    page keeps its shape and the tiles do not jump into place;
///  * the error state says what failed in plain French and offers a
///    retry, instead of surfacing whatever `ApiException.message` held —
///    those messages are written for developers and mention the backend
///    URL;
///  * the empty state distinguishes "nothing matches your search" from
///    "this category is empty" from "no products exist yet", and each
///    offers the action that actually resolves it.
class ProductGrid extends ConsumerWidget {
  const ProductGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);

    return Column(
      children: [
        const _CatalogTitleBar(),
        Expanded(
          child: productsAsync.when(
            loading: () => LayoutBuilder(
              builder: (context, constraints) => AppCardGridSkeleton(
                columns: (constraints.maxWidth / AppSizes.productTileTarget)
                    .floor()
                    .clamp(2, 8),
                count: 12,
              ),
            ),
            error: (error, _) => AppErrorState(
              title: 'Catalogue indisponible',
              message: error is ApiException && error.code == 'NETWORK_ERROR'
                  ? 'Le serveur est injoignable. Vérifiez la connexion réseau, '
                      'puis réessayez.'
                  : 'Les produits n\'ont pas pu être chargés. Réessayez dans '
                      'un instant.',
              onRetry: () => ref.invalidate(productsProvider),
              // The raw message is kept available but folded away — a
              // manager diagnosing a misconfigured server can open it,
              // a cashier mid-queue never sees it.
              technicalDetail: error is ApiException
                  ? '${error.code}: ${error.message}'
                  : error.toString(),
            ),
            data: (_) {
              final products = ref.watch(filteredProductsProvider);
              final query = ref.watch(searchQueryProvider);
              final category = ref.watch(selectedCategoryProvider);

              if (products.isEmpty) {
                if (query.trim().isNotEmpty) {
                  return AppEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Aucun produit trouvé',
                    message:
                        'Aucun produit ne correspond à « ${query.trim()} ». '
                        'Vérifiez l\'orthographe ou scannez le code-barres.',
                    actionLabel: 'Effacer la recherche',
                    actionIcon: Icons.close_rounded,
                    onAction: () =>
                        ref.read(searchQueryProvider.notifier).state = '',
                  );
                }
                if (category != kAllCategoryId) {
                  return AppEmptyState(
                    icon: Icons.category_outlined,
                    title: 'Catégorie vide',
                    message:
                        'Aucun produit dans cette catégorie pour le moment.',
                    actionLabel: 'Voir tous les produits',
                    actionIcon: Icons.grid_view_rounded,
                    onAction: () => ref
                        .read(selectedCategoryProvider.notifier)
                        .state = kAllCategoryId,
                  );
                }
                return const AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aucun produit au catalogue',
                  message:
                      'Ajoutez des produits depuis le module Produits pour '
                      'commencer à encaisser.',
                );
              }

              // Quantities already in the order, so each tile can show
              // its own counter without every tile watching the cart.
              final cartQuantities = <String, int>{
                for (final item in ref.watch(cartProvider))
                  item.product.id: item.quantity,
              };

              return LayoutBuilder(
                builder: (context, constraints) {
                  // Desktop-first: aim for ~200px tiles, never fewer than
                  // two columns, so this same widget survives a narrow
                  // window without a separate layout.
                  final crossAxisCount =
                      (constraints.maxWidth / AppSizes.productTileTarget)
                          .floor()
                          .clamp(2, 8);

                  return GridView.builder(
                    padding: AppSpacing.pagePadding,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: AppSpacing.lg,
                      crossAxisSpacing: AppSpacing.lg,
                      // Taller than wide: the tile carries an image, a
                      // two-line name and a price, and the old 0.92 ratio
                      // clipped the second name line.
                      childAspectRatio: 0.82,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ProductCard(
                        product: product,
                        quantityInCart: cartQuantities[product.id] ?? 0,
                        onTap: () =>
                            ref.read(cartProvider.notifier).addProduct(product),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Shows which catalog section is on screen, and how many products are in
/// it — the count is what tells a cashier whether scrolling is worth it.
class _CatalogTitleBar extends ConsumerWidget {
  const _CatalogTitleBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;
    final selected = ref.watch(selectedCategoryProvider);
    final categories = ref.watch(categoriesProvider);
    final query = ref.watch(searchQueryProvider);
    final visible = ref.watch(filteredProductsProvider);

    String title;
    if (query.trim().isNotEmpty) {
      title = 'Résultats de recherche';
    } else if (selected == kAllCategoryId) {
      title = 'Tous les produits';
    } else {
      final match = categories.where((c) => c.id == selected);
      title = match.isNotEmpty ? match.first.name : selected;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.sectionTitle,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            '${visible.length} produit${visible.length > 1 ? 's' : ''}',
            style: text.bodySecondary.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
