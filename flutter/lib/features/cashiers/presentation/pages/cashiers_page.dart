import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/cashiers_provider.dart';
import '../widgets/cashier_form_dialog.dart';
import '../widgets/change_pin_dialog.dart';
import '../widgets/confirm_toggle_active_dialog.dart';

class CashiersPage extends ConsumerStatefulWidget {
  const CashiersPage({super.key});

  @override
  ConsumerState<CashiersPage> createState() => _CashiersPageState();
}

class _CashiersPageState extends ConsumerState<CashiersPage> {
  String _search = '';

  /// Ids of cashiers with a deactivate/reactivate request currently in
  /// flight. Used both to disable that row's button (no double-click) and
  /// to show a small inline progress indicator instead of the icon.
  final Set<String> _pendingIds = {};

  /// Ids of cashiers whose confirmation dialog is currently open.
  ///
  /// Deliberately separate from [_pendingIds]: this one guards the window
  /// between the tap and the admin answering the dialog, during which no
  /// request exists yet and so no spinner should be shown — but a second
  /// tap must still not be able to stack a second dialog on the root
  /// navigator. It's plain state (not `setState`-driven) because nothing
  /// in the UI renders from it; rebuilding for it would only risk
  /// rebuilding the list while a route transition is running.
  final Set<String> _confirmingIds = {};

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user;
    if (currentUser == null || !currentUser.isAdmin) {
      return const RestrictedPage(
        message: 'Only admins can manage cashier accounts.',
      );
    }

