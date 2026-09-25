import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/ingredient.dart';
import '../providers/ingredients_provider.dart';
import '../widgets/ingredient_form_dialog.dart';
import '../widgets/ingredient_restock_dialog.dart';

class IngredientsPage extends ConsumerStatefulWidget {
  const IngredientsPage({super.key});

  @override
  ConsumerState<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends ConsumerState<IngredientsPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final ingredientsAsync = ref.watch(ingredientsProvider);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Rechercher un ingrédient...',
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Nouveau stock'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ingredientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                message: error is ApiException ? error.message : 'Could not load ingredients.',
                onRetry: () => ref.read(ingredientsProvider.notifier).refresh(),
              ),
              data: (ingredients) {
                final filtered = _search.isEmpty
                    ? ingredients
                    : ingredients.where((i) => i.name.toLowerCase().contains(_search)).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child:
                        Text('Aucun ingrédient trouvé', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HeaderRow(),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final ingredient = filtered[index];
                            return _IngredientRow(
                              ingredient: ingredient,
                              onEdit: () => _openForm(context, existing: ingredient),
                              onRestock: () => _openRestock(context, ingredient),
                              onDelete: () => _confirmDelete(context, ingredient),
                              onToggleActive: () => _toggleActive(context, ingredient),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, {Ingredient? existing}) {
    showDialog(
      context: context,
      builder: (_) => IngredientFormDialog(
        existing: existing,
        onSubmit: (input) async {
          final notifier = ref.read(ingredientsProvider.notifier);
          if (existing == null) {
            await notifier.createIngredient(input);
          } else {
            await notifier.updateIngredient(existing.id, input);
          }
        },
      ),
    );
  }

  void _openRestock(BuildContext context, Ingredient ingredient) {
    showDialog(
      context: context,
      builder: (_) => IngredientRestockDialog(
        ingredient: ingredient,
        onSubmit: (quantity, note) => ref
            .read(ingredientsProvider.notifier)
            .addStock(ingredient.id, quantity, note: note),
      ),
    );
  }

  /// "Supprimer" always succeeds from the user's point of view (spec
  /// §1/§17): the backend removes this ingredient from every product
  /// recipe that used it, then either hard-deletes it (no stock/purchase
  /// history) or deactivates it (history exists and must be preserved —
  /// see ingredientService.remove). Either way it disappears from this
  /// screen and from every recipe/ingredient picker right away.
  Future<void> _confirmDelete(BuildContext context, Ingredient ingredient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cet ingrédient ?'),
        content: Text(
          '"${ingredient.name}" sera retiré de toutes les recettes.\n\n'
          'Son historique de stock et ses achats seront conservés.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref.read(ingredientsProvider.notifier).deleteIngredient(ingredient.id);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      // Only unexpected failures reach here now (network error, the
      // ingredient was already deleted elsewhere, permission issue,
      // ...) — never display a raw error, always the backend's own
      // user-facing message (spec §22).
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Impossible de supprimer'),
          content: Text(error.message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<void> _deactivate(BuildContext context, Ingredient ingredient) async {
    try {
      await ref.read(ingredientsProvider.notifier).deactivateIngredient(ingredient.id);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Erreur'),
          content: Text(error.message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  /// Menu entry: "Désactiver" / "Réactiver" toggle, independent of the
  /// delete flow — lets a manager deliberately retire (or bring back) a
  /// supply without going through a blocked-delete dialog first.
  Future<void> _toggleActive(BuildContext context, Ingredient ingredient) async {
    final notifier = ref.read(ingredientsProvider.notifier);
    try {
      if (ingredient.isActive) {
        await notifier.deactivateIngredient(ingredient.id);
      } else {
        await notifier.updateIngredient(ingredient.id, {'is_active': true});
      }
    } on ApiException catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Erreur'),
          content: Text(error.message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontSize: 12.5);
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Ingrédient', style: style)),
          Expanded(flex: 2, child: Text('Quantité', style: style)),
          Expanded(flex: 2, child: Text('Coût moyen', style: style)),
          Expanded(flex: 2, child: Text('Stock min', style: style)),
          Expanded(flex: 2, child: Text('Statut', style: style)),
          SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;
  final VoidCallback onEdit;
  final VoidCallback onRestock;
  final VoidCallback onDelete;
  final VoidCallback onToggleActive;

  const _IngredientRow({
    required this.ingredient,
    required this.onEdit,
    required this.onRestock,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final statusInfo = ingredient.isActive
        ? _statusInfo(ingredient.status)
        : const _StatusInfo('Inactif', AppColors.textSecondary, Color(0xFFE5E7EB));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Opacity(
        opacity: ingredient.isActive ? 1 : 0.6,
        child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: statusInfo.iconBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.scatter_plot_outlined, size: 18, color: statusInfo.color),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(ingredient.name,
                      style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${ingredient.stockQuantity} ${ingredient.unit.name}'),
          ),
          Expanded(
            flex: 2,
            child: Text('${ingredient.costPerUnit.toStringAsFixed(2)} DH'),
          ),
          Expanded(
            flex: 2,
            child: Text('${ingredient.minStock} ${ingredient.unit.name}',
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusInfo.iconBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusInfo.label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusInfo.color),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Nouveau stock',
                  icon: const Icon(Icons.add_box_outlined, size: 20),
                  onPressed: onRestock,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                    if (value == 'toggle_active') onToggleActive();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                    PopupMenuItem(
                      value: 'toggle_active',
                      child: Text(ingredient.isActive ? 'Désactiver' : 'Réactiver'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                  ],
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  _StatusInfo _statusInfo(IngredientStockStatus status) {
    switch (status) {
      case IngredientStockStatus.rupture:
        return _StatusInfo('Rupture', AppColors.danger, const Color(0xFFFEE2E2));
      case IngredientStockStatus.faible:
        return _StatusInfo('Faible', AppColors.warning, const Color(0xFFFEF3C7));
      case IngredientStockStatus.normal:
        return _StatusInfo('Normal', AppColors.success, AppColors.primarySurface);
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final Color iconBg;

  const _StatusInfo(this.label, this.color, this.iconBg);
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
