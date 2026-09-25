import 'package:flutter_test/flutter_test.dart';
import 'package:store_pos/core/network/api_exception.dart';
import 'package:store_pos/features/dashboard/presentation/widgets/dashboard_error_view.dart';

/// These lock in the behaviour that the old dashboard lacked: a failure
/// must be classified, not flattened into one sentence.
///
/// The regression being guarded against is subtle — every section used
/// `error: (_, __)`, so a dead server, a 403 and a 500 were visually
/// identical. If someone reintroduces a catch-all here, these fail.
void main() {
  // Identity translator: these tests assert on WHICH key is chosen, not
  // on the French/Arabic wording, so the key itself is the expectation.
  String t(String key) => key;

  group('DashboardErrorInfo.from', () {
    test('a connection failure names the URL that was actually tried', () {
      final info = DashboardErrorInfo.from(
        const ApiException(code: 'NETWORK_ERROR', message: 'unreachable'),
        t,
      );

      expect(info.title, 'dashboard.error_unreachable');
      // The URL is the whole point — without it "server unreachable" is
      // just as undiagnosable as the old generic message.
      expect(info.detail, contains('http'));
      expect(info.needsOperatorAction, isTrue);
    });

    test('401 is reported as an expired session, not a network problem', () {
      final info = DashboardErrorInfo.from(
        const ApiException(statusCode: 401, code: 'TOKEN_EXPIRED', message: 'jwt expired'),
        t,
      );

      expect(info.title, 'dashboard.error_session');
    });

    test('403 is reported as a permission problem and keeps the server message', () {
      final info = DashboardErrorInfo.from(
        const ApiException(
          statusCode: 403,
          code: 'PERMISSION_DENIED',
          message: "Missing permission 'reports.view' for role 'cashier'",
        ),
        t,
      );

      expect(info.title, 'dashboard.error_forbidden');
      expect(info.detail, contains('reports.view'));
    });

    test('a 500 surfaces the backend message verbatim plus code and status', () {
      final info = DashboardErrorInfo.from(
        const ApiException(
          statusCode: 500,
          code: 'DB_ERROR',
          message: 'Unknown column x in field list',
        ),
        t,
      );

      // The backend already wrote a readable sentence; replacing it with
      // our own vaguer one is what caused this bug to hide for so long.
      expect(info.title, 'Unknown column x in field list');
      expect(info.detail, contains('DB_ERROR'));
      expect(info.detail, contains('500'));
      expect(info.needsOperatorAction, isTrue);
    });

    test('a 404 is surfaced but not treated as needing operator action', () {
      final info = DashboardErrorInfo.from(
        const ApiException(statusCode: 404, code: 'NOT_FOUND', message: 'Route not found'),
        t,
      );

      expect(info.title, 'Route not found');
      expect(info.needsOperatorAction, isFalse);
    });

    test('a non-ApiException is reported as unexpected, not as a network error', () {
      final info = DashboardErrorInfo.from(
        StateError('Null check operator used on a null value'),
        t,
      );

      expect(info.title, 'dashboard.error_unexpected');
      // Must not masquerade as connectivity — that misdirects debugging.
      expect(info.title, isNot('dashboard.error_unreachable'));
    });

    test('a null error still classifies rather than throwing', () {
      expect(DashboardErrorInfo.from(null, t).title, 'dashboard.error_unexpected');
    });
  });
}
