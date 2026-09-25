import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The application's semantic color set, resolved from the active
/// [AppPalette] and exposed through the [Theme] as a [ThemeExtension].
///
/// Why this exists: before the redesign, ~460 call sites across 52 files
/// read colors straight off the static `AppColors` constants. Those are
/// compile-time light-mode values, so the Settings -> Apparence palettes
/// (and the Dark preset in particular) only ever repainted the handful of
/// chrome widgets that happened to read from `Theme.of(context)` — every
/// card body, table, badge and POS panel stayed hard light. Colors that
/// live on the Theme fix that at the root: one lookup, always correct for
/// the active palette and brightness.
///
/// Read it with `context.colors` (see the extension at the bottom of this
/// file), never by constructing it directly.
///
/// The static `AppColors` class is intentionally left in place — it is
/// still the source of the default palette's values, and the screens not
/// yet migrated keep compiling against it.
@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  // --- Brand ---
  final Color primary;
  final Color onPrimary;

  /// Very light wash of the brand color. Used for selected navigation
  /// rows, info panels, and the POS total block.
  final Color primarySurface;
  final Color secondary;

  // --- Neutrals / structure ---
  /// Page background, behind cards.
  final Color background;

  /// Card, panel, dialog and table surface.
  final Color surface;

  /// One step recessed from [surface]: input fills, keypad keys,
  /// table header rows, quantity steppers.
  final Color surfaceMuted;

  /// Hover state for interactive rows and tiles.
  final Color surfaceHover;

  /// Navigation sidebar background.
  final Color sidebar;

  /// Hairline borders on cards, inputs, tables, dividers.
  final Color border;

  /// Slightly stronger border, for focused or selected containers.
  final Color borderStrong;

  // --- Text ---
  /// Headings, values, anything that carries the meaning of a line.
  final Color textPrimary;

  /// Labels, descriptions, secondary metadata.
  final Color textSecondary;

  /// Placeholders, disabled text, timestamps.
  final Color textMuted;

  // --- Status ---
  final Color success;
  final Color successSurface;
  final Color warning;
  final Color warningSurface;
  final Color danger;
  final Color dangerSurface;
  final Color info;
  final Color infoSurface;

  /// Fill and text color for disabled controls.
  final Color disabled;
  final Color onDisabled;

  const AppColorScheme({
    required this.primary,
    required this.onPrimary,
    required this.primarySurface,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceHover,
    required this.sidebar,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.danger,
    required this.dangerSurface,
    required this.info,
    required this.infoSurface,
    required this.disabled,
    required this.onDisabled,
  });

  /// Derives the full semantic set from a user-chosen [AppPalette].
  ///
  /// The status hues (success/warning/danger/info) stay fixed rather than
  /// being derived from the palette: in a POS, "out of stock" must read as
  /// red and "paid" as green regardless of which brand color the store
  /// picked,
  /// and a manager glancing at a stock table should not have to re-learn
  /// what the colors mean because someone chose a green theme. What *does*
  /// adapt is the tint behind each status, which is blended against the
  /// real surface so it stays legible on a dark palette instead of
  /// stamping a light pink panel onto a dark card.
  factory AppColorScheme.fromPalette(AppPalette palette) {
    final isDark = palette.brightness == Brightness.dark;
    final surface = palette.card;
    final text = palette.text;

    // Blends [color] into [surface] at [opacity] — a real opaque color,
    // not a translucent overlay, so it composites identically whatever is
    // painted behind it (important inside scrolling lists and tables).
    Color tint(Color color, double opacity) =>
        Color.alphaBlend(color.withOpacity(opacity), surface);

    const success = Color(0xFF16A34A);
    const warning = Color(0xFFF59E0B);
    const danger = Color(0xFFEF4444);
    const info = Color(0xFF3B82F6);

    // A dark surface needs a stronger tint to be visible at all; a light
    // one needs a weaker tint to stay subtle.
    final tintStrength = isDark ? 0.18 : 0.10;

    return AppColorScheme(
      primary: palette.primary,
      onPrimary: readableOn(palette.primary),
      primarySurface: tint(palette.primary, tintStrength),
      secondary: palette.secondary,
      background: palette.background,
      surface: surface,
      surfaceMuted: isDark
          ? Color.alphaBlend(Colors.white.withOpacity(0.05), surface)
          : Color.alphaBlend(text.withOpacity(0.04), surface),
      surfaceHover: isDark
          ? Color.alphaBlend(Colors.white.withOpacity(0.07), surface)
          : Color.alphaBlend(text.withOpacity(0.045), surface),
      sidebar: surface,
      border: Color.alphaBlend(text.withOpacity(isDark ? 0.16 : 0.11), surface),
      borderStrong:
          Color.alphaBlend(text.withOpacity(isDark ? 0.30 : 0.20), surface),
      textPrimary: text,
      textSecondary: Color.alphaBlend(text.withOpacity(0.66), surface),
      textMuted: Color.alphaBlend(text.withOpacity(0.45), surface),
      success: isDark ? const Color(0xFF4ADE80) : success,
      successSurface: tint(success, tintStrength),
      warning: isDark ? const Color(0xFFFBBF24) : warning,
      warningSurface: tint(warning, tintStrength),
      danger: isDark ? const Color(0xFFF87171) : danger,
      dangerSurface: tint(danger, tintStrength),
      info: isDark ? const Color(0xFF60A5FA) : info,
      infoSurface: tint(info, tintStrength),
      disabled: Color.alphaBlend(text.withOpacity(0.07), surface),
      onDisabled: Color.alphaBlend(text.withOpacity(0.38), surface),
    );
  }

  /// White text/icons on a dark fill, dark text on a light one. Used for
  /// on-primary content, since a custom palette's primary can legitimately
  /// be a pale yellow.
  static Color readableOn(Color background) {
    return background.computeLuminance() > 0.55
        ? const Color(0xFF1A1D1F)
        : Colors.white;
  }

  /// The accent color for an arbitrary status string, so a badge, a chip
  /// and a table cell all agree on what "PAID" or "LOW_STOCK" looks like.
  /// Unknown values fall back to a neutral, which is the honest answer for
  /// a status the UI does not recognise — it never invents a meaning.
  Color statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'PAID':
      case 'COMPLETED':
      case 'SERVED':
      case 'ACTIVE':
      case 'IN_STOCK':
      case 'SYNCED':
        return success;
      case 'PENDING':
      case 'PREPARING':
      case 'PARTIAL':
      // Cashier settlement awaiting payment TO THE CASHIER (spec §23) —
      // not to be confused with a sale's own PENDING payment_status, but
      // the same "not resolved yet" amber makes sense for both.
      case 'PRINTED':
      // The sales schema's enum value is PARTIALLY_PAID (see
      // migrations/001_init.sql). Only the shortened 'PARTIAL' was
      // listed, so a partially-paid sale fell through to the neutral
      // default and rendered as an unremarkable grey chip instead of an
      // amber one.
      case 'PARTIALLY_PAID':
      case 'LOW_STOCK':
      case 'SYNCING':
        return warning;
      case 'CANCELLED':
      case 'FAILED':
      case 'REFUNDED':
      case 'OUT_OF_STOCK':
      case 'INACTIVE':
        return danger;
      case 'READY':
      case 'DRAFT':
        return info;
      default:
        return textSecondary;
    }
  }

  /// The matching low-contrast fill for [statusColor].
  Color statusSurface(String status) {
    final color = statusColor(status);
    if (color == success) return successSurface;
    if (color == warning) return warningSurface;
    if (color == danger) return dangerSurface;
    if (color == info) return infoSurface;
    return surfaceMuted;
  }

  @override
  AppColorScheme copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primarySurface,
    Color? secondary,
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceHover,
    Color? sidebar,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? success,
    Color? successSurface,
    Color? warning,
    Color? warningSurface,
    Color? danger,
    Color? dangerSurface,
    Color? info,
    Color? infoSurface,
    Color? disabled,
    Color? onDisabled,
  }) {
    return AppColorScheme(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySurface: primarySurface ?? this.primarySurface,
      secondary: secondary ?? this.secondary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      sidebar: sidebar ?? this.sidebar,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      danger: danger ?? this.danger,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      info: info ?? this.info,
      infoSurface: infoSurface ?? this.infoSurface,
      disabled: disabled ?? this.disabled,
      onDisabled: onDisabled ?? this.onDisabled,
    );
  }

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {
    if (other is! AppColorScheme) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorScheme(
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primarySurface: l(primarySurface, other.primarySurface),
      secondary: l(secondary, other.secondary),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceHover: l(surfaceHover, other.surfaceHover),
      sidebar: l(sidebar, other.sidebar),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      success: l(success, other.success),
      successSurface: l(successSurface, other.successSurface),
      warning: l(warning, other.warning),
      warningSurface: l(warningSurface, other.warningSurface),
      danger: l(danger, other.danger),
      dangerSurface: l(dangerSurface, other.dangerSurface),
      info: l(info, other.info),
      infoSurface: l(infoSurface, other.infoSurface),
      disabled: l(disabled, other.disabled),
      onDisabled: l(onDisabled, other.onDisabled),
    );
  }
}

/// `context.colors.textSecondary` — the single way widgets should reach
/// for a color.
///
/// Falls back to the default light palette if the extension somehow isn't
/// registered (e.g. a widget rendered under a bare `MaterialApp` in a
/// test), so a missing theme degrades to correct-looking defaults instead
/// of a null crash.
extension AppColorSchemeX on BuildContext {
  AppColorScheme get colors =>
      Theme.of(this).extension<AppColorScheme>() ?? _fallback;

  static final AppColorScheme _fallback =
      AppColorScheme.fromPalette(AppPalettes.defaultPalette);
}
