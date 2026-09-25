import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the current session (JWT access/refresh tokens + a cached copy
/// of the logged-in user) in the platform keychain/keystore, so the
/// cashier doesn't have to log in again every time the app restarts.
class TokenStorage {
  TokenStorage._();
  static final TokenStorage instance = TokenStorage._();

  final _storage = const FlutterSecureStorage();

  static const _accessTokenKey = 'store_pos_access_token';
  static const _refreshTokenKey = 'store_pos_refresh_token';
  static const _userKey = 'store_pos_user';

  // In-memory cache of the current session. Reads are served from here
  // whenever possible instead of round-tripping through the platform
  // secure-storage plugin on every single API call.
  //
  // This matters in practice: some flutter_secure_storage platform
  // backends (notably flutter_secure_storage_windows, which persists to an
  // encrypted file rather than the OS keychain) have shown a gap where a
  // write reports success but a read immediately afterward returns null.
  // Serving from memory means a session set during this run is never lost
  // to that gap; secure storage is still used so the session survives an
  // app restart, and `_restoreSession()`/`_refreshCurrentUser()` in
  // AuthNotifier independently validate a restored token against
  // `/auth/me` before trusting it.
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  String? _cachedUserJson;

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userJson,
  }) async {
    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;
    _cachedUserJson = userJson;
    // The in-memory cache above is already set, so the current session
    // works regardless of what happens below. On Flutter web specifically,
    // flutter_secure_storage encrypts via the browser's Web Crypto API,
    // which browsers only expose in a secure context (HTTPS, or
    // http://localhost) — accessing the app over a plain-HTTP LAN address
    // (e.g. http://192.168.x.x:8080) is NOT a secure context, so this
    // write throws. Without this try/catch, that exception propagated out
    // of a *successful* login and was shown to the cashier as "Unable to
    // connect to the server" even though the server had just authenticated
    // them. Swallow it here: the only real cost is the session not
    // surviving a page reload, which is a reasonable degrade for an
    // insecure-context deployment, not a reason to fail the login itself.
    try {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
        _storage.write(key: _userKey, value: userJson),
      ]);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TokenStorage] Persisting session failed (session is '
            'still active in memory for this run): $e');
      }
    }
  }

  Future<String?> readAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;
    final value = await _storage.read(key: _accessTokenKey);
    _cachedAccessToken = value;
    return value;
  }

  Future<String?> readRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;
    final value = await _storage.read(key: _refreshTokenKey);
    _cachedRefreshToken = value;
    return value;
  }

  Future<String?> readUserJson() async {
    if (_cachedUserJson != null) return _cachedUserJson;
    final value = await _storage.read(key: _userKey);
    _cachedUserJson = value;
    return value;
  }

  Future<void> clear() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _cachedUserJson = null;
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _userKey),
    ]);
  }
}