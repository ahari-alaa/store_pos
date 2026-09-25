import 'package:flutter/material.dart';

import '../../design/design_system.dart';

/// The standard content surface: 1px border, 14px radius, no shadow.
///
/// Replaces the ad-hoc `Container(decoration: BoxDecoration(...))` blocks
/// that were repeated across screens with slightly different radii (12,
/// 16, 20), different border colors and inconsistent padding.
///
/// Set [onTap] to make the whole card interactive — it then gains a hover
/// state and a pointer cursor, which is what a desktop user expects from
/// something clickable.
class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Draws a 1.5px primary-colored border. For the selected card in a
  /// set (a chosen payment method, an open order).
  final bool selected;

  /// Renders the card in its "needs attention" state — used for low
  /// stock, failed sync, overdue payment. Never for decoration.
  final Color? accentBorderColor;

  final double? width;
  final double? height;

  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.selected = false,
    this.accentBorderColor,
    this.width,
    this.height,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onTap != null;

    final borderColor = widget.accentBorderColor ??
        (widget.selected ? colors.primary : colors.border);

    final card = AnimatedContainer(
      duration: AppDurations.fast,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: interactive && _hovered ? colors.surfaceHover : colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: borderColor,
          width: widget.selected || widget.accentBorderColor != null ? 1.5 : 1,
        ),
        boxShadow: interactive && _hovered
            ? AppShadows.hover(Theme.of(context).brightness)
            : AppShadows.none,
      ),
      child: widget.child,
    );

    if (!interactive) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}

/// A titled card: header row (icon + title + optional trailing action),
/// a hairline, then the body. This is the shape every dashboard widget,
/// settings group and detail panel in the app should use, so they all
/// have the same header height and internal padding.
class AppSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Right-hand side of the header — typically a text button ("Voir
  /// tout") or a small filter control. Keep it to one control.
  final Widget? action;

  final Widget child;

  /// Removes the body padding, for a card whose body is a full-bleed
  /// table or list that manages its own insets.
  final bool bodyFlush;

  const AppSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.action,
    this.bodyFlush = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: AppSizes.iconMd, color: colors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: text.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: text.bodySecondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  action!,
                ] else
                  const SizedBox(width: AppSpacing.sm),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          Padding(
            padding:
                bodyFlush ? EdgeInsets.zero : const EdgeInsets.all(AppSpacing.lg),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A plain heading above a group of cards — no surface of its own.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: text.sectionTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: text.bodySecondary),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
