import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A user-customizable color palette (Settings → Apparence).
///
/// Kept as a plain value object separate from the static [AppColors]
/// class (which stays untouched — see its own doc comment about being
/// promotable to exactly this kind of object later). [AppTheme.build]
/// turns an [AppPalette] into the actual [ThemeData], so every widget
/// that already reads colors from `Theme.of(context)` (Card, AppBar,
/// ElevatedButton, inputs, chips, dividers, scaffold background — i.e.
/// most of the visual chrome around every screen) reacts live when the
/// palette changes, with no per-screen changes required.
///
/// Widgets that instead reference the static [AppColors] constants
/// directly for one-off accents (a handful of icons/badges) don't pick
/// up a custom palette — see the dashboard/sidebar/top bar widgets for
/// the ones that have been migrated to read from the palette instead.
@immutable
class AppPalette {
  final String name;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color background;
  final Color card;
  final Color text;
  final Brightness brightness;

  const AppPalette({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.background,
    required this.card,
    required this.text,
    this.brightness = Brightness.light,
  });

  AppPalette copyWith({
    String? name,
    Color? primary,
    Color? secondary,
    Color? accent,
    Color? background,
    Color? card,
    Color? text,
    Brightness? brightness,
  }) {
    return AppPalette(
      name: name ?? this.name,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      card: card ?? this.card,
      text: text ?? this.text,
      brightness: brightness ?? this.brightness,
    );
  }

  Color get textSecondary => Color.alphaBlend(text.withOpacity(0.62), background);
  Color get border => Color.alphaBlend(text.withOpacity(0.10), card);

  Map<String, dynamic> toJson() => {
        'name': name,
        'primary': primary.value,
        'secondary': secondary.value,
        'accent': accent.value,
        'background': background.value,
        'card': card.value,
        'text': text.value,
        'brightness': brightness == Brightness.dark ? 'dark' : 'light',
      };

  factory AppPalette.fromJson(Map<String, dynamic> json) {
    final fallback = AppPalettes.defaultPalette;
    Color colorOr(String key, Color fallbackColor) {
      final raw = json[key];
      return raw is int ? Color(raw) : fallbackColor;
    }

    return AppPalette(
      name: json['name'] as String? ?? fallback.name,
      primary: colorOr('primary', fallback.primary),
      secondary: colorOr('secondary', fallback.secondary),
      accent: colorOr('accent', fallback.accent),
      background: colorOr('background', fallback.background),
      card: colorOr('card', fallback.card),
      text: colorOr('text', fallback.text),
      brightness: json['brightness'] == 'dark' ? Brightness.dark : Brightness.light,
    );
  }
}

/// Predefined themes offered in Settings → Apparence, plus the "Default"
/// palette that mirrors the project's original hard-coded [AppColors]
/// exactly (so picking "Défaut" — or never opening the theme picker at
/// all — looks identical to the app before this feature existed).
class AppPalettes {
  AppPalettes._();

  static const defaultPalette = AppPalette(
    name: 'theme.default',
    primary: AppColors.primary,
    secondary: AppColors.accentPurple,
    accent: AppColors.accentOrange,
    background: AppColors.background,
    card: AppColors.surface,
    text: AppColors.textPrimary,
  );

  static const blue = AppPalette(
    name: 'theme.blue',
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF0EA5E9),
    accent: Color(0xFF38BDF8),
    background: Color(0xFFF0F6FF),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
  );

  static const green = AppPalette(
    name: 'theme.green',
    primary: Color(0xFF16A34A),
    secondary: Color(0xFF0D9488),
    accent: Color(0xFF84CC16),
    background: Color(0xFFF3FBF5),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF14231A),
  );

  static const purple = AppPalette(
    name: 'theme.purple',
    primary: Color(0xFF7C3AED),
    secondary: Color(0xFFA855F7),
    accent: Color(0xFFEC4899),
    background: Color(0xFFF6F3FE),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF1E1533),
  );

  static const orange = AppPalette(
    name: 'theme.orange',
    primary: Color(0xFFEA580C),
    secondary: Color(0xFFF59E0B),
    accent: Color(0xFFDC2626),
    background: Color(0xFFFFF7ED),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF2B1B0E),
  );

  static const light = AppPalette(
    name: 'theme.light',
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF64748B),
    accent: Color(0xFF0EA5E9),
    background: Color(0xFFFFFFFF),
    card: Color(0xFFF8FAFC),
    text: Color(0xFF0F172A),
  );

  static const dark = AppPalette(
    name: 'theme.dark',
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF8B5CF6),
    accent: Color(0xFFF97316),
    background: Color(0xFF0F1115),
    card: Color(0xFF1A1D23),
    text: Color(0xFFF3F4F6),
    brightness: Brightness.dark,
  );

  static const List<AppPalette> presets = [
    defaultPalette,
    blue,
    green,
    purple,
    orange,
    light,
    dark,
  ];
}
