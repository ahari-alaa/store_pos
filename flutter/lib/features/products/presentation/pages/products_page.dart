import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/product_image.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../pos/domain/entities/product.dart';
import '../../../pos/presentation/providers/products_manage_provider.dart';
import '../widgets/product_detail_panel.dart';
import '../widgets/product_form_dialog.dart';
import '../widgets/product_status_badge.dart';
import '../widgets/restock_dialog.dart';

/// "All categories" / "All statuses" pseudo-values for the filter pills.
const String _kAllCategories = 'All categories';
const String _kAllStatuses = 'All statuses';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  String _search = '';
  String _categoryFilter = _kAllCategories;
  String _statusFilter = _kAllStatuses;
  String? _selectedProductId;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user == null || !user.canManageProducts) {
      return const RestrictedPage(
        message: 'Only admins and managers can manage products.',
      );
    }

    final productsAsync = ref.watch(productsManageProvider);
    final deletingIds = ref.watch(deletingProductIdsProvider);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _PageHeading(),
              ),
              ElevatedButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('New product'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                message: error is ApiException
                    ? error.message
                    : 'Could not load products.',
                onRetry: () =>
                    ref.read(productsManageProvider.notifier).refresh(),
              ),
              data: (products) {
                final categories = _distinctCategories(products);

                final filtered = products.where((p) {
                  final matchesSearch = _search.isEmpty ||
                      p.name.toLowerCase().contains(_search) ||
                      (p.barcode?.toLowerCase().contains(_search) ?? false) ||
                      (p.sku?.toLowerCase().contains(_search) ?? false);
                  final matchesCategory = _categoryFilter == _kAllCategories ||
                      p.category == _categoryFilter;
                  final matchesStatus = _statusFilter == _kAllStatuses ||
                      _statusLabel(p) == _statusFilter;
                  return matchesSearch && matchesCategory && matchesStatus;
                }).toList();

                Product? selected;
                if (_selectedProductId != null) {
                  for (final p in products) {
                    if (p.id == _selectedProductId) {
                      selected = p;
                      break;
                    }
                  }
                }

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                prefixIcon:
                                    Icon(Icons.search_rounded, size: 20),
                                hintText: 'Search a product...',
                              ),
                              onChanged: (v) => setState(
                                  () => _search = v.trim().toLowerCase()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _FilterPill(
                            label: 'Category',
                            value: _categoryFilter,
                            options: [_kAllCategories, ...categories],
                            onChanged: (v) =>
                                setState(() => _categoryFilter = v),
                          ),
                          const SizedBox(width: 10),
                          _FilterPill(
                            label: 'Availability',
                            value: _statusFilter,
                            options: const [
                              _kAllStatuses,
                              'Available',
                              'Low stock',
                              'Out of stock',
                              'Inactive',
                            ],
                            onChanged: (v) => setState(() => _statusFilter = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Text('No products found',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          ),
                        )
                      else
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              const _HeaderRow(),
                              const Divider(height: 1),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final product = filtered[index];
                                  return _ProductRow(
                                    product: product,
                                    isSelected:
                                        product.id == _selectedProductId,
                                    isDeleting:
                                        deletingIds.contains(product.id),
                                    onSelect: () => setState(() {
                                      _selectedProductId =
                                          _selectedProductId == product.id
                                              ? null
                                              : product.id;
                                    }),
                                    onEdit: () =>
                                        _openForm(context, existing: product),
                                    onRestock: () =>
                                        _openRestock(context, product),
                                    onDeactivate: () =>
                                        _confirmDeactivate(context, product),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      if (selected != null) ...[
                        () {
                          // Captured into a `final` so Dart can promote it to
                          // non-null *inside* the closures below too — a
                          // `Product?` local narrowed by an `if (x != null)`
                          // only stays promoted for direct use in that scope,
                          // not for a variable captured by a lambda (the
                          // analyzer can't prove it isn't reassigned before
                          // the lambda runs), which is what tripped the
                          // Windows build error.
                          final selectedProduct = selected!;
                          return Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: ProductDetailPanel(
                              product: selectedProduct,
                              onEdit: () =>
                                  _openForm(context, existing: selectedProduct),
                              onRestock: () =>
                                  _openRestock(context, selectedProduct),
                              onClose: () =>
                                  setState(() => _selectedProductId = null),
                            ),
                          );
                        }(),
                      ],
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

  List<String> _distinctCategories(List<Product> products) {
    final set = <String>{};
    for (final p in products) {
      final c = p.category?.trim();
      if (c != null && c.isNotEmpty) set.add(c);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _statusLabel(Product product) {
    switch (availabilityOf(product)) {
      case ProductAvailability.available:
        return 'Available';
      case ProductAvailability.lowStock:
        return 'Low stock';
      case ProductAvailability.outOfStock:
        return 'Out of stock';
      case ProductAvailability.inactive:
        return 'Inactive';
    }
  }

  void _openForm(BuildContext context, {Product? existing}) {
    showDialog(
      context: context,
      builder: (_) => ProductFormDialog(
        existing: existing,
        onSubmit: (input,
            {imageBytes, imageFilename, removeImage = false}) async {
          final notifier = ref.read(productsManageProvider.notifier);
          final productId = existing == null
              ? await notifier.createProduct(input)
              : existing.id;
          if (existing != null) {
            await notifier.updateProduct(existing.id, input);
          }
          if (imageBytes != null && imageFilename != null) {
            await notifier.uploadImage(productId,
                bytes: imageBytes, filename: imageFilename);
          } else if (removeImage) {
            await notifier.removeImage(productId);
          }
        },
      ),
    );
  }

  void _openRestock(BuildContext context, Product product) {
    showDialog(
      context: context,
      builder: (_) => RestockDialog(
        product: product,
        onSubmit: (quantity, note) => ref
            .read(productsManageProvider.notifier)
            .restock(product.id, quantity, note: note),
      ),
    );
  }

  Future<void> _confirmDeactivate(BuildContext context, Product product) async {
    // Guard against duplicate requests: ignore a second tap (e.g. a fast
    // double-click on the icon button) while one is already in flight.
    if (ref.read(deletingProductIdsProvider).contains(product.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text(
          '"${product.name}" will be permanently deleted, including its photo. '
          'If it has past sales, it will be deactivated instead so sales history stays intact.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Captured BEFORE the `await` below, while `context` is definitely
    // still attached to a live element. Re-resolving
    // ScaffoldMessenger.of(context) *after* an await is the actual bug
    // that crashed with "Looking up a deactivated widget's ancestor is
    // unsafe": `mounted` can still read true for a State whose Element
    // has been deactivated (e.g. navigated away mid-request) but not yet
    // unmounted, so the ancestor lookup can fail even past a `mounted`
    // guard. Holding the messenger instance sidesteps the lookup
    // entirely on the far side of the await.
    final messenger = ScaffoldMessenger.of(context);

    // This can NEVER be allowed to throw unhandled: a failed request here
    // must show a readable error and leave the Products screen exactly as
    // it was, not blank the screen or crash the app.
    try {
      final wasDeactivatedInstead = await ref
          .read(productsManageProvider.notifier)
          .deactivateProduct(product.id);

      if (!mounted) return;
      if (_selectedProductId == product.id) {
        setState(() => _selectedProductId = null);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            wasDeactivatedInstead
                ? '"${product.name}" has past sales, so it was deactivated instead of deleted.'
                : '"${product.name}" deleted.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not delete product: ${e.message}'),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Something went wrong while deleting: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Products',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text(
          'Manage your products, ingredients and recipes',
          style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// A single filter dropdown styled as a pill ("Category ▾"), matching the
/// products-screen mockup. Built on [PopupMenuButton] so it needs no extra
/// package and keeps the same visual language as the rest of the app.
class _FilterPill extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _FilterPill({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = value == options.first;
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                if (option == value)
                  const Icon(Icons.check_rounded,
                      size: 16, color: AppColors.primary)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(option),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isDefault ? label : value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    isDefault ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textMuted,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: const [
          SizedBox(width: 58),
          Expanded(flex: 3, child: Text('PRODUCT', style: style)),
          Expanded(flex: 2, child: Text('SKU', style: style)),
          Expanded(flex: 2, child: Text('PRICE', style: style)),
          Expanded(flex: 2, child: Text('INGREDIENTS', style: style)),
          Expanded(flex: 1, child: Text('STOCK', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          SizedBox(width: 44, child: SizedBox.shrink()),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Product product;
  final bool isSelected;
  final bool isDeleting;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onRestock;
  final VoidCallback onDeactivate;

  const _ProductRow({
    required this.product,
    required this.isSelected,
    this.isDeleting = false,
    required this.onSelect,
    required this.onEdit,
    required this.onRestock,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        color: isSelected ? AppColors.primarySurface : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              margin: const EdgeInsets.only(right: 14),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: ProductImage(
                imageUrl: product.fullImageUrl,
                cacheWidth: 88,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                product.sku ?? '—',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                CurrencyFormatter.format(product.price),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Expanded(
              flex: 2,
              child: Text('—', style: TextStyle(color: AppColors.textMuted)),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${product.stockQuantity}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: product.isOutOfStock
                      ? AppColors.danger
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: ProductStatusBadge.forProduct(product),
            ),
            SizedBox(
              width: 44,
              child: isDeleting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : PopupMenuButton<_RowAction>(
                      icon: const Icon(Icons.more_horiz_rounded,
                          color: AppColors.textSecondary),
                      onSelected: (action) {
                        switch (action) {
                          case _RowAction.restock:
                            onRestock();
                            break;
                          case _RowAction.edit:
                            onEdit();
                            break;
                          case _RowAction.delete:
                            onDeactivate();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _RowAction.restock,
                          child: Row(children: [
                            Icon(Icons.add_box_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Restock'),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: _RowAction.edit,
                          child: Row(children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ]),
                        ),
                        if (product.isActive)
                          const PopupMenuItem(
                            value: _RowAction.delete,
                            child: Row(children: [
                              Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.danger),
                              SizedBox(width: 10),
                              Text('Delete',
                                  style: TextStyle(color: AppColors.danger)),
                            ]),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _RowAction { restock, edit, delete }

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
          const Icon(Icons.cloud_off_rounded,
              size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
