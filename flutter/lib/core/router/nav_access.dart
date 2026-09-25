import '../../features/auth/domain/entities/app_user.dart';

/// Which screens each role may open — the single source of truth for the
/// router guard and the sidebar.
///
/// A CASHIER gets exactly three destinations: Caisse (`/pos`), Ventes
/// (`/sales`) and their own Rapport (`/rapport`). `/receipt-preview` is the
/// full-screen receipt the Caisse opens after a sale, so it must stay
/// reachable, but it is not a destination.
///
/// This is only the UI half. The backend enforces the same limits on every
/// API (see backend/src/middleware/authorize.js and the route files), so
/// typing a URL or calling an endpoint by hand gets a cashier nowhere.
const List<String> kCashierRoutes = ['/pos', '/sales', '/rapport', '/receipt-preview'];

/// The one destination that belongs to the cashier only.
const String kCashierReportRoute = '/rapport';

bool _matches(String path, String route) => path == route || path.startsWith('$route/');

/// Whether [user] may open [path] (a matched location such as `/reports/x`).
/// A null user is not this function's concern — the auth redirect handles it.
bool canAccessRoute(AppUser? user, String path) {
  if (user == null) return true;
  if (user.isCashier) return kCashierRoutes.any((route) => _matches(path, route));
  // Admin / manager have the store-wide Rapports; `/rapport` is the
  // cashier's personal report and means nothing for them.
  return !_matches(path, kCashierReportRoute);
}

/// Where a signed-in [user] lands by default. A cashier can't use the
/// dashboard (every call it makes is admin/manager-only), so they go to the
/// Caisse.
String homeRouteFor(AppUser? user) {
  if (user == null) return '/dashboard';
  if (user.isCashier) return '/pos';
  return user.canViewReports ? '/dashboard' : '/pos';
}
