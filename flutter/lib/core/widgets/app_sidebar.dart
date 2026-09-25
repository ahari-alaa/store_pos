import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/app_user.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../design/design_system.dart';
import '../l10n/locale_provider.dart';

/// A logical grouping of navigation destinations.
///
/// Nine flat rows read as an undifferentiated list; the same nine split
/// into "what you watch / what you sell / what you administer" is
/// scannable at a glance, which is the whole job of a sidebar in software
/// someone uses for eight hours a day.
enum NavSection { main, catalog, admin }

class SidebarDestination {
  final String path;
  final String label;
  // Translation key used by the migrated (Consumer-based) sidebar; falls
  // back to [label] wherever a screen hasn't been localized yet (see
  // AppShell, which still uses [label] directly for page titles).
  final String labelKey;
  final IconData icon;

  /// Icon shown when this destination is the active one. Material's
  /// outlined/filled pairs are used consistently across the rail: outline
  /// for resting, filled for selected. Mixing the two arbitrarily (which
  /// the previous version did — `home_rounded` filled next to
  /// `inventory_2_outlined`) is what made the icon set look borrowed from
  /// three different products.
  final IconData selectedIcon;

  final NavSection section;

  /// Whether this destination should show for [user]. `null` (the
  /// default) means "always visible" — most modules gate their own
  /// content per-role internally (see RestrictedPage usage in
  /// ExpensesPage/ProductsPage/CashiersPage) rather than hiding the
  /// sidebar link entirely. Dashboard/Reports are the exception: every
  /// endpoint they call is admin/manager-only server-side (`reports.view`
  /// — see authorize.js), so a cashier tapping them would only ever see
  /// a dead end, and the link is hidden instead.
  final bool Function(AppUser? user)? visibleFor;

  const SidebarDestination({
    required this.path,
    required this.label,
    required this.labelKey,
    required this.icon,
    required this.selectedIcon,
    required this.section,
    this.visibleFor,
  });
}

bool _requiresReportsView(AppUser? user) => user == null || user.canViewReports;

/// Everything that is not Caisse / Ventes / the cashier's own Rapport is a
/// management module: a cashier does not see it (and the router guard +
/// backend refuse it too — see nav_access.dart).
bool _notForCashier(AppUser? user) => user == null || !user.isCashier;

/// The cashier's personal report.
bool _cashierOnly(AppUser? user) => user != null && user.isCashier;

/// "Paiements caissiers" (spec §22-§23) — mirrors the backend's
/// 'cashier_settlements.view' permission (admin + manager only).
bool _canManageCashierSettlements(AppUser? user) => user == null || user.canManageCashierSettlements;

/// Sidebar destinations mirror the modules from the project spec.
/// Paths and visibility rules are unchanged from before the redesign —
/// only grouping and the selected-state icons are new.
const List<SidebarDestination> kSidebarDestinations = [
  SidebarDestination(
    path: '/dashboard',
    label: 'Accueil',
    labelKey: 'nav.dashboard',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
    section: NavSection.main,
    visibleFor: _requiresReportsView,
  ),
  SidebarDestination(
    path: '/pos',
    label: 'Caisse',
    labelKey: 'nav.pos',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale_rounded,
    section: NavSection.main,
  ),
  SidebarDestination(
    path: '/sales',
    label: 'Ventes',
    labelKey: 'nav.sales',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
    section: NavSection.main,
  ),
  SidebarDestination(
    path: '/rapport',
    label: 'Rapport',
    labelKey: 'nav.my_report',
    icon: Icons.assessment_outlined,
    selectedIcon: Icons.assessment_rounded,
    section: NavSection.main,
    visibleFor: _cashierOnly,
  ),
  SidebarDestination(
    path: '/products',
    label: 'Produits',
    labelKey: 'nav.products',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
    section: NavSection.catalog,
    visibleFor: _notForCashier,
  ),
  SidebarDestination(
    path: '/expenses',
    label: 'Stocks & Dépenses',
    labelKey: 'nav.expenses',
    icon: Icons.inventory_outlined,
    selectedIcon: Icons.inventory_rounded,
    section: NavSection.catalog,
    visibleFor: _notForCashier,
  ),
  SidebarDestination(
    path: '/clients',
    label: 'Clients',
    labelKey: 'nav.clients',
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt_rounded,
    section: NavSection.catalog,
    visibleFor: _notForCashier,
  ),
  SidebarDestination(
    path: '/reports',
    label: 'Rapports',
    labelKey: 'nav.reports',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart_rounded,
    section: NavSection.admin,
    visibleFor: _requiresReportsView,
  ),
  SidebarDestination(
    path: '/cashier-settlements',
    label: 'Paiements caissiers',
    labelKey: 'nav.cashier_settlements',
    icon: Icons.payments_outlined,
    selectedIcon: Icons.payments_rounded,
    section: NavSection.admin,
    visibleFor: _canManageCashierSettlements,
  ),
  SidebarDestination(
    path: '/cashiers',
    label: 'Utilisateurs',
    labelKey: 'nav.cashiers',
    icon: Icons.badge_outlined,
    selectedIcon: Icons.badge_rounded,
    section: NavSection.admin,
    visibleFor: _notForCashier,
  ),
  SidebarDestination(
    path: '/settings',
    label: 'Paramètres',
    labelKey: 'nav.settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    section: NavSection.admin,
    visibleFor: _notForCashier,
  ),
];

