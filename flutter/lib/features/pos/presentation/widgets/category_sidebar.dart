import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../providers/pos_providers.dart';
import 'category_style.dart';

/// Always-visible category navigation.
///
/// A vertical list of large targets that sits permanently beside the
/// catalog: selecting a category never navigates away from the POS, so
/// the order panel (a sibling widget, not a child of this one) is never
/// affected.
///
/// The count moved onto the same line as the label instead of sitting
/// under it. That halves the row height, which means more categories are
/// visible without scrolling — and on a register, a category that needs
/// scrolling to reach is a category that costs a second every time.
class CategorySidebar extends ConsumerWidget {
  const CategorySidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final totalCount = ref.watch(allProductsCountProvider);

    return Container(
      width: AppSizes.posCategoryRailWidth,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg + 2,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Text(
              'CATÉGORIES',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: 0.8,
                color: colors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              children: [
                _CategoryTile(
                  id: kAllCategoryId,
                  label: 'Tout',
                  count: totalCount,
                  isSelected: selected == kAllCategoryId,
                  onTap: () => ref
                      .read(selectedCategoryProvider.notifier)
                      .state = kAllCategoryId,
                ),
                ...categories.map(
                  (category) => _CategoryTile(
                    id: category.id,
                    label: category.name,
                    count: category.count,
                    isSelected: selected == category.id,
                    onTap: () => ref
                        .read(selectedCategoryProvider.notifier)
                        .state = category.id,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatefulWidget {
  final String id;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.id,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = CategoryStyle.of(widget.id);

    final foreground =
        widget.isSelected ? colors.primary : colors.textSecondary;

    // No Tooltip here on purpose: the label and count are already fully
    // visible on the tile itself (see the class doc above), so a Tooltip
    // would be redundant -- and it would also stack its own hover-driven
    // OverlayEntry on top of this MouseRegion's onEnter/onExit setState.
    // The two reacting to the same hover events, on a list the mouse
    // sweeps down quickly, is exactly the pattern that trips Flutter's
    // MouseTracker reentrancy assertion (`'!_debugDuringDeviceUpdate'`)
    // and can hang the app. Keep this tile's hover surface to the single
    // MouseRegion below.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
              duration: AppDurations.fast,
              height: 44,
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? colors.primarySurface
                    : (_hovered ? colors.surfaceHover : Colors.transparent),
                borderRadius: AppRadius.smAll,
                border: Border.all(
                  color: widget.isSelected
                      ? colors.primary
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    style.icon,
                    size: AppSizes.iconSm + 2,
                    color: widget.isSelected ? colors.primary : style.color,
                  ),
                  const SizedBox(width: AppSpacing.sm + 2),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isSelected
                            ? colors.textPrimary
                            : foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${widget.count}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

/// Horizontal category selector used on narrow windows, where a fixed
/// 176px vertical rail would cost the catalog too much width.
///
/// Note this is a different presentation of the same state, not a
/// reduced one: every category is still reachable, by scrolling the row.
/// Nothing is dropped to make it fit.
class CategoryChipRow extends ConsumerWidget {
  const CategoryChipRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(selectedCategoryProvider);
    final totalCount = ref.watch(allProductsCountProvider);

    Widget chip(String id, String label, int count) {
      final isSelected = selected == id;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Material(
          color: isSelected ? colors.primary : colors.surfaceMuted,
          borderRadius: AppRadius.smAll,
          child: InkWell(
            borderRadius: AppRadius.smAll,
            onTap: () =>
                ref.read(selectedCategoryProvider.notifier).state = id,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              alignment: Alignment.center,
              child: Text(
                '$label · $count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? colors.onPrimary : colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 60,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        children: [
          chip(kAllCategoryId, 'Tout', totalCount),
          for (final category in categories)
            chip(category.id, category.name, category.count),
        ],
      ),
    );
  }
}
