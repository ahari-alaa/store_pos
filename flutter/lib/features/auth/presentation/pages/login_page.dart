import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../providers/auth_provider.dart';

const int _kMinPinLength = 4;
const int _kMaxPinLength = 8;

/// Width below which the branding panel is dropped and only the PIN card
/// is shown. Hiding decoration on a small window is fine; hiding a
/// control would not be.
const double _kBrandPanelBreakpoint = 900;

/// POS cashier login screen: PIN-only, no email/password, no user
/// picker. The cashier enters their PIN on the on-screen numeric keypad
/// (no OS keyboard involved) and the backend resolves which user that
/// PIN belongs to — see AuthNotifier.loginWithPin /
/// store_pos_backend/src/services/authService.js#loginWithPin.
///
/// The redesign changes the presentation only. Specifically it does *not*
/// introduce the email/username + password + "remember me" form from the
/// visual reference: this deployment authenticates by PIN, and swapping
/// in a credentials form would mean either breaking login outright or
/// inventing a backend route that does not exist.
///
/// Two real defects are fixed here beyond the styling:
///   * the screen read every colour from the static `AppColors` constants,
///     which are compile-time light-mode values — so choosing the Dark
///     palette in Paramètres left the login screen stubbornly white. It
///     now resolves through `context.colors` like the rest of the app.
///   * there was no physical-keyboard path. A cashier workstation usually
///     has a keyboard or a numpad attached, and having to mouse over to
///     nine on-screen buttons is slow. Digits, Backspace and Enter now
///     work, without removing the on-screen keypad for touch terminals.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  String _pin = '';
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _onDigit(String digit) {
    final auth = ref.read(authProvider);
    if (auth.status == AuthStatus.authenticating) return;
    if (_pin.length >= _kMaxPinLength) return;

    setState(() => _pin += digit);

    // Clear a previous error the moment the cashier starts typing again,
    // rather than leaving a stale "Incorrect PIN" up while they retry.
    if (auth.errorMessage != null) {
      ref.read(authProvider.notifier).clearError();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _onEnter() async {
    if (_pin.length < _kMinPinLength) return;
    final pin = _pin;
    final success = await ref.read(authProvider.notifier).loginWithPin(pin);
    // Wrong PIN: clear the dots so the cashier isn't stuck editing a PIN
    // that's already known to be wrong, and can just re-enter cleanly.
    if (!success && mounted) {
      setState(() => _pin = '');
    }
  }

  /// Physical keyboard support. Digits map to [_onDigit]; Backspace and
  /// Delete erase; Enter submits; Escape clears the whole entry.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (ref.read(authProvider).status == AuthStatus.authenticating) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _onBackspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _onEnter();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_pin.isNotEmpty) setState(() => _pin = '');
      return KeyEventResult.handled;
    }

    // `character` covers both the number row and the numpad without
    // enumerating eighteen LogicalKeyboardKey constants.
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 0x30 &&
        character.codeUnitAt(0) <= 0x39) {
      _onDigit(character);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final auth = ref.watch(authProvider);
    final isLoading = auth.status == AuthStatus.authenticating;

    return Scaffold(
      backgroundColor: colors.background,
      body: Focus(
        focusNode: _keyboardFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showBrandPanel =
                constraints.maxWidth >= _kBrandPanelBreakpoint;

            final card = _PinCard(
              pin: _pin,
              isLoading: isLoading,
              errorMessage: auth.errorMessage,
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              onEnter: _onEnter,
            );

            if (!showBrandPanel) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: card,
                  ),
                ),
              );
            }

            return Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: card,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Left-hand branding panel. Pure decoration — it carries no control, so
/// dropping it on a narrow window costs the cashier nothing.
class _BrandPanel extends ConsumerWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        // A two-stop gradient off the brand colour, so a custom palette
        // is honoured instead of a stock photo that fights it.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            Color.alphaBlend(Colors.black.withOpacity(0.28), colors.primary),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.onPrimary.withOpacity(0.16),
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: colors.onPrimary,
                size: 28,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              tr(ref, 'app.name'),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: colors.onPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                tr(ref, 'login.tagline'),
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: colors.onPrimary.withOpacity(0.78),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The PIN entry card: title, masked dots, error, keypad, submit.
class _PinCard extends ConsumerWidget {
  final String pin;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onEnter;