const Map<NavSection, String> _kSectionLabelKeys = {
  NavSection.main: 'nav.section_main',
  NavSection.catalog: 'nav.section_catalog',
  NavSection.admin: 'nav.section_admin',
};

/// Persistent navigation rail.
///
/// Collapses to an icon-only rail below [AppSizes.sidebarCollapseBreakpoint]
/// so a half-width window on a 1366px laptop still gets a usable content
/// area instead of the 248px rail eating a fifth of it. Collapsing is
/// automatic *and* manually overridable — a cashier on a small screen who
/// wants labels can pin them open, and the choice survives navigation
/// because the rail lives in the router's ShellRoute.
class AppSidebar extends ConsumerStatefulWidget {
  final String currentPath;

  const AppSidebar({super.key, required this.currentPath});

  @override
  ConsumerState<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends ConsumerState<AppSidebar> {
  /// `null` = follow the window width. Set by the collapse toggle.
  bool? _manualCollapsed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = ref.watch(authProvider).user;

    final autoCollapsed = MediaQuery.sizeOf(context).width <
        AppSizes.sidebarCollapseBreakpoint;
    final collapsed = _manualCollapsed ?? autoCollapsed;

    final destinations = kSidebarDestinations
        .where((d) => d.visibleFor == null || d.visibleFor!(user))
        .toList();

    return AnimatedContainer(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      width: collapsed
          ? AppSizes.sidebarCollapsedWidth
          : AppSizes.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(collapsed: collapsed),
          Expanded(
            child: _NavList(
              destinations: destinations,
              currentPath: widget.currentPath,
              collapsed: collapsed,
            ),
          ),
          Divider(height: 1, thickness: 1, color: colors.border),
          _CollapseToggle(
            collapsed: collapsed,
            onToggle: () => setState(() => _manualCollapsed = !collapsed),
          ),
        ],
      ),
    );
  }
}

class _NavList extends ConsumerWidget {
  final List<SidebarDestination> destinations;
  final String currentPath;
  final bool collapsed;

