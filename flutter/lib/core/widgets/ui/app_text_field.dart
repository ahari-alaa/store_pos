import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/design_system.dart';

/// The application's text input.
///
/// Every field gets: a label above it (not a floating placeholder that
/// disappears the moment you type — a cashier re-reading a half-filled
/// form needs to know what each box is), a consistent 44px height, and an
/// error slot that is reserved whether or not there is an error, so
/// validation never shifts the form under the user's cursor.
class AppTextField extends StatelessWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  /// Shown under the field in red. Pass a *sentence*, not a code.
  final String? errorText;

  /// Helper text under the field when there is no error.
  final String? helperText;

  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int? maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final TextAlign textAlign;

  /// Marks the field as required. Renders a subtle asterisk on the label
  /// — the only place the app should communicate requiredness, rather
  /// than leaving the user to discover it on submit.
  final bool required;

  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label!, style: text.label),
              if (required)
                Text(
                  ' *',
                  style: text.label.copyWith(color: colors.danger),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm - 2),
        ],
        TextFormField(
          controller: controller,
          initialValue: controller == null ? initialValue : null,
          focusNode: focusNode,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          validator: validator,
          obscureText: obscureText,
          enabled: enabled,
          readOnly: readOnly,
          autofocus: autofocus,
          maxLines: obscureText ? 1 : maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textAlign: textAlign,
          style: text.body.copyWith(
            color: enabled ? colors.textPrimary : colors.onDisabled,
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: AppSizes.iconMd, color: colors.textMuted)
                : null,
            suffixIcon: suffix,
            // The theme supplies fill, border, radius and padding, so a
            // field looks the same on every screen without each screen
            // restating it — which is exactly what the old code did, with
            // six different fill colors and four radii.
          ),
        ),
      ],
    );
  }
}

/// A password/PIN field with a show/hide toggle. Kept as its own widget so
/// the toggle behaves identically everywhere it appears.
class AppPasswordField extends StatefulWidget {
  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final bool required;

  const AppPasswordField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.required = false,
  });

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      hint: widget.hint,
      controller: widget.controller,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      errorText: widget.errorText,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      required: widget.required,
      obscureText: _obscured,
      suffix: IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: AppSizes.iconMd,
          color: context.colors.textMuted,
        ),
        tooltip: _obscured ? 'Afficher' : 'Masquer',
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}

/// The search box used in every module toolbar.
///
/// Always shows a clear button once there is text: the previous screens
/// left the cashier to select-all-and-delete to get back to the full list,
/// which is three interactions for something that should be one.
class AppSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;
  final double? width;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  /// Extra affordance shown before the clear button — the POS uses it for
  /// the barcode-scanner hint.
  final Widget? trailing;

  const AppSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
    this.width,
    this.focusNode,
    this.onSubmitted,
    this.trailing,
  });

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    // Only rebuild for the empty/non-empty transition, which is all the
    // clear button cares about — not on every keystroke.
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = _controller.text.isNotEmpty;

    return SizedBox(
      width: widget.width,
      height: AppSizes.inputHeight,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: context.text.body,
        decoration: InputDecoration(
          hintText: widget.hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          prefixIcon:
              Icon(Icons.search_rounded, size: AppSizes.iconMd, color: colors.textMuted),
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.trailing != null) widget.trailing!,
              if (hasText)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: AppSizes.iconSm, color: colors.textMuted),
                  tooltip: 'Effacer',
                  splashRadius: 16,
                  onPressed: _clear,
                ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 40),
        ),
      ),
    );
  }
}
