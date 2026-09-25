import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';

/// Cashier-facing numeric keypad for entering "Amount received" in cash.
///
/// Deliberately its own modal with big touch targets instead of a plain
/// [TextField] + OS keyboard — a cashier standing at a register shouldn't
/// need to reach for a physical keyboard to ring up cash. Returns the
/// entered amount (a [double]) via [Navigator.pop], or `null` if the
/// cashier dismissed the dialog without confirming.
///
/// The arithmetic (`_appendDigit`, `_normalize`, `_change`, …) is
/// unchanged by the redesign — it was correct, and change calculation is
/// the last thing that should be rewritten for looks. What changed:
///
///  * **Physical keyboard/numpad now works.** A register almost always
///    has a numpad wired to it, and the dialog previously ignored it
///    completely — the cashier had to mouse over to twelve on-screen
///    keys. Digits, `.`, Backspace, Escape and Enter are now bound,
///    *without* removing the on-screen keypad for touch terminals.
///  * **Quick-amount chips.** Appoint (exact change) plus the common
///    note denominations. These are the fastest path for the overwhelming
///    majority of cash transactions and save the whole typing step.
///  * The strings were English inside an otherwise French till, and every
///    colour was a static light-mode constant.
class CashAmountKeypadDialog extends ConsumerStatefulWidget {
  final double total;
  final double initialValue;

  const CashAmountKeypadDialog({
    super.key,
    required this.total,
    this.initialValue = 0,
  });

  @override
  ConsumerState<CashAmountKeypadDialog> createState() =>
      _CashAmountKeypadDialogState();
}

