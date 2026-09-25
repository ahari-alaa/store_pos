import 'package:flutter/material.dart';

import 'virtual_keyboard.dart';

/// Docks [VirtualKeyboard] under whatever text field currently has focus,
/// anywhere in the app -- including inside dialogs.
///
/// It listens at the app-wide [FocusManager] level rather than per-widget.
/// Every existing `TextField`/`TextFormField` is built on [EditableText],
/// and that widget exposes its [TextEditingController] and `keyboardType`
/// as public fields, so this can read/drive the currently-focused field
/// generically without any changes to individual screens or forms.
class KeyboardAutoShow extends StatefulWidget {
  const KeyboardAutoShow({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardAutoShow> createState() => _KeyboardAutoShowState();
}

class _KeyboardAutoShowState extends State<KeyboardAutoShow> {
  EditableText? _active;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    // primaryFocus.context is the BuildContext of the internal `Focus`
    // widget that EditableText wraps itself in -- not EditableText's own
    // context -- so checking `context.widget is EditableText` directly
    // never matches. EditableText is an ancestor of that Focus widget in
    // the element tree (it's the one that built it), so walk up to find
    // it; fall back to the widget itself in case a future Flutter version
    // changes that internal wiring.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    EditableText? next;
    if (focusContext != null) {
      final w = focusContext.widget;
      next = w is EditableText
          ? w
          : focusContext.findAncestorWidgetOfExactType<EditableText>();
    }
    if (next != _active) {
      setState(() => _active = next);
    }
  }

  bool get _isNumeric {
    final type = _active?.keyboardType.index;
    // TextInputType.number and TextInputType.phone are the numeric-style
    // inputs used across the POS (price, quantity, barcode, PIN); every
    // other keyboardType falls back to the full QWERTY layout.
    return type == TextInputType.number.index || type == TextInputType.phone.index;
  }

  void _insert(String value) {
    final controller = _active?.controller;
    if (controller == null) return;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final newText = text.replaceRange(start, end, value);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    // Setting controller.value only updates what's drawn on screen --
    // TextField.onChanged (search filters, form validation, Riverpod
    // state, etc.) is only invoked by Flutter along the real keystroke
    // path, never by an external controller mutation. EditableText.onChanged
    // is the same public field TextField forwards its own onChanged to,
    // so calling it here is what actually makes typed text "do its job"
    // (search-as-you-type, live totals, etc.) instead of just being
    // displayed.
    _active?.onChanged?.call(newText);
  }

  void _backspace() {
    final controller = _active?.controller;
    if (controller == null) return;
    final text = controller.text;
    final selection = controller.selection;
    if (text.isEmpty) return;
    if (selection.start != selection.end && selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, '');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
      _active?.onChanged?.call(newText);
      return;
    }
    final cursor = selection.start < 0 ? text.length : selection.start;
    if (cursor == 0) return;
    final newText = text.replaceRange(cursor - 1, cursor, '');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor - 1),
    );
    _active?.onChanged?.call(newText);
  }

  void _done() {
    _active?.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_active != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // Without this, every key tap lands outside the focused
            // field's own hit box, which triggers TextField's default
            // "tap outside" behavior and unfocuses the field before the
            // key's onTap even fires -- so nothing ever got typed.
            // TextFieldTapRegion tells the field "this control is part
            // of me", the same mechanism Flutter's own docs recommend
            // for spinner buttons attached to a field.
            child: TextFieldTapRegion(
              child: VirtualKeyboard(
                isNumeric: _isNumeric,
                onKey: _insert,
                onBackspace: _backspace,
                onDone: _done,
              ),
            ),
          ),
      ],
    );
  }
}
