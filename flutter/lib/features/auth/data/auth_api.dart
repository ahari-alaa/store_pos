import '../../../core/network/api_client.dart';

/// Thin wrapper around the `/api/auth/*` endpoints
/// (see store_pos_backend/src/routes/authRoutes.js).
class AuthApi {
  final ApiClient _client;

  const AuthApi(this._client);

  /// Returns `{ user, access_token, refresh_token, expires_in }`.
  Future<Map<String, dynamic>> login({required String email, required String password}) {
    return _client.post('/auth/login', body: {'email': email, 'password': password});
  }

  /// Cashier PIN login (see store_pos_backend/src/services/authService.js
  /// #loginWithPin). Only the PIN is sent — the backend resolves which
  /// user it belongs to. Returns the same shape as [login].
  Future<Map<String, dynamic>> loginPin({required String pin}) {
    return _client.post('/auth/login-pin', body: {'pin': pin});
  }

  /// Returns `{ user }` for whoever the current access token belongs to.
  Future<Map<String, dynamic>> me() {
    return _client.get('/auth/me');
  }

  /// Stateless on the server (see authController.js) — mainly here so the
  /// client always has a single, consistent place to call on sign-out.
  Future<void> logout() async {
    await _client.post('/auth/logout');
  }

  /// Admin-only: create a new cashier/manager/admin account for the
  /// signed-in admin's store. Returns `{ user }`.
  Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) {
    return _client.post('/auth/users', body: {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
    });
  }

  /// Admin-only: list cashiers/managers/admins for the Cashiers screen.
  Future<Map<String, dynamic>> listUsers() {
    return _client.get('/auth/users', query: {'page_size': 200});
  }

  /// Admin-only: edit a cashier's name/email/role/active state, or reset
  /// their password (only the fields present in `input` are changed —
  /// see authValidators.js#updateUser).
  ///
  /// [isCurrentUser] must be true only when [id] is the signed-in admin's
  /// own id (e.g. editing their own profile). Every request already
  /// carries the admin's own token no matter whose account is being
  /// edited, so a 401 here is only ever real evidence of a dead session
  /// when the admin is editing themselves — a 401 while editing a
  /// DIFFERENT account must never log the admin out (see ApiClient.put).
  Future<Map<String, dynamic>> updateUser(
    String id,
    Map<String, dynamic> input, {
    bool isCurrentUser = false,
  }) {
    return _client.put(
      '/auth/users/$id',
      body: input,
      suppressUnauthorized: !isCurrentUser,
    );
  }

  /// Admin-only: assign/change a staff member's PIN (Users → [name] →
  /// Change PIN). [isCurrentUser] follows the same rule as [updateUser]'s
  /// — true only when [id] is the signed-in admin's own account, so a
  /// failure here while changing someone ELSE's PIN can never be mistaken
  /// for the admin's own session expiring.
  Future<Map<String, dynamic>> setPin(
    String id,
    String pin, {
    bool isCurrentUser = false,
  }) {
    return _client.put(
      '/auth/users/$id/pin',
      body: {'pin': pin},
      suppressUnauthorized: !isCurrentUser,
    );
  }
}
