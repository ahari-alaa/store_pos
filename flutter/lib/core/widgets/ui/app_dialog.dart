import 'package:flutter/material.dart';

import '../../design/design_system.dart';
import 'app_button.dart';

/// The shell every dialog in the application uses: title row with an
/// explicit close button, a scrollable body, and an action bar pinned to
/// the bottom with cancel on the left of the primary action.
///
/// The body is scrollable and the whole dialog is height-capped, which
/// fixes a real class of bug in the old dialogs: the product and expense
/// forms overflowed vertically on a short window (a 1366x768 laptop, or a
/// half-height window on any screen), pushing the save button off-screen
/// with no way to reach it.
class AppDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  /// Action buttons, right-aligned. Order them least- to most-important:
  /// the primary action goes last, nearest the corner the eye lands on.
  final List<Widget> actions;

  final double width;

  /// Hides the close button. Only for a dialog that must be answered —
  /// which in this application is essentially never.
  final bool dismissible;

  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.width = 520,
    this.dismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final media = MediaQuery.of(context);

    return Dialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          // Never taller than the window minus its insets, so the action
          // bar is always reachable.
          maxHeight: media.size.height - AppSpacing.xxl * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primarySurface,
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(icon,
                          size: AppSizes.iconMd, color: colors.primary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: text.sectionTitle),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(subtitle!, style: text.bodySecondary),
                        ],
                      ],
                    ),
                  ),
                  if (dismissible)
                    AppIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  else
                    const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: child,
              ),
            ),
            if (actions.isNotEmpty) ...[
              Divider(height: 1, thickness: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog.
///
/// [consequence] is the important parameter and the reason this exists:
/// a delete dialog that says "Êtes-vous sûr ?" tells the user nothing. It
/// should say what will actually happen — "Ce produit sera retiré du
/// catalogue. Les ventes déjà enregistrées ne sont pas affectées." That
/// sentence is what prevents the mistake.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? consequence,
  String confirmLabel = 'Confirmer',
  String cancelLabel = 'Annuler',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      final text = dialogContext.text;

      return AppDialog(
        title: title,
        width: 460,
        icon: icon ?? (destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: text.body),
            if (consequence != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: destructive ? colors.dangerSurface : colors.infoSurface,
                  borderRadius: AppRadius.smAll,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      destructive
                          ? Icons.error_outline_rounded
                          : Icons.info_outline_rounded,
                      size: AppSizes.iconSm,
                      color: destructive ? colors.danger : colors.info,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        consequence,
                        style: text.bodySecondary.copyWith(
                          color: destructive ? colors.danger : colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          AppButton.text(
            label: cancelLabel,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          if (destructive)
            AppButton.destructive(
              label: confirmLabel,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            )
          else
            AppButton.primary(
              label: confirmLabel,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Non-blocking feedback. Replaces the raw `ScaffoldMessenger` calls that
/// were scattered through the POS with a hard-coded red or blue
/// background and no icon.
enum AppToastKind { success, error, info, warning }

void showAppToast(
  BuildContext context, {
  required String message,
  AppToastKind kind = AppToastKind.info,
  SnackBarAction? action,
}) {
  final colors = context.colors;

  final (Color accent, IconData icon) = switch (kind) {
    AppToastKind.success => (colors.success, Icons.check_circle_outline_rounded),
    AppToastKind.error => (colors.danger, Icons.error_outline_rounded),
    AppToastKind.warning => (colors.warning, Icons.warning_amber_rounded),
    AppToastKind.info => (colors.info, Icons.info_outline_rounded),
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.textPrimary,
        elevation: 0,
        width: 420,
        duration: const Duration(seconds: 4),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        action: action,
        content: Row(
          children: [
            Icon(icon, size: AppSizes.iconMd, color: accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: colors.surface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
