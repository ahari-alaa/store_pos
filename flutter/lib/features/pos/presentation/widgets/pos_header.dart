import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/widgets/app_top_bar.dart';
import '../../../../core/widgets/ui/app_text_field.dart';
import '../../domain/entities/product.dart';
import '../providers/cart_provider.dart';
import '../providers/pos_providers.dart';

/// The POS screen's own header.
///
/// The search field doubles as the barcode-scanner input: a USB/Bluetooth
/// scanner behaves like a keyboard, typing the barcode into whatever
/// field has focus and then sending Enter. The field is autofocused so a
/// scan works without the cashier clicking anything first.
///
/// On submit (the Enter a scanner sends), if the current filter has
/// narrowed to exactly one in-stock product, that product is added to the
/// order and the field clears — which turns a scan into a complete
/// "add to order" action rather than just a filter. Anything ambiguous
/// leaves the filtered grid up for the cashier to choose from, because
/// guessing which of several matches was scanned is how the wrong item
/// ends up on a receipt.
class PosHeader extends ConsumerStatefulWidget {
  const PosHeader({super.key});

  @override
  ConsumerState<PosHeader> createState() => _PosHeaderState();
}

class _PosHeaderState extends ConsumerState<PosHeader> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;

    final matches = ref.read(filteredProductsProvider);
    if (matches.length == 1 && !matches.first.isOutOfStock) {
      ref.read(cartProvider.notifier).addProduct(matches.first);
      _controller.clear();
      ref.read(searchQueryProvider.notifier).state = '';
    }
    // Keep focus on the field either way, so consecutive scans work
    // without the cashier clicking back into it.
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: AppSizes.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              // Capped rather than filling the bar: a search field
              // stretched across a 2560px monitor looks unfinished, and
              // the space is better given to the status cluster.
              constraints: const BoxConstraints(maxWidth: 520),
              child: AppSearchField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                hint: 'Rechercher un produit ou scanner un code-barres',
                onChanged: (value) =>
                    ref.read(searchQueryProvider.notifier).state = value,
                onSubmitted: _onSubmitted,
                trailing: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Tooltip(
                    message: 'Scannez un code-barres : le lecteur saisit '
                        'directement dans ce champ',
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      size: AppSizes.iconMd,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          const _StockAlertsButton(),
          const SizedBox(width: AppSpacing.lg),
          const ConnectionStatusChip(),
          const SizedBox(width: AppSpacing.lg),
          const _PosUserBadge(),
        ],
      ),
    );
  }
}

/// Products currently at zero stock, derived from the live POS product
/// list. Real data, not a placeholder notification count.
final outOfStockProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
  return products.where((p) => p.isOutOfStock).toList();
});

/// Low-stock products (at or below five units), the level at which a
/// cashier should be warning a manager rather than discovering a rupture
/// mid-sale.
final lowStockProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
  return products
      .where((p) => !p.isOutOfStock && p.stockQuantity <= 5)
      .toList();
});

/// Stock alerts.
///
/// This replaces the old bell icon, which was labelled "notifications"
/// but only ever listed out-of-stock products — so its badge count meant
/// something different from what the icon implied. It now says what it
/// is, shows both rupture and low-stock levels, and each entry is
/// actionable: clicking one jumps to that product in the catalog.
class _StockAlertsButton extends ConsumerWidget {
  const _StockAlertsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final outOfStock = ref.watch(outOfStockProductsProvider);
    final lowStock = ref.watch(lowStockProductsProvider);
    final count = outOfStock.length + lowStock.length;
    final hasRupture = outOfStock.isNotEmpty;

    return PopupMenuButton<String>(
      tooltip: count > 0
          ? '$count alerte${count > 1 ? 's' : ''} de stock'
          : 'Aucune alerte de stock',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 380),
      onSelected: (productId) {
        // Filter the catalog down to the chosen product so the cashier
        // lands on it rather than having to search for it by hand.
        final match = [...outOfStock, ...lowStock]
            .where((p) => p.id == productId);
        if (match.isNotEmpty) {
          ref.read(searchQueryProvider.notifier).state = match.first.name;
        }
      },
      itemBuilder: (context) {
        if (count == 0) {
          return [
            PopupMenuItem<String>(
              enabled: false,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: AppSizes.iconSm, color: colors.success),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Tous les produits sont en stock',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ];
        }

        return [
          PopupMenuItem<String>(
            enabled: false,
            height: 36,
            child: Text(
              'ALERTES DE STOCK',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 0.8,
                color: colors.textMuted,
              ),
            ),
          ),
          for (final product in outOfStock)
            _alertItem(context, product, isRupture: true),
          for (final product in lowStock)
            _alertItem(context, product, isRupture: false),
        ];
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: AppSizes.iconButtonSize,
            height: AppSizes.iconButtonSize,
            decoration: BoxDecoration(
              color: count > 0
                  ? (hasRupture ? colors.dangerSurface : colors.warningSurface)
                  : colors.surfaceMuted,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(
              count > 0
                  ? Icons.inventory_2_outlined
                  : Icons.inventory_2_outlined,
              size: AppSizes.iconMd,
              color: count > 0
                  ? (hasRupture ? colors.danger : colors.warning)
                  : colors.textSecondary,
            ),
          ),
          if (count > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hasRupture ? colors.danger : colors.warning,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _alertItem(
    BuildContext context,
    Product product, {
    required bool isRupture,
  }) {
    final colors = context.colors;
    final accent = isRupture ? colors.danger : colors.warning;

    return PopupMenuItem<String>(
      value: product.id,
      height: 44,
      child: Row(
        children: [
          Icon(
            isRupture
                ? Icons.error_outline_rounded
                : Icons.warning_amber_rounded,
            size: AppSizes.iconSm,
            color: accent,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            isRupture ? 'Rupture' : '${product.stockQuantity} restant',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cashier identity on the POS header.
///
/// This is the shared [UserMenuButton] from the application top bar, not
/// a second implementation. The POS used to carry its own badge with an
/// English role label and its own logout path, which is how the two
/// headers drifted apart.
class _PosUserBadge extends StatelessWidget {
  const _PosUserBadge();

  @override
  Widget build(BuildContext context) => const UserMenuButton();
}
