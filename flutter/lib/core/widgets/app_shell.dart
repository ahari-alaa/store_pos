import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/design_system.dart';
import '../l10n/locale_provider.dart';
import 'app_sidebar.dart';
import 'app_top_bar.dart';

/// Resolved chrome for the current route: what the top bar should say and
/// whether it should offer a back affordance.
class _ShellChrome {
  final String title;
  final String? subtitle;
  final bool showBack;

  const _ShellChrome(this.title, {this.subtitle, this.showBack = false});
}

/// Persistent frame (sidebar + top bar) wrapping every routed page.
/// Used as the `builder` of a go_router `ShellRoute` so navigating between
/// sections never rebuilds the sidebar itself.
class AppShell extends ConsumerWidget {
  final String currentPath;
  final Widget child;

  const AppShell({
    super.key,
    required this.currentPath,
    required this.child,
  });

  /// Maps a route to its top-bar chrome.
  ///
  /// This used to be a `kSidebarDestinations.firstWhere(startsWith)` with
  /// `orElse: first`, which silently mislabelled every route that has no
  /// sidebar entry of its own: `/suppliers` and `/cashiers/:id` both
  /// rendered under the title "Accueil". Sub-routes are now resolved
  /// explicitly, longest-prefix-first, and anything genuinely unknown
  /// falls back to the app name rather than to an unrelated module.
  _ShellChrome _chromeFor(WidgetRef ref, String path) {
    // Deepest paths first — '/cashiers/x' must not be caught by
    // '/cashiers'.
    if (path.startsWith('/cashiers/')) {
      return _ShellChrome(tr(ref, 'nav.cashiers'), showBack: true);
    }
    if (path.startsWith('/reports/cashiers/')) {
      return _ShellChrome(tr(ref, 'reports.cashier_detail'), showBack: true);
    }
    if (path.startsWith('/reports')) {
      return _ShellChrome(
        tr(ref, 'nav.reports'),
        subtitle: tr(ref, 'reports.subtitle'),
      );
    }
    if (path.startsWith('/stocks')) {
      return _ShellChrome(
        tr(ref, 'nav.stocks'),
        subtitle: "Catalogue d'ingrédients utilisé par vos recettes",
        showBack: true,
      );
    }
    if (path.startsWith('/suppliers')) {
      return const _ShellChrome('Fournisseurs', showBack: true);
    }
    if (path.startsWith('/cashier-settlements')) {
      return _ShellChrome(
        tr(ref, 'nav.cashier_settlements'),
        subtitle: tr(ref, 'admin_settlements.subtitle'),
      );
    }
    if (path.startsWith('/dashboard')) {
      return _ShellChrome(
        tr(ref, 'nav.dashboard'),
        subtitle: tr(ref, 'topbar.overview_subtitle'),
      );
    }

    for (final destination in kSidebarDestinations) {
      if (path == destination.path || path.startsWith('${destination.path}/')) {
        return _ShellChrome(tr(ref, destination.labelKey));
      }
    }
    return _ShellChrome(tr(ref, 'app.name'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    // The POS page owns its own top row (live search/scan field, matching
    // the reference design) instead of the generic title bar every other
    // module uses — so we skip the shared AppTopBar only for that route.
    final usesOwnHeader = currentPath.startsWith('/pos');
    final chrome = _chromeFor(ref, currentPath);

    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          AppSidebar(currentPath: currentPath),
          Expanded(
            child: Column(
              children: [
                if (!usesOwnHeader)
                  AppTopBar(
                    title: chrome.title,
                    subtitle: chrome.subtitle,
                    // Only offer "back" when there is somewhere to go
                    // back to. Calling context.pop() on a route reached
                    // directly (deep link, refresh) would otherwise throw.
                    onBack: chrome.showBack && context.canPop()
                        ? () => context.pop()
                        : null,
                  ),
                // ClipRect stops a page that briefly overshoots during a
                // window resize from painting over the top bar.
                Expanded(child: ClipRect(child: child)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
