import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The visual on-screen keyboard docked under a focused text field.
///
/// Purely presentational — it reports key presses through callbacks and
/// has no idea which [TextEditingController] it's editing. That wiring
/// lives in [KeyboardAutoShow], which owns the currently-focused
/// controller and applies the edits.
class VirtualKeyboard extends StatefulWidget {
  const VirtualKeyboard({
    super.key,
    required this.isNumeric,
    required this.onKey,
    required this.onBackspace,
    required this.onDone,
  });

  /// Numeric fields (price, quantity, barcode, PIN, etc.) get a compact
  /// numeric keypad instead of the full QWERTY layout, matching the
  /// field's existing `keyboardType` — this widget doesn't change that
  /// configuration, it just mirrors it visually.
  final bool isNumeric;

  /// Called with the literal character to insert (already
  /// upper/lower-cased for the QWERTY layout's shift state).
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;

  /// Dismisses the keyboard (unfocuses the field).
  final VoidCallback onDone;

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard> {
  bool _shift = false;

  static const _row0 = '1234567890';
  static const _row1 = 'qwertyuiop';
  static const _row2 = 'asdfghjkl';
  static const _row3 = 'zxcvbnm';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: widget.isNumeric ? _buildNumeric() : _buildQwerty(),
        ),
      ),
    );
  }

  Widget _buildQwerty() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _keyRow(_row0.split('')),
        const SizedBox(height: 6),
        _keyRow(_row1.split('')),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _keyRow(_row2.split('')),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _specialKey(
              icon: Icons.arrow_upward_rounded,
              flex: 2,
              selected: _shift,
              onTap: () => setState(() => _shift = !_shift),
            ),
            const SizedBox(width: 6),
            Expanded(flex: 7, child: _keyRow(_row3.split(''))),
            const SizedBox(width: 6),
            _specialKey(
              icon: Icons.backspace_outlined,
              flex: 2,
              onTap: widget.onBackspace,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: _key(' ', label: 'Espace', onTap: () => widget.onKey(' ')),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: _specialKey(
                icon: Icons.check_rounded,
                filled: true,
                onTap: widget.onDone,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumeric() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '←'];
    // Smaller than the QWERTY layout on purpose: a numeric field like
    // price/SKU/quantity only ever needs a few taps, so a full-width,
    // 44px-tall keypad is oversized for it — this one is capped to a
    // compact width and uses shorter, tighter keys instead, closer in
    // scale to the text field it's attached to.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1.8,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ...keys.map((k) {
              if (k == '←') {
                return _specialKey(
                  icon: Icons.backspace_outlined,
                  onTap: widget.onBackspace,
                  height: 32,
                  iconSize: 15,
                );
              }
              return _key(k, onTap: () => widget.onKey(k), height: 32, fontSize: 13);
            }),
          ],
        ),
      ),
    );
  }

  Widget _keyRow(List<String> letters) {
    return Row(
      children: [
        for (final l in letters) ...[
          Expanded(
            child: _key(
              _shift ? l.toUpperCase() : l,
              onTap: () => widget.onKey(_shift ? l.toUpperCase() : l),
            ),
          ),
          if (l != letters.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _key(String value, {String? label, required VoidCallback onTap, double height = 44, double fontSize = 15}) {
    return SizedBox(
      height: height,
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Center(
            child: Text(
              label ?? value,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _specialKey({
    required IconData icon,
    required VoidCallback onTap,
    int flex = 1,
    bool selected = false,
    bool filled = false,
    double height = 44,
    double iconSize = 18,
  }) {
    final child = SizedBox(
      height: height,
      child: Material(
        color: filled
            ? AppColors.primary
            : (selected ? AppColors.primaryLight : AppColors.background),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: filled ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
    return flex == 1 ? child : Expanded(flex: flex, child: child);
  }
}
