import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/product_image.dart';
import '../../../ingredients/domain/entities/recipe.dart';
import '../../../ingredients/presentation/providers/ingredients_provider.dart';
import '../../../ingredients/presentation/providers/recipe_provider.dart';
import '../../../ingredients/presentation/widgets/add_recipe_line_dialog.dart';
import '../../../pos/domain/entities/product.dart';
import 'product_status_badge.dart';

/// Expanded read-only summary of the selected product, shown below the
/// products table. The recipe section is wired to the real
/// ingredients/recipe API; the supply-availability / possible-production
/// panel on the right comes straight from that same recipe response,
/// which already normalizes units and picks the limiting supply
/// server-side (see recipeService.getForProduct).
class ProductDetailPanel extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onRestock;
  final VoidCallback onClose;

  const ProductDetailPanel({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onRestock,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            flex: 2,
            child: _MainCard(
                product: product,
                onEdit: onEdit,
                onRestock: onRestock,
                onClose: onClose)),
        const SizedBox(width: 20),
        Expanded(child: _SupplyAvailability(productId: product.id)),
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onRestock;
  final VoidCallback onClose;

  const _MainCard({
    required this.product,
    required this.onEdit,
    required this.onRestock,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Product details',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                OutlinedButton.icon(
                  onPressed: onRestock,
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text('Restock'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit product'),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 108,
                  height: 108,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.primaryLight, width: 1.5),
                  ),
                  child: product.fullImageUrl != null
                      ? ProductImage(
                          imageUrl: product.fullImageUrl, cacheWidth: 216)
                      : const Icon(Icons.inventory_2_outlined,
                          color: AppColors.primaryDark, size: 30),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(product.name,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          ProductStatusBadge.forProduct(product),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 28,
                        runSpacing: 14,
                        children: [
                          _Field('Category', product.category ?? '—'),
                          _Field('SKU', product.sku ?? '—'),
                          _Field('Selling price',
                              CurrencyFormatter.format(product.price)),
                          _Field('Stock', '${product.stockQuantity}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 18, 22, 4),
            child: _SectionHeading(
              title: 'Recipe',
              subtitle:
                  'The supplies required to produce one unit of this product.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
            child: _RecipeEditor(productId: product.id),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(subtitle,
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Real recipe editor, backed by /api/products/:id/ingredients: a supply
/// table (edit/delete per line), "+ Add supply" dialog, and a live
/// ingredient-cost / margin summary card.
class _RecipeEditor extends ConsumerWidget {
  final String productId;

  const _RecipeEditor({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeProvider(productId));

    return recipeAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text('Could not load the recipe: $error',
            style: const TextStyle(color: AppColors.danger)),
      ),
      data: (recipe) {
        return Column(
          children: [
            if (recipe.lines.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1.1),
                    3: FlexColumnWidth(1),
                    4: FlexColumnWidth(1),
                    5: FlexColumnWidth(0.8),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: AppColors.background),
                      children: [
                        _HeadCell('SUPPLY'),
                        _HeadCell('PER UNIT'),
                        _HeadCell('STOCK'),
                        _HeadCell('PRODUCTION'),
                        _HeadCell('COST'),
                        _HeadCell(''),
                      ],
                    ),
                    for (final line in recipe.lines)
                      TableRow(children: [
                        _BodyCell(line.ingredientName, bold: true),
                        _BodyCell('${line.quantity} ${line.unit}'),
                        _BodyCell(
                            '${line.ingredientStock} ${line.ingredientUnit}'),
                        _BodyCell(line.possibleProduction == null
                            ? '—'
                            : '${line.possibleProduction}'),
                        _BodyCell('${line.lineCost.toStringAsFixed(2)} DH'),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined, size: 15),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 28),
                                onPressed: () =>
                                    _openEditDialog(context, ref, line),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline,
                                    size: 15, color: AppColors.danger),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 28, minHeight: 28),
                                onPressed: () =>
                                    _confirmRemove(context, ref, line),
                              ),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'No supplies added yet. Add supplies used to produce this product.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openAddDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('+ Add supply'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primaryLight),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PRODUCTION COST',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: AppColors.primaryDark)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _SummaryStat('Production cost',
                          '${recipe.ingredientsCost.toStringAsFixed(2)} DH'),
                      _SummaryStat('Selling price',
                          '${recipe.salePrice.toStringAsFixed(2)} DH'),
                      _SummaryStat('Estimated profit',
                          '${recipe.margin.toStringAsFixed(2)} DH'),
                      _SummaryStat('Margin', '${recipe.marginPercent}%',
                          highlight: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _openAddDialog(BuildContext context, WidgetRef ref) {
    final ingredientsAsync = ref.read(ingredientsProvider);
    final allIngredients = ingredientsAsync.valueOrNull ?? const [];
    final recipe = ref.read(recipeProvider(productId)).valueOrNull;
    final usedIds = recipe?.lines.map((l) => l.ingredientId).toSet() ?? {};
    final available = allIngredients
        .where((i) => i.isActive && !usedIds.contains(i.id))
        .toList();

    showDialog(
      context: context,
      builder: (_) => AddRecipeLineDialog(
        availableIngredients: available,
        onSubmit: (ingredientId, quantity, unit) => ref
            .read(recipeProvider(productId).notifier)
            .addLine(ingredientId, quantity, unit: unit),
      ),
    );
  }

  void _openEditDialog(BuildContext context, WidgetRef ref, RecipeLine line) {
    showDialog(
      context: context,
      builder: (_) => AddRecipeLineDialog(
        availableIngredients: const [],
        existingLine: line,
        onSubmit: (ingredientId, quantity, unit) => ref
            .read(recipeProvider(productId).notifier)
            .updateLine(ingredientId, quantity, unit: unit),
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, RecipeLine line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove supply'),
        content: Text('Remove ${line.ingredientName} from this recipe?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(recipeProvider(productId).notifier)
          .removeLine(line.ingredientId);
    }
  }
}

class _HeadCell extends StatelessWidget {
  final String text;
  const _HeadCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.textMuted)),
    );
  }
}

class _BodyCell extends StatelessWidget {
  final String text;
  final bool bold;
  const _BodyCell(this.text, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _SummaryStat(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color:
                    highlight ? AppColors.primaryDark : AppColors.textPrimary,
              )),
        ],
      ),
    );
  }
}

