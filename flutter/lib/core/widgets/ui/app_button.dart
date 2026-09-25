import 'package:flutter/material.dart';

import '../../design/design_system.dart';

/// The six button roles this application has. There are no others.
///
/// Before the redesign the codebase had ElevatedButton, OutlinedButton,
/// TextButton, FilledButton, bare InkWell-in-a-Material, and at least four
/// one-off styled Containers, at heights of 30, 36, 44, 46, 50, 52 and 56
/// with font sizes down to 9.5. [AppButton] collapses all of that.
enum AppButtonVariant {
  /// Filled with the brand color. One per screen region — the action the
  /// user is there to perform (Pay, Save, Add product).
  primary,

  /// Filled with a muted surface. A common action that is not *the*
  /// action (Filter, Export).
  secondary,

  /// Bordered, transparent fill. Alternatives beside a primary.
  outline,

  /// No fill, no border. Tertiary actions and "Cancel" in dialogs.
  text,

  /// Filled red. Irreversible actions only — delete, void a sale,
  /// deactivate a user. Never use this because something is "important".
  destructive,
}

enum AppButtonSize { small, medium, large }

class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// Null disables the button. A disabled button keeps its footprint so
  /// the layout never shifts when it becomes available.
  final VoidCallback? onPressed;

  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Swaps the label for a spinner and blocks input. Use for any action
  /// that makes a network call, so the cashier can never double-submit a
  /// sale.
  final bool loading;

  /// Stretches to the width of the parent.
  final bool expand;

  final String? tooltip;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  }) : variant = AppButtonVariant.outline;

  const AppButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  }) : variant = AppButtonVariant.text;

  const AppButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.size = AppButtonSize.medium,
    this.loading = false,
    this.expand = false,
    this.tooltip,
  }) : variant = AppButtonVariant.destructive;

  double get _height {
    switch (size) {
      case AppButtonSize.small:
        return AppSizes.buttonHeightSm;
      case AppButtonSize.large:
        return AppSizes.buttonHeightLg;
      case AppButtonSize.medium:
        return AppSizes.buttonHeight;
    }
  }

  double get _fontSize {
    switch (size) {
      case AppButtonSize.small:
        return 13;
      case AppButtonSize.large:
        return 16;
      case AppButtonSize.medium:
        return 14;
    }
  }

  double get _horizontalPadding {
    switch (size) {
      case AppButtonSize.small:
        return AppSpacing.md;
      case AppButtonSize.large:
        return AppSpacing.xl;
      case AppButtonSize.medium:
        return AppSpacing.lg;
    }
  }

  /// (background, foreground, borderColor) for each variant.
  static (Color, Color, Color?) _styleFor(
      AppButtonVariant variant, AppColorScheme colors) {
    switch (variant) {
      case AppButtonVariant.primary:
        return (colors.primary, colors.onPrimary, null);
      case AppButtonVariant.secondary:
        return (colors.surfaceMuted, colors.textPrimary, null);
      case AppButtonVariant.outline:
        return (Colors.transparent, colors.textPrimary, colors.border);
      case AppButtonVariant.text:
        return (Colors.transparent, colors.primary, null);
      case AppButtonVariant.destructive:
        return (
          colors.danger,
          AppColorScheme.readableOn(colors.danger),
          null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null && !loading;

    final style = _styleFor(variant, colors);
    final Color background = style.$1;
    final Color foreground = style.$2;
    final Color? borderColor = style.$3;

    final effectiveBackground = enabled
        ? background
        : (background == Colors.transparent
            ? Colors.transparent
            : colors.disabled);
    final effectiveForeground = enabled ? foreground : colors.onDisabled;

    Widget content;
    if (loading) {
      content = SizedBox(
        width: _fontSize + 4,
        height: _fontSize + 4,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: effectiveForeground,
        ),
      );
    } else {
      content = Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size == AppButtonSize.small ? AppSizes.iconSm : AppSizes.iconMd),
            const SizedBox(width: AppSpacing.sm),
          ],
          // Flexible so a long label in a narrow column ellipsises
          // instead of throwing a horizontal overflow — the single most
          // common overflow source in the old cart/toolbar rows.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _fontSize,
                fontWeight: FontWeight.w600,
                color: effectiveForeground,
              ),
            ),
          ),
        ],
      );
    }

    Widget button = SizedBox(
      height: _height,
      width: expand ? double.infinity : null,
      child: Material(
        color: effectiveBackground,
        borderRadius: AppRadius.smAll,
        child: InkWell(
          borderRadius: AppRadius.smAll,
          onTap: enabled ? onPressed : null,
          // A real desktop hover/press response, which the bare
          // Material-default buttons did not give on the tinted surfaces
          // this app uses.
          hoverColor: foreground.withOpacity(0.06),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
            decoration: BoxDecoration(
              borderRadius: AppRadius.smAll,
              border: borderColor != null
                  ? Border.all(color: enabled ? borderColor : colors.disabled)
                  : null,
            ),
            child: IconTheme(
              data: IconThemeData(color: effectiveForeground),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// A square icon-only button. Always give it a [tooltip] — an icon with
/// no label and no tooltip is a guessing game, and several of the old
/// toolbar icons were exactly that.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  /// Renders the icon in the danger color. For row-level delete actions.
  final bool destructive;

  /// Draws a muted background behind the icon, so it reads as a control
  /// rather than as decoration.
  final bool filled;

  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.destructive = false,
    this.filled = false,
    this.size = AppSizes.iconButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;

    final foreground = !enabled
        ? colors.onDisabled
        : destructive
            ? colors.danger
            : colors.textSecondary;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: filled ? colors.surfaceMuted : Colors.transparent,
          borderRadius: AppRadius.smAll,
          child: InkWell(
            borderRadius: AppRadius.smAll,
            onTap: onPressed,
            child: Icon(icon, size: AppSizes.iconMd, color: foreground),
          ),
        ),
      ),
    );
  }
}
