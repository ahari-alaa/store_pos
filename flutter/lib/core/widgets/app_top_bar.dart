import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../features/auth/presentation/providers/auth_provider.dart';
import '../design/design_system.dart';
import '../l10n/locale_provider.dart';
import '../network/connection_status.dart';
import 'ui/app_dialog.dart';

/// Top bar shown above the routed page content.
///
/// Three things are new relative to the pre-redesign version, all of them
/// correctness rather than decoration:
///
///  * **The user badge is now a real menu.** Before, logout existed only
///    inside the POS screen's own header popup — a manager sitting on
///    Produits or Paramètres had no way to end their session without
///    navigating to the till first. The badge is now a focusable,
///    keyboard-reachable menu with Paramètres and Se déconnecter.
///  * **The connection chip reports reality.** It is driven by
///    [connectionStatusProvider], which is fed by the outcome of the
///    requests the app actually makes (see api_client.dart), so it shows
///    nothing until a request has completed rather than claiming a
///    connection it has not verified.
///  * **Nothing here can overflow.** Title, subtitle and user name are
///    all constrained and ellipsised; the whole trailing cluster drops to
///    icon-only below a narrow breakpoint instead of pushing the title
///    off-screen.
class AppTopBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;

  /// Page-specific controls (a search field, a primary action) rendered
  /// between the title and the status cluster.
  final Widget? trailing;
  final VoidCallback? onBack;

  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(AppSizes.topBarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;

    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Below this, the user's name and role are dropped and only the
          // avatar remains. Hiding a label is acceptable here because the
          // menu behind it still carries the full identity; hiding an
          // *action* would not be.
          final compact = constraints.maxWidth < 760;

          return Row(
            children: [
              if (onBack != null) ...[
                _TopBarIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: tr(ref, 'common.back'),
                  onPressed: onBack,
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              // Flexible, not Expanded: when a page supplies a wide
              // trailing widget (the POS search field), the title yields
              // space instead of forcing a horizontal overflow.
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.pageTitle,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.pageSubtitle,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              if (trailing != null) ...[
                Flexible(child: trailing!),
                const SizedBox(width: AppSpacing.lg),
              ],
              const ConnectionStatusChip(),
              const SizedBox(width: AppSpacing.md),
              Container(
                width: 1,
                height: 28,
                color: colors.border,
              ),
              const SizedBox(width: AppSpacing.md),
              UserMenuButton(compact: compact),
            ],
          );
        },
      ),
    );
  }
}

/// Square, themed icon button used by the top bar chrome.
class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _TopBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.smAll,
        child: InkWell(
          borderRadius: AppRadius.smAll,
          onTap: onPressed,
          child: SizedBox(
            width: AppSizes.iconButtonSize,
            height: AppSizes.iconButtonSize,
            child: Icon(icon, size: AppSizes.iconMd, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// Server-reachability indicator.
///
/// Deliberately reports *reachability only*. This client has no local
/// write queue, so a "✓ Synchronisé" or a pending-items count would be
/// fabricated — and a fabricated sync badge is worse than none, because
/// it tells a cashier a sale is safely queued when it is not. See the
/// long note in connection_status.dart.
class ConnectionStatusChip extends ConsumerWidget {
  const ConnectionStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final status = ref.watch(connectionStatusProvider);

    final (Color accent, String labelKey, String detailKey) = switch (status) {
      ConnectionStatus.online => (
          colors.success,
          'connection.online',
          'connection.online_detail',
        ),
      ConnectionStatus.offline => (
          colors.danger,
          'connection.offline',
          'connection.offline_detail',
        ),
      ConnectionStatus.unknown => (
          colors.textMuted,
          'connection.checking',
          'connection.checking_detail',
        ),
    };

    final lastContact =
        ref.read(connectionStatusProvider.notifier).lastContact;
    final tooltip = StringBuffer(tr(ref, detailKey));
    if (lastContact != null) {
      tooltip
        ..write('\n')
        ..write(tr(ref, 'connection.last_contact'))
        ..write(' : ')
        ..write(DateFormat('HH:mm:ss').format(lastContact));
    }

    return Tooltip(
      message: tooltip.toString(),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: AppRadius.xsAll,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              tr(ref, labelKey),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar + name + role, opening the account menu.
class UserMenuButton extends ConsumerWidget {
  final bool compact;

  const UserMenuButton({super.key, this.compact = false});

  static String roleLabelKey(String role) {
    switch (role) {
      case 'admin':
        return 'role.admin';
      case 'manager':
        return 'role.manager';
      default:
        return 'role.cashier';
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: trRead(ref, 'user.logout_confirm_title'),
      message: trRead(ref, 'user.logout_confirm_body'),
      confirmLabel: trRead(ref, 'user.logout'),
      cancelLabel: trRead(ref, 'common.cancel'),
      destructive: true,
      icon: Icons.logout_rounded,
    );
    if (!confirmed) return;
    await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final user = ref.watch(authProvider).user;
    final name = (user?.name.trim().isNotEmpty ?? false) ? user!.name : '—';
    final roleLabel = user == null ? '' : tr(ref, roleLabelKey(user.role));
    final initial = name == '—' ? '?' : name.characters.first.toUpperCase();

    final avatar = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primarySurface,
        shape: BoxShape.circle,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: colors.primary,
        ),
      ),
    );

    return PopupMenuButton<String>(
      tooltip: tr(ref, 'user.menu'),
      offset: const Offset(0, AppSizes.iconButtonSize),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.smAll,
        side: BorderSide(color: colors.border),
      ),
      color: colors.surface,
      onSelected: (value) {
        switch (value) {
          case 'settings':
            context.go('/settings');
            break;
          case 'logout':
            _confirmLogout(context, ref);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'settings',
          height: 44,
          child: _MenuRow(
            icon: Icons.settings_outlined,
            label: tr(ref, 'user.settings'),
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'logout',
          height: 44,
          child: _MenuRow(
            icon: Icons.logout_rounded,
            label: tr(ref, 'user.logout'),
            destructive: true,
          ),
        ),
      ],
      child: Container(
        height: AppSizes.iconButtonSize,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            avatar,
            if (!compact) ...[
              const SizedBox(width: AppSpacing.md),
              // Bounded: a long cashier name must ellipsise, not push the
              // chevron out of the bar.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.25,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (roleLabel.isNotEmpty)
                      Text(
                        roleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.expand_more_rounded,
              size: AppSizes.iconSm,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = destructive ? colors.danger : colors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconSm, color: color),
        const SizedBox(width: AppSpacing.md),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
