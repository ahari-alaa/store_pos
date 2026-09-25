import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/providers.dart';
import '../../../../core/storage/token_storage.dart';
import '../../data/auth_api.dart';
import '../../domain/entities/app_user.dart';

enum AuthStatus {
  /// Still checking secure storage for an existing session.
  unknown,
  authenticating,
  authenticated,
  unauthenticated,
}

class AuthState {
  final AuthStatus status;
  final AppUser? user;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.errorMessage,
  });

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  static const initial = AuthState();
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _api;

  AuthNotifier(this._api) : super(AuthState.initial) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await TokenStorage.instance.readAccessToken();
    final userJson = await TokenStorage.instance.readUserJson();

    if (token == null || token.isEmpty || userJson == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    try {
      final user = AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      state = state.copyWith(status: AuthStatus.authenticated, user: user, clearError: true);
      // Validate the cached token/user against the server in the
      // background; if it's no longer valid, onUnauthorized (wired in
      // core/network/providers.dart) calls handleSessionExpired below.
      _refreshCurrentUser();
    } catch (_) {
      await TokenStorage.instance.clear();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> _refreshCurrentUser() async {
    try {
      final data = await _api.me();
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      state = state.copyWith(user: user);
    } catch (_) {
      // A network hiccup shouldn't log the cashier out; a genuine 401 is
      // already handled by the ApiClient's onUnauthorized callback.
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.authenticating, clearError: true);
    try {
      final data = await _api.login(email: email.trim(), password: password);
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String;

      await TokenStorage.instance.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userJson: jsonEncode(user.toJson()),
      );

      state = state.copyWith(status: AuthStatus.authenticated, user: user, clearError: true);
      return true;
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.unauthenticated, errorMessage: e.message);
      return false;
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Something went wrong. Please try again.',
      );
      return false;
    }
  }

  /// Cashier PIN login — the POS app's login screen (see [LoginPage])
  /// only ever calls this, never [login]. Same session handling as
  /// [login]; the only difference is the API call and how a rejected
  /// attempt is worded (a PIN attempt should never suggest whether the
  /// PIN belongs to anyone, so the message comes straight from the
  /// backend's generic 'Incorrect PIN' / 'This account is inactive').
  Future<bool> loginWithPin(String pin) async {
    state = state.copyWith(status: AuthStatus.authenticating, clearError: true);
    try {
      final data = await _api.loginPin(pin: pin);
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final accessToken = data['access_token'] as String;
      final refreshToken = data['refresh_token'] as String;

      await TokenStorage.instance.saveSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userJson: jsonEncode(user.toJson()),
      );

      state = state.copyWith(status: AuthStatus.authenticated, user: user, clearError: true);
      return true;
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.unauthenticated, errorMessage: e.message);
      return false;
    } catch (_) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        errorMessage: 'Unable to connect to the server. Please try again.',
      );
      return false;
    }
  }

  /// Dismisses a stale login error (e.g. "Incorrect PIN") the moment the
  /// cashier starts entering a new PIN, so the banner doesn't sit on
  /// screen through their next attempt. No-op once a login is already in
  /// flight or has succeeded.
  void clearError() {
    if (state.errorMessage == null) return;
    if (state.status == AuthStatus.authenticating) return;
    state = state.copyWith(clearError: true);
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } catch (_) {
      // Best-effort — the token is deleted locally regardless, and the
      // server side of logout is stateless anyway (see authController.js).
    }
    await TokenStorage.instance.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Called by the [ApiClient] when a request comes back 401 with an
  /// auth-related code (expired/invalid token, deactivated user, ...).
  Future<void> handleSessionExpired() async {
    if (state.status != AuthStatus.authenticated) return;
    await TokenStorage.instance.clear();
    state = const AuthState(
      status: AuthStatus.unauthenticated,
      errorMessage: 'Your session has expired. Please log in again.',
    );
  }
}

final Provider<AuthApi> authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));

final StateNotifierProvider<AuthNotifier, AuthState> authProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authApiProvider));
});
