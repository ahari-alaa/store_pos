import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/domain/entities/app_user.dart';
import '../../features/cashiers/presentation/pages/cashier_detail_page.dart';
import '../../features/cashiers/presentation/pages/cashiers_page.dart';
import '../../features/dashboard/domain/entities/dashboard_extras.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/expenses/presentation/pages/expenses_page.dart';
import '../../features/ingredients/presentation/pages/ingredients_page.dart';
import '../../features/pos/presentation/pages/pos_page.dart';
import '../../features/pos/presentation/providers/receipt_data.dart';
import '../../features/pos/presentation/widgets/receipt_preview_page.dart';
import '../../features/products/presentation/pages/products_page.dart';
import '../../features/reports/presentation/pages/cashier_report_page.dart';
import '../../features/reports/presentation/pages/report_cashier_detail_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/settlements/presentation/pages/admin_cashier_settlements_page.dart';
import '../../features/sales/presentation/pages/sales_entry_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/suppliers/presentation/pages/suppliers_page.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/coming_soon_page.dart';
import '../widgets/splash_page.dart';
import 'nav_access.dart';

/// App-wide router. Auth-gated: every route except `/login` and `/splash`
/// requires a signed-in session (see [_redirect] below).
///
/// Every module in [kSidebarDestinations] gets a real route so navigation
/// is honest (no dead sidebar links). POS, Products, Suppliers, Cashiers
/// and Settings render real functionality; everything else still renders
/// [ComingSoonPage] until its own phase lands.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _GoRouterRefreshNotifier(ref),
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      // Registered as a real go_router route (not pushed imperatively via
      // Navigator.push) so it's a route go_router actually knows about.
      // Mixing an imperative Navigator.push with go_router's own
      // declarative/ShellRoute navigator can corrupt the navigator stack
      // the moment go_router needs to redirect out from under it — e.g. a
      // cashier's session getting invalidated (account deactivated) while
      // this screen is open used to crash with "You have popped the last
      // page off of the stack" and a black screen. Routing through
      // go_router avoids that entirely: a redirect now just replaces this
      // page like any other.
      GoRoute(
        path: '/receipt-preview',
        builder: (context, state) => ReceiptPreviewPage(data: state.extra as ReceiptData),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AppShell(currentPath: state.matchedLocation, child: child);
        },
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/pos',
            builder: (context, state) => const PosPage(),
          ),
          GoRoute(
            path: '/stocks',
            builder: (context, state) => const IngredientsPage(),
          ),
          GoRoute(
            path: '/products',
            builder: (context, state) => const ProductsPage(),
          ),
          GoRoute(
            path: '/suppliers',
            builder: (context, state) => const SuppliersPage(),
          ),
          GoRoute(
            path: '/sales',
            // Cashier: own orders + serving state. Admin/manager: the
            // existing store-wide Ventes (see SalesEntryPage).
            builder: (context, state) => const SalesEntryPage(),
          ),
          GoRoute(
            // The cashier's PERSONAL report (not the admin Rapports above).
            path: '/rapport',
            builder: (context, state) => const CashierReportPage(),
          ),
          GoRoute(
            path: '/cashiers',
            builder: (context, state) => const CashiersPage(),
            routes: [
              // Cashier detail (spec: tap a staff member to see their info
              // + how many orders/how much they've sold on a given day).
              // `extra` carries the already-loaded AppUser from the list
              // (see CashiersPage._CashierTile) so opening this screen
              // doesn't need its own fetch; CashierDetailPage falls back
              // to looking the id up in cashiersProvider if `extra` is
              // missing (e.g. a refreshed/deep-linked route on web).
              GoRoute(
                path: ':id',
                builder: (context, state) => CashierDetailPage(
                  cashierId: state.pathParameters['id']!,
                  initialUser: state.extra as AppUser?,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/expenses',
            builder: (context, state) => const ExpensesPage(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsPage(),
            routes: [
              // Rapports cashier-detail drill-down (spec §11), reached by
              // tapping a row in CashierPerformanceSection. `extra`
              // carries the already-loaded CashierRankingEntry so the
              // header renders immediately while the full detail (with
              // day-by-day breakdown + payment split) is still loading —
              // same pattern as /cashiers/:id above.
              GoRoute(
                path: 'cashiers/:id',
                builder: (context, state) => ReportCashierDetailPage(
                  cashierId: state.pathParameters['id']!,
                  fallback: state.extra as CashierRankingEntry?,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/cashier-settlements',
            builder: (context, state) => const AdminCashierSettlementsPage(),
          ),
          ..._comingSoonRoutes,
        ],
      ),
    ],
  );
});

String? _redirect(Ref ref, GoRouterState state) {
  final auth = ref.read(authProvider);
  final isSplash = state.matchedLocation == '/splash';
  final isLoggingIn = state.matchedLocation == '/login';

  // Still checking secure storage for an existing session — stay on the
  // splash screen until that resolves, so we never flash the POS UI (or
  // the login form) before we actually know.
  if (auth.status == AuthStatus.unknown) {
    return isSplash ? null : '/splash';
  }

  if (!auth.isAuthenticated) {
    return isLoggingIn ? null : '/login';
  }

  // Signed in: bounce away from splash/login into the app. Every
  // /reports/* endpoint the dashboard calls is admin/manager-only (see
  // store_pos_backend/src/middleware/authorize.js's ROLE_PERMISSIONS —
  // the cashier role has no 'reports.view'), so a cashier — who, since
  // migrations/010_pin_authentication.sql, now signs in directly via a
  // PIN with no user picker — must never be routed to `/dashboard` by
  // default: every single fetch on that page would come back 403 and
  // show nothing but a load error. Send a cashier straight to the POS
  // screen instead; admin/manager keep landing on the dashboard as
  // before. This also guards a cashier session that somehow ends up on
  // `/dashboard` directly (e.g. a stale deep link) — DashboardPage
  // itself additionally shows a RestrictedPage as a defensive fallback.
  final user = auth.user;
  final canViewReports = user == null || user.canViewReports;
  if (isSplash || isLoggingIn) {
    return homeRouteFor(user);
  }
  if (state.matchedLocation == '/dashboard' && !canViewReports) {
    return '/pos';
  }
  // Role guard for EVERY route, not just the dashboard: a cashier may only
  // open Caisse / Ventes / Rapport (see nav_access.dart), and `/rapport` is
  // theirs alone. Hiding sidebar links is not access control, so a deep link
  // or a stale route is redirected here too. (The backend rejects the
  // matching API calls regardless.)
  if (!canAccessRoute(user, state.matchedLocation)) {
    return homeRouteFor(user);
  }
  return null;
}

/// Bridges Riverpod's [authProvider] to go_router's [Listenable]-based
/// `refreshListenable`, so a login/logout/session-expiry immediately
/// re-runs [_redirect] instead of waiting for the next navigation.
class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

/// Builds a `ComingSoonPage` route for every sidebar destination other than
/// POS, reusing its label/icon so the placeholder stays in sync with the
/// sidebar automatically.
const List<String> _implementedRoutes = [
  '/dashboard',
  '/pos',
  '/products',
  '/stocks',
  '/suppliers',
  '/sales',
  '/cashiers',
  '/settings',
  '/expenses',
  '/reports',
  '/rapport',
  '/cashier-settlements',
];

final List<GoRoute> _comingSoonRoutes = kSidebarDestinations
    .where((destination) => !_implementedRoutes.contains(destination.path))
    .map(
      (destination) => GoRoute(
        path: destination.path,
        builder: (context, state) => ComingSoonPage(
          title: destination.label,
          icon: destination.icon,
        ),
      ),
    )
    .toList();
