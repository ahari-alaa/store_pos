import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class CashiersNotifier extends StateNotifier<AsyncValue<List<AppUser>>> {
  final Ref _ref;

  CashiersNotifier(this._ref) : super(const AsyncValue.loading()) {
    refresh();
  }

  /// Refreshes the cashier list. Only shows the full loading spinner on
  /// the very first load — a refresh triggered after an update (e.g. right
  /// after deactivating a cashier) keeps the current list on screen while
  /// it re-fetches, instead of flashing the whole Cashiers screen back to
  /// a blank loading state.
  Future<void> refresh() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }
    try {
      final data = await _ref.read(authApiProvider).listUsers();
      final items = (data['items'] as List<dynamic>? ?? const [])
          .map((raw) => AppUser.fromJson(raw as Map<String, dynamic>))
          .toList();
      state = AsyncValue.data(items);
    } catch (error, stack) {
      // Keep the last good list attached to the new error state (via
      // copyWithPrevious) rather than discarding it — a transient refresh
      // failure should never blank out an already-loaded Cashiers screen.
      state = AsyncValue<List<AppUser>>.error(error, stack).copyWithPrevious(state);
    }
  }

  Future<void> createCashier({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    await _ref.read(authApiProvider).createUser(
          name: name,
          email: email,
          password: password,
          role: role,
        );
    await refresh();
  }

  /// [currentUserId] is the signed-in admin's own id — used only to tell
  /// [AuthApi.updateUser] whether this edit could plausibly be about the
  /// admin's own session, so an unrelated failure while editing a
  /// DIFFERENT cashier can never be mistaken for "my session expired"
  /// (see AuthApi.updateUser / ApiClient.put).
  Future<void> updateCashier(
    String id,
    Map<String, dynamic> input, {
    required String currentUserId,
  }) async {
    await _ref.read(authApiProvider).updateUser(
          id,
          input,
          isCurrentUser: id == currentUserId,
        );
    await refresh();
  }

  /// Admin-only: assign/change a staff member's PIN (Users → [name] →
  /// Change PIN). Doesn't need a [refresh] afterward — a PIN is never
  /// part of [AppUser]/the Cashiers list — but the call still needs to be
  /// funneled through here rather than straight from the UI so it stays
  /// alongside every other user-management action.
  Future<void> changePin(
    String id,
    String pin, {
    required String currentUserId,
  }) {
    return _ref.read(authApiProvider).setPin(
          id,
          pin,
          isCurrentUser: id == currentUserId,
        );
  }
}

final cashiersProvider = StateNotifierProvider<CashiersNotifier, AsyncValue<List<AppUser>>>((ref) {
  return CashiersNotifier(ref);
});