/// "Possible production" panel (spec §6/§27): reads this product's
/// recipe, which already carries live supply stock, per-line possible
/// production, and the overall limiting supply computed server-side (so
/// unit conversion — e.g. a recipe in g against stock in kg — is always
/// correct).
class _SupplyAvailability extends ConsumerWidget {
  final String productId;

  const _SupplyAvailability({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeProvider(productId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: recipeAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) =>
              Text('$error', style: const TextStyle(color: AppColors.danger)),
          data: (recipe) {
            if (recipe.lines.isEmpty) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Supply availability',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(
                      'No recipe set — add supplies to see possible production.',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              );
            }

            final sellable = recipe.possibleProduction;
            final isAvailable = sellable > 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Supply availability',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                const Text('Based on current supply stock',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                for (final line in recipe.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          line.ingredientName == recipe.limitingIngredient
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle,
                          size: 15,
                          color:
                              line.ingredientName == recipe.limitingIngredient
                                  ? AppColors.danger
                                  : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(line.ingredientName,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          '${line.ingredientStock} ${line.ingredientUnit} available'
                          '${line.possibleProduction != null ? ' · ≈${line.possibleProduction}' : ''}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text('$sellable units',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      const Text('Possible production',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textSecondary)),
                      if (recipe.limitingIngredient != null) ...[
                        const SizedBox(height: 4),
                        Text('Limiting supply: ${recipe.limitingIngredient}',
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isAvailable
                        ? AppColors.primarySurface
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          isAvailable
                              ? Icons.check_circle
                              : Icons.error_outline_rounded,
                          size: 15,
                          color: isAvailable
                              ? AppColors.primaryDark
                              : AppColors.danger),
                      const SizedBox(width: 7),
                      Text(
                        isAvailable
                            ? 'Product available'
                            : 'Produit indisponible',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: isAvailable
                                ? AppColors.primaryDark
                                : AppColors.danger),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