  const _NavList({
    required this.destinations,
    required this.currentPath,
    required this.collapsed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build a flat list of rows with section headings interleaved, so the
    // whole thing stays a single scrollable and never overflows on a
    // short window.
    final children = <Widget>[];
    NavSection? lastSection;

    for (final destination in destinations) {
      if (destination.section != lastSection) {
        lastSection = destination.section;
        children.add(
          _SectionHeading(
            label: tr(ref, _kSectionLabelKeys[destination.section]!),
            collapsed: collapsed,
            isFirst: children.isEmpty,
          ),
        );
      }
      children.add(
        _SidebarTile(
          destination: destination,
          // `startsWith` alone would light up "/sales" for a route like
          // "/sales-report"; comparing the next character keeps the
          // active state honest for sub-routes such as /products/42.
          selected: _isActive(currentPath, destination.path),
          collapsed: collapsed,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      children: children,
    );
  }

  static bool _isActive(String current, String path) {
    if (current == path) return true;
    return current.startsWith('$path/');
  }
}

class _SidebarHeader extends ConsumerWidget {
  final bool collapsed;

  const _SidebarHeader({required this.collapsed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;

    final mark = Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: AppRadius.smAll,
      ),
      child: Icon(
        Icons.storefront_rounded,
        color: colors.onPrimary,
        size: AppSizes.iconMd,
      ),
    );

    return Container(
      height: AppSizes.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          mark,
          if (!collapsed) ...[
            const SizedBox(width: AppSpacing.md),
            // Expanded + ellipsis: the store name is user-configurable in
            // Settings, so it must degrade instead of overflowing the
            // fixed-width rail.
            Expanded(
              child: Text(
                tr(ref, 'app.name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.cardTitle.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String label;
  final bool collapsed;
  final bool isFirst;

  const _SectionHeading({
    required this.label,
    required this.collapsed,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Collapsed: a heading would be unreadable at 72px, so the group is
    // signalled by a hairline rule instead of truncated text.
    if (collapsed) {
      if (isFirst) return const SizedBox(height: AppSpacing.sm);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Divider(height: 1, thickness: 1, color: colors.border),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        isFirst ? AppSpacing.md : AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

class _SidebarTile extends ConsumerStatefulWidget {
  final SidebarDestination destination;
  final bool selected;
  final bool collapsed;

  const _SidebarTile({
    required this.destination,
    required this.selected,
    required this.collapsed,
  });

  @override
  ConsumerState<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends ConsumerState<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;
    final label = tr(ref, widget.destination.labelKey);

    final foreground = selected
        ? colors.primary
        : (_hovered ? colors.textPrimary : colors.textSecondary);

    final background = selected
        ? colors.primarySurface
        : (_hovered ? colors.surfaceHover : Colors.transparent);

    final row = Row(
      mainAxisAlignment: widget.collapsed
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(
          selected
              ? widget.destination.selectedIcon
              : widget.destination.icon,
          size: AppSizes.iconMd,
          color: foreground,
        ),
        if (!widget.collapsed) ...[
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              // "Stocks & Dépenses" is already near the rail's width in
              // Arabic; ellipsis rather than overflow, with the tooltip
              // below carrying the full string.
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.primary : colors.textPrimary,
              ),
            ),
          ),
        ],
      ],
    );

    Widget tile = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Stack(
        children: [
          Material(
            color: background,
            borderRadius: AppRadius.smAll,
            child: InkWell(
              borderRadius: AppRadius.smAll,
              onTap: () => context.go(widget.destination.path),
              onHover: (value) => setState(() => _hovered = value),
              child: Container(
                height: 42,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.collapsed ? 0 : AppSpacing.md,
                ),
                alignment: Alignment.center,
                child: row,
              ),
            ),
          ),
          // Active marker: a 3px bar on the leading edge. Positioned so it
          // is mirrored automatically under an RTL Directionality (Arabic).
          if (selected)
            PositionedDirectional(
              start: 0,
              top: 9,
              bottom: 9,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );

    // A collapsed rail is only usable with tooltips; an expanded one
    // already shows the label in full, so it doesn't need one.
    //
    // IMPORTANT: this tile's own hover feedback (`_hovered` above) is
    // driven by InkWell's `onHover`, which fires on every enter/exit as
    // the mouse travels down the rail. Wrapping the *whole* tile in
    // `Tooltip` unconditionally used to stack Tooltip's own hover-driven
    // MouseRegion (which inserts/removes an OverlayEntry) on top of that
    // same hover surface. Flutter's MouseTracker isn't reentrant-safe
    // against a widget subtree changing (the tooltip's OverlayEntry)
    // while it's still mid-way through processing that same batch of
    // hover events — fast mouse movement down the rail could throw
    // `'!_debugDuringDeviceUpdate': is not true` and eventually hang the
    // app. Only adding Tooltip in the one state that actually needs it
    // (collapsed) keeps the expanded rail — the one you hover across
    // constantly while navigating — down to a single hover listener.
    return widget.collapsed
        ? Tooltip(
            message: label,
            waitDuration: const Duration(milliseconds: 500),
            preferBelow: false,
            child: tile,
          )
        : tile;
  }
}

class _CollapseToggle extends ConsumerWidget {
  final bool collapsed;
  final VoidCallback onToggle;

  const _CollapseToggle({required this.collapsed, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final label = tr(ref, collapsed ? 'nav.expand' : 'nav.collapse');

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.smAll,
          child: InkWell(
            borderRadius: AppRadius.smAll,
            onTap: onToggle,
            child: Container(
              height: AppSizes.buttonHeightSm,
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : AppSpacing.md,
              ),
              alignment:
                  collapsed ? Alignment.center : AlignmentDirectional.centerStart,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    collapsed
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    size: AppSizes.iconMd,
                    color: colors.textMuted,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
