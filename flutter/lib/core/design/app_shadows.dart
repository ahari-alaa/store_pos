import 'package:flutter/material.dart';

/// Elevation tokens.
///
/// This application is border-led, not shadow-led: cards and panels are
/// separated by a 1px border and a background step, which is what reads as
/// "enterprise software" rather than "Material demo". Shadows appear only
/// on surfaces that genuinely float above the page — menus, dialogs, and a
/// tile while the pointer is over it.
///
/// There are three levels and no more. If a surface needs a fourth, the
/// layout is the problem, not the shadow.
class AppShadows {
  AppShadows._();

  /// Flat. Cards, panels, tables at rest.
  static const List<BoxShadow> none = [];

  /// A card or tile under the pointer, or a sticky table header over
  /// scrolled content. Barely visible on purpose.
  static List<BoxShadow> hover(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withOpacity(brightness == Brightness.dark ? 0.32 : 0.06),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  /// Popup menus, dropdowns, toasts.
  static List<BoxShadow> overlay(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withOpacity(brightness == Brightness.dark ? 0.44 : 0.10),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  /// Modal dialogs.
  static List<BoxShadow> modal(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withOpacity(brightness == Brightness.dark ? 0.56 : 0.16),
          blurRadius: 36,
          offset: const Offset(0, 12),
        ),
      ];
}