    final cashiersAsync = ref.watch(cashiersProvider);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search staff by name or email...',
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.person_add_alt_rounded, size: 20),
                label: const Text('Add cashier'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _buildBody(context, cashiersAsync, currentUser),
          ),
        ],
      ),
    );
  }

  /// Handles the AsyncValue explicitly (instead of a plain `.when`) so a
  /// failed background refresh — e.g. right after a successful
  /// deactivate/reactivate — never blanks out an already-loaded list.
  /// [CashiersNotifier.refresh] keeps the previous value attached via
  /// `copyWithPrevious` specifically so this can stay on screen.
  Widget _buildBody(
    BuildContext context,
    AsyncValue<List<AppUser>> cashiersAsync,
    AppUser currentUser,
  ) {
    if (cashiersAsync.isLoading && !cashiersAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    if (cashiersAsync.hasError && !cashiersAsync.hasValue) {
      final error = cashiersAsync.error;
      return _ErrorState(
        message: error is ApiException ? error.message : 'Could not load staff accounts.',
        onRetry: () => ref.read(cashiersProvider.notifier).refresh(),
      );
    }

    final users = cashiersAsync.value ?? const <AppUser>[];
    final filtered = _search.isEmpty
        ? users
        : users
            .where((u) =>
                u.name.toLowerCase().contains(_search) || u.email.toLowerCase().contains(_search))
            .toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text('No staff accounts found', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = filtered[index];
          return _CashierTile(
            user: user,
            isSelf: user.id == currentUser.id,
            busy: _pendingIds.contains(user.id),
            onOpen: () => context.push('/cashiers/${user.id}', extra: user),
            onEdit: () => _openForm(context, existing: user),
            onChangePin: () => _openChangePin(context, currentUser, user),
            onToggleActive: () => _confirmToggleActive(context, currentUser, user),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, {AppUser? existing}) {
    showDialog(
      context: context,
      builder: (_) => CashierFormDialog(
        existing: existing,
        onSubmit: (input) async {
          final notifier = ref.read(cashiersProvider.notifier);
          if (existing == null) {
            await notifier.createCashier(
              name: input['name'] as String,
              email: input['email'] as String,
              password: input['password'] as String,
              role: input['role'] as String,
            );
          } else {
            final currentUserId = ref.read(authProvider).user?.id ?? '';
            await notifier.updateCashier(existing.id, input, currentUserId: currentUserId);
          }
        },
      ),
    );
  }

  void _openChangePin(BuildContext context, AppUser currentAdmin, AppUser target) {
    showDialog(
      context: context,
      builder: (_) => ChangePinDialog(
        user: target,
        onSubmit: (pin) => ref.read(cashiersProvider.notifier).changePin(
              target.id,
              pin,
              currentUserId: currentAdmin.id,
            ),
      ),
    );
  }

  /// Deactivates/reactivates [target] (never [currentAdmin] themself — the
  /// action button is hidden for `isSelf`, see [_CashierTile]).
  ///
  /// This is the flow that used to black-screen the app with
  /// `'!_debugLocked': is not true`. The whole flow is now ordered as:
  ///
  ///   1. close the confirmation dialog SYNCHRONOUSLY, from the dialog's
  ///      own navigator (see [showConfirmToggleActiveDialog]);
  ///   2. only then start the async request;
  ///   3. never touch a Navigator again afterwards — success and every
  ///      failure mode are reported with a SnackBar on the page that is
  ///      already on screen.
  ///
  /// There is exactly one navigation operation in this method's entire
  /// call chain (the dialog popping itself), and it has fully completed
  /// before any `await` on network work begins. That ordering is what
  /// makes re-entrant navigation structurally impossible here, rather
  /// than merely unlikely.
  ///
  /// A failure here (or even a success) must also never affect
  /// [currentAdmin]'s own session. See CashiersNotifier.updateCashier /
  /// AuthApi.updateUser / ApiClient.put for how a stray 401 on this
  /// specific call is prevented from triggering a global logout.
  Future<void> _confirmToggleActive(
    BuildContext context,
    AppUser currentAdmin,
    AppUser target,
  ) async {
    // Re-entrancy guards. The first covers "dialog already open", the
    // second "request already in flight" — together they make rapid
    // repeated taps on the same row a no-op rather than a second dialog
    // or a second PUT.
    if (_confirmingIds.contains(target.id)) return;
    if (_pendingIds.contains(target.id)) return;

    final deactivating = target.isActive;

    // Captured before any await so no BuildContext is used across an
    // async gap further down (and so the SnackBar still lands on the
    // right messenger even if the widget tree moves underneath us).
    final messenger = ScaffoldMessenger.of(context);

    var confirmed = false;
    _confirmingIds.add(target.id);
    try {
      confirmed = await showConfirmToggleActiveDialog(
        context: context,
        userName: target.name,
        deactivating: deactivating,
      );
    } finally {
      _confirmingIds.remove(target.id);
    }

    // Cancelled: the dialog has already closed itself, the Cashiers page
    // was never touched, and there is nothing left to do. No navigation,
    // no request, no state change.
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _pendingIds.add(target.id));
    try {
      await ref.read(cashiersProvider.notifier).updateCashier(
            target.id,
            {'is_active': !target.isActive},
            currentUserId: currentAdmin.id,
          );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content:
              Text(deactivating ? 'Cashier deactivated successfully.' : 'Cashier reactivated successfully.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } on ApiException catch (e) {
      // Readable backend message (e.g. "You cannot deactivate your own
      // account", "User not found") preserved as-is — the page stays
      // exactly where it is.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not update the cashier. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pendingIds.remove(target.id));
      }
    }
  }
}

class _CashierTile extends StatelessWidget {
  final AppUser user;
  final bool isSelf;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onChangePin;
  final VoidCallback onToggleActive;

  const _CashierTile({
    required this.user,
    required this.isSelf,
    required this.busy,
    required this.onOpen,
    required this.onEdit,
    required this.onChangePin,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onOpen,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySurface,
        child: Text(
          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
        ),
      ),
      title: Row(
        children: [
          Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (isSelf) ...[
            const SizedBox(width: 6),
            const Text('(you)', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ],
      ),
      subtitle: Text('${user.email} • ${_roleLabel(user.role)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: user.isActive ? AppColors.primarySurface : AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              user.isActive ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: user.isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: busy ? null : onEdit,
          ),
          IconButton(
            tooltip: 'Change PIN',
            icon: const Icon(Icons.dialpad_rounded, size: 20),
            onPressed: busy ? null : onChangePin,
          ),
          if (!isSelf)
            SizedBox(
              width: 40,
              height: 40,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: user.isActive ? 'Deactivate' : 'Reactivate',
                      icon: Icon(
                        user.isActive ? Icons.block_outlined : Icons.check_circle_outline_rounded,
                        size: 20,
                        color: user.isActive ? AppColors.danger : AppColors.primary,
                      ),
                      onPressed: onToggleActive,
                    ),
            ),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manager';
      default:
        return 'Cashier';
    }
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