  const _PinCard({
    required this.pin,
    required this.isLoading,
    required this.errorMessage,
    required this.onDigit,
    required this.onBackspace,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: colors.border),
        boxShadow: AppShadows.overlay(Theme.of(context).brightness),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr(ref, 'login.title'), style: text.pageTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(tr(ref, 'login.subtitle'), style: text.pageSubtitle),
          const SizedBox(height: AppSpacing.xxl),
          _PinDots(length: pin.length, isLoading: isLoading),
          // Reserved height: without it the keypad jumps up and down as
          // the error appears and clears, which makes the buttons move
          // under the cashier's finger mid-retry.
          SizedBox(
            height: 64,
            child: Center(
              child: _ErrorSlot(message: errorMessage),
            ),
          ),
          _Keypad(
            enabled: !isLoading,
            canBackspace: pin.isNotEmpty,
            onDigit: onDigit,
            onBackspace: onBackspace,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: AppSizes.buttonHeightLg,
            child: FilledButton(
              onPressed:
                  (!isLoading && pin.length >= _kMinPinLength) ? onEnter : null,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                disabledBackgroundColor: colors.disabled,
                disabledForegroundColor: colors.onDisabled,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.smAll,
                ),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: colors.onPrimary,
                      ),
                    )
                  : Text(
                      tr(ref, 'login.enter'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            tr(ref, 'login.footer_help'),
            textAlign: TextAlign.center,
            style: text.bodySecondary.copyWith(
              fontSize: 12.5,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows either the server's message or the local "too short" hint.
///
/// The messages surfaced here come from AuthNotifier, which already
/// translates backend error codes into cashier-readable French — no raw
/// `ApiException`, status code or stack trace ever reaches this widget.
class _ErrorSlot extends StatelessWidget {
  final String? message;

  const _ErrorSlot({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (message == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.dangerSurface,
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: AppSizes.iconSm,
            color: colors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              message!,
              style: TextStyle(
                color: colors.danger,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `● ● ● ●` — masked PIN display. Never renders the actual digits.
class _PinDots extends StatelessWidget {
  final int length;
  final bool isLoading;

  const _PinDots({required this.length, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 30,
      child: isLoading
          ? Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colors.primary,
                ),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _kMaxPinLength; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.md),
                  _Dot(filled: i < length),
                ],
              ],
            ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool filled;

  const _Dot({required this.filled});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? colors.primary : Colors.transparent,
        border: Border.all(
          color: filled ? colors.primary : colors.borderStrong,
          width: 1.5,
        ),
      ),
    );
  }
}

/// On-screen numeric keypad: 1-9, a blank spacer, 0, and backspace. No OS
/// keyboard is ever requested — there is no [TextField] on this screen at
/// all.
class _Keypad extends StatelessWidget {
  final bool enabled;
  final bool canBackspace;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  const _Keypad({
    required this.enabled,
    required this.canBackspace,
    required this.onDigit,
    required this.onBackspace,
  });

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows) ...[
          Row(
            children: [
              for (final digit in row) ...[
                Expanded(
                  child: _KeypadButton(
                    label: digit,
                    onTap: enabled ? () => onDigit(digit) : null,
                  ),
                ),
                if (digit != row.last) const SizedBox(width: AppSpacing.md),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Row(
          children: [
            const Expanded(child: SizedBox()),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _KeypadButton(
                label: '0',
                onTap: enabled ? () => onDigit('0') : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _KeypadButton(
                icon: Icons.backspace_outlined,
                onTap: enabled && canBackspace ? onBackspace : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;

  const _KeypadButton({this.label, this.icon, this.onTap});

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = widget.onTap == null;

    return AspectRatio(
      aspectRatio: 1.5,
      child: Material(
        color: disabled
            ? colors.surface
            : (_hovered ? colors.surfaceHover : colors.surfaceMuted),
        borderRadius: AppRadius.smAll,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: AppRadius.smAll,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.smAll,
              border: Border.all(
                color: _hovered && !disabled
                    ? colors.borderStrong
                    : colors.border,
              ),
            ),
            alignment: Alignment.center,
            child: widget.label != null
                ? Text(
                    widget.label!,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      // Tabular figures so 1 and 8 occupy the same width
                      // and the keypad grid does not shimmer.
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: disabled
                          ? colors.onDisabled
                          : colors.textPrimary,
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: 22,
                    color: disabled ? colors.onDisabled : colors.textSecondary,
                  ),
          ),
        ),
      ),
    );
  }
}
