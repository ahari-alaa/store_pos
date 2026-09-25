import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Confirmation dialog for deactivating / reactivating a staff account.
///
/// Extracted from [CashiersPage] for one reason: the buttons MUST pop the
/// route that this dialog itself lives on, and nothing else.
///
/// The bug this replaces looked harmless:
///
/// ```dart
/// showDialog<bool>(
///   context: context,                                   // <- page context
///   builder: (_) => AlertDialog(                        // <- dialog context discarded
///     actions: [
///       TextButton(onPressed: () => Navigator.of(context).pop(false), ...),
///     ],
///   ),
/// );
/// ```
///
/// `showDialog` pushes onto the ROOT navigator (`useRootNavigator`
/// defaults to true), but `Navigator.of(context)` — where `context` is
/// the Cashiers *page's* context — resolves to the nearest enclosing
/// Navigator, which is the one go_router's `ShellRoute` creates for
/// [AppShell]'s child. So the buttons popped the shell navigator (i.e.
/// the `/cashiers` page itself) while the dialog sat untouched on the
/// root navigator. See the class docs on [showConfirmToggleActiveDialog].
///
/// Taking `dialogContext` from the builder makes the correct navigator
/// the only one reachable from the button callbacks — the page context is
/// not captured at all, so the old mistake can't be reintroduced here.
class ConfirmToggleActiveDialog extends StatelessWidget {
  /// Name of the account being acted on, shown in the body text.
  final String userName;

  /// True when the account is currently active (so the action deactivates
  /// it); false when the action reactivates it.
  final bool deactivating;

  const ConfirmToggleActiveDialog({
    super.key,
    required this.userName,
    required this.deactivating,
  });

  @override
  Widget build(BuildContext dialogContext) {
    return AlertDialog(
      title: Text(deactivating ? 'Deactivate account?' : 'Reactivate account?'),
      content: Text(
        deactivating
            ? '"$userName" will no longer be able to sign in.'
            : '"$userName" will be able to sign in again.',
      ),
      actions: [
        TextButton(
          // `dialogContext` is this widget's own context, which sits
          // inside the dialog route on the root navigator — so this pops
          // the dialog, never the page underneath it.
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: deactivating
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(deactivating ? 'Deactivate' : 'Reactivate'),
        ),
      ],
    );
  }
}

/// Shows [ConfirmToggleActiveDialog] and resolves to whether the admin
/// confirmed.
///
/// Returns `false` (never `null`) when dismissed, so callers can't
/// accidentally treat "no answer" as a confirmation.
///
/// `barrierDismissible` is false deliberately: the only two ways out are
/// the two buttons, both of which pop `dialogContext`. That keeps the
/// number of distinct code paths that can complete this future at exactly
/// two, which is what makes the caller's "close synchronously, THEN do
/// async work" ordering reliable.
Future<bool> showConfirmToggleActiveDialog({
  required BuildContext context,
  required String userName,
  required bool deactivating,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    // Explicit rather than implicit. The dialog lives on the root
    // navigator, above go_router's shell navigator — which is precisely
    // why the buttons must use the builder's context and not the caller's.
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (dialogContext) => ConfirmToggleActiveDialog(
      userName: userName,
      deactivating: deactivating,
    ),
  );
  return confirmed ?? false;
}
