import 'package:flutter/material.dart';

/// The two languages this app supports (spec: bilingual FR/AR with RTL
/// for Arabic). Kept as a small enum — rather than raw [Locale] strings
/// scattered around — so the theme/settings code has a closed, typo-proof
/// set of values to switch on.
enum AppLocale { fr, ar }

extension AppLocaleX on AppLocale {
  Locale get locale {
    switch (this) {
      case AppLocale.fr:
        return const Locale('fr');
      case AppLocale.ar:
        return const Locale('ar');
    }
  }

  /// Flutter's built-in Material/Widgets localizations already know
  /// Arabic is RTL and flip `Directionality` automatically once `locale`
  /// above is wired into MaterialApp — this getter is only used by the
  /// couple of custom widgets that need to branch explicitly (e.g. to
  /// mirror an icon by hand).
  TextDirection get textDirection => this == AppLocale.ar ? TextDirection.rtl : TextDirection.ltr;

  String get nativeName {
    switch (this) {
      case AppLocale.fr:
        return 'Français';
      case AppLocale.ar:
        return 'العربية';
    }
  }

  static AppLocale fromCode(String? code) => code == 'ar' ? AppLocale.ar : AppLocale.fr;
}
