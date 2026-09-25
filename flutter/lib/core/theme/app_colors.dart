import 'package:flutter/material.dart';

/// Central color palette for the Store POS design system.
///
/// Kept as static consts (not a Theme extension) on purpose for Phase 1:
/// simple, obvious, and easy for every widget to reach without extra
/// plumbing. If/when we need per-store theming (multi-tenant branding),
/// this can be promoted to a [ThemeExtension] without touching call sites
/// much, since everything already goes through [AppColors].
class AppColors {
  AppColors._();

  // Brand — matches the blue "Store POS" dashboard design.
  static const Color primary = Color(0xFF2563EB); // blue-600
  static const Color primaryDark = Color(0xFF1D4ED8); // blue-700
  static const Color primaryLight = Color(0xFFDBEAFE); // blue-100
  static const Color primarySurface = Color(0xFFEFF6FF); // blue-50

  // Neutrals
  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color sidebarBackground = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE7E9EC);
  static const Color divider = Color(0xFFEEF0F2);

  static const Color textPrimary = Color(0xFF1A1D1F);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Category chip / accent tints (used for product category badges)
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentOrange = Color(0xFFF97316);
  static const Color accentTeal = Color(0xFF14B8A6);

  static const List<Color> chipPalette = [
    accentBlue,
    accentOrange,
    accentPurple,
    accentTeal,
    primary,
    danger,
  ];
}
