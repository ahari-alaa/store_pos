import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/core/router/nav_access.dart';
import 'package:store_pos/core/widgets/app_sidebar.dart';
import 'package:store_pos/features/auth/domain/entities/app_user.dart';

AppUser _user(String role) => AppUser(
      id: 'u-$role',
      storeId: 's-1',
      name: role,
      email: '$role@x.test',
      role: role,
      isActive: true,
    );

List<String> _sidebarFor(AppUser? user) => kSidebarDestinations
    .where((d) => d.visibleFor == null || d.visibleFor!(user))
    .map((d) => d.path)
    .toList();

void main() {
  final cashier = _user('cashier');
  final manager = _user('manager');
  final admin = _user('admin');

  group('sidebar', () {
    test('a cashier sees ONLY Caisse, Ventes and Rapport', () {
      expect(_sidebarFor(cashier), ['/pos', '/sales', '/rapport']);
    });

    test('the cashier sidebar has none of the management modules', () {
      final paths = _sidebarFor(cashier);
      for (final hidden in [
        '/dashboard',
        '/products',
        '/expenses',
        '/stocks',
        '/suppliers',
        '/clients',
        '/reports',
        '/cashiers',
        '/settings',
      ]) {
        expect(paths, isNot(contains(hidden)), reason: '$hidden must be hidden from a cashier');
      }
    });

    test('admin and manager keep every management module and do NOT get the cashier Rapport', () {
      for (final user in [admin, manager]) {
        final paths = _sidebarFor(user);
        expect(paths, containsAll(['/dashboard', '/pos', '/sales', '/products', '/expenses', '/reports', '/cashiers', '/settings']));
        expect(paths, isNot(contains('/rapport')));
      }
    });

    test('the personal Rapport has its own label key (not the admin "Rapports")', () {
      final rapport = kSidebarDestinations.firstWhere((d) => d.path == '/rapport');
      final reports = kSidebarDestinations.firstWhere((d) => d.path == '/reports');
      expect(rapport.labelKey, 'nav.my_report');
      expect(reports.labelKey, 'nav.reports');
    });
  });

  group('router guard (canAccessRoute)', () {
    test('a cashier can open Caisse, Ventes, Rapport and the receipt preview', () {
      for (final path in ['/pos', '/sales', '/rapport', '/receipt-preview']) {
        expect(canAccessRoute(cashier, path), isTrue, reason: path);
      }
    });

    test('a cashier is refused everything else, including sub-routes and deep links', () {
      for (final path in [
        '/dashboard',
        '/products',
        '/stocks',
        '/suppliers',
        '/expenses',
        '/clients',
        '/reports',
        '/reports/cashiers/abc',
        '/cashiers',
        '/cashiers/abc',
        '/settings',
        '/something-unknown',
        '/rapportage', // must not be matched by a plain prefix test
      ]) {
        expect(canAccessRoute(cashier, path), isFalse, reason: path);
      }
    });

    test('admin/manager keep access to their modules but not to /rapport', () {
      for (final user in [admin, manager]) {
        for (final path in ['/dashboard', '/pos', '/sales', '/reports', '/reports/cashiers/abc', '/cashiers', '/settings']) {
          expect(canAccessRoute(user, path), isTrue, reason: path);
        }
        expect(canAccessRoute(user, '/rapport'), isFalse);
      }
    });

    test('no user: the auth redirect decides, not this guard', () {
      expect(canAccessRoute(null, '/anything'), isTrue);
    });
  });

  group('homeRouteFor', () {
    test('cashier lands on the Caisse, admin/manager on the dashboard', () {
      expect(homeRouteFor(cashier), '/pos');
      expect(homeRouteFor(admin), '/dashboard');
      expect(homeRouteFor(manager), '/dashboard');
      expect(homeRouteFor(null), '/dashboard');
    });
  });

  test('AppUser.isCashier', () {
    expect(cashier.isCashier, isTrue);
    expect(admin.isCashier, isFalse);
    expect(manager.isCashier, isFalse);
  });
}