class _CashAmountKeypadDialogState
    extends ConsumerState<CashAmountKeypadDialog> {
  /// Raw digit/decimal-point buffer the cashier is typing, e.g. "150.5".
  /// Kept as a string (not a double) while editing so the cashier can type
  /// a trailing "." or a single trailing zero without it being silently
  /// dropped by number parsing.
  late String _buffer;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _buffer = widget.initialValue > 0
        ? _trimTrailingZeros(widget.initialValue.toStringAsFixed(2))
        : '';
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_buffer) ?? 0;

  double get _change => _amount - widget.total;

  void _appendDigit(String digit) {
    setState(() {
      if (_buffer.isEmpty && digit == '0') {
        // Ignore extra leading zeros ("0", "00", ...) — nothing to show yet.
        return;
      }
      if (_buffer == '0') {
        // Replace a lone leading zero rather than producing "05".
        _buffer = digit == '.' ? '0.' : digit;
        return;
      }
      _buffer += digit;
      _buffer = _normalize(_buffer);
    });
  }

  void _appendDot() {
    setState(() {
      if (_buffer.contains('.')) return; // one decimal point max
      _buffer = _buffer.isEmpty ? '0.' : '$_buffer.';
    });
  }

  void _appendDoubleZero() {
    setState(() {
      if (_buffer.isEmpty) return; // "00" alone means nothing to a cashier
      _buffer = _normalize('${_buffer}00');
    });
  }

  void _backspace() {
    setState(() {
      if (_buffer.isEmpty) return;
      _buffer = _buffer.substring(0, _buffer.length - 1);
    });
  }

  void _clear() {
    setState(() => _buffer = '');
  }

  /// Sets the buffer outright, used by the quick-amount chips.
  void _setAmount(double value) {
    setState(() => _buffer = _trimTrailingZeros(value.toStringAsFixed(2)));
  }

  /// Caps the decimal part at 2 digits and the whole buffer at a sane
  /// length, so entry always stays a valid, bounded currency-looking value
  /// (never "12..50" — a second "." is rejected before it's appended in
  /// [_appendDot] — and never "0012.5.6" — decimals beyond 2 digits are
  /// trimmed here).
  String _normalize(String value) {
    if (value.length > 12) value = value.substring(0, 12);
    final dotIndex = value.indexOf('.');
    if (dotIndex == -1) return value;
    final decimals = value.substring(dotIndex + 1);
    if (decimals.length <= 2) return value;
    return '${value.substring(0, dotIndex)}.${decimals.substring(0, 2)}';
  }

  String _trimTrailingZeros(String value) {
    if (!value.contains('.')) return value;
    var v = value;
    while (v.endsWith('0')) {
      v = v.substring(0, v.length - 1);
    }
    if (v.endsWith('.')) v = v.substring(0, v.length - 1);
    return v;
  }

  void _confirm() {
    Navigator.of(context).pop(_amount);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _clear();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    final character = event.character;
    if (character == '.' || character == ',') {
      // A numpad's decimal key emits ',' under a French layout.
      _appendDot();
      return KeyEventResult.handled;
    }
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 0x30 &&
        character.codeUnitAt(0) <= 0x39) {
      _appendDigit(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Exact amount first, then the note denominations that are actually
  /// larger than the total — offering "20 DH" for a 340 DH basket is
  /// noise, so those are filtered out.
  List<(String, double)> _quickAmounts() {
    final out = <(String, double)>[
      (trRead(ref, 'keypad.exact'), widget.total),
    ];
    for (final note in const [20.0, 50.0, 100.0, 200.0, 500.0]) {
      if (note > widget.total) {
        out.add(('${note.toStringAsFixed(0)} DH', note));
      }
    }
    // Four chips is what fits on one row at this dialog width.
    return out.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final displayText = _buffer.isEmpty ? '0.00' : _buffer;
    // Computed once: it was being rebuilt three times per frame, and the
    // `label == last.$1` separator test broke if two chips shared a label.
    final quick = _quickAmounts();
    final sufficient = _amount >= widget.total - 0.001;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AppDialog(
        title: tr(ref, 'keypad.title'),
        icon: Icons.payments_outlined,
        width: 420,
        actions: [
          AppButton.outline(
            label: tr(ref, 'keypad.clear'),
            icon: Icons.close_rounded,
            onPressed: _buffer.isEmpty ? null : _clear,
          ),
          AppButton.primary(
            label: tr(ref, 'keypad.confirm'),
            icon: Icons.check_rounded,
            onPressed: _confirm,
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The amount display: the one thing in this dialog the
            // cashier and the customer both look at.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: colors.primarySurface,
                borderRadius: AppRadius.mdAll,
              ),
              // Scales down instead of overflowing once the cashier types
              // a long amount.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$displayText DH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SummaryRow(
              label: tr(ref, 'keypad.total'),
              value: CurrencyFormatter.format(widget.total),
            ),
            const SizedBox(height: AppSpacing.xs),
            _SummaryRow(
              label: tr(
                ref,
                sufficient ? 'keypad.change' : 'keypad.remaining',
              ),
              value: CurrencyFormatter.format(_change.abs()),
              emphasize: true,
              color: sufficient ? colors.success : colors.danger,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              tr(ref, 'keypad.quick_amounts'),
              style: text.label.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var i = 0; i < quick.length; i++) ...[
                  Expanded(
                    child: _QuickChip(
                      label: quick[i].$1,
                      onTap: () => _setAmount(quick[i].$2),
                    ),
                  ),
                  if (i != quick.length - 1)
                    const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Keypad(
              onDigit: _appendDigit,
              onDoubleZero: _appendDoubleZero,
              onDot: _appendDot,
              onBackspace: _backspace,
              backspaceLabel: tr(ref, 'keypad.backspace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceMuted,
      borderRadius: AppRadius.smAll,
      child: InkWell(
        borderRadius: AppRadius.smAll,
        onTap: onTap,
        child: Container(
          height: AppSizes.buttonHeightSm,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.smAll,
            border: Border.all(color: colors.border),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final Color? color;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasize ? 16 : 13,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDoubleZero;
  final VoidCallback onDot;
  final VoidCallback onBackspace;
  final String backspaceLabel;

  const _Keypad({
    required this.onDigit,
    required this.onDoubleZero,
    required this.onDot,
    required this.onBackspace,
    required this.backspaceLabel,
  });

  @override
  Widget build(BuildContext context) {
    // Calculator layout (7-8-9 on top), which is what a register numpad
    // uses — keeping the on-screen keys in the same order as the physical
    // ones avoids a mis-key when a cashier switches between the two.
    const rows = [
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
    ];

    VoidCallback tapFor(String label) => switch (label) {
          '00' => onDoubleZero,
          '.' => onDot,
          _ => () => onDigit(label),
        };

    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              for (final label in row) ...[
                Expanded(child: _Key(label: label, onTap: tapFor(label))),
                if (label != row.last) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          children: [
            Expanded(child: _Key(label: '00', onTap: onDoubleZero)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Key(label: '0', onTap: () => onDigit('0'))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Key(label: '.', onTap: onDot)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: AppButton.outline(
            label: backspaceLabel,
            icon: Icons.backspace_outlined,
            expand: true,
            onPressed: onBackspace,
          ),
        ),
      ],
    );
  }
}

class _Key extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _Key({required this.label, required this.onTap});

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: _hovered ? colors.surfaceHover : colors.surfaceMuted,
      borderRadius: AppRadius.smAll,
      child: InkWell(
        borderRadius: AppRadius.smAll,
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.smAll,
            border: Border.all(color: colors.border),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
