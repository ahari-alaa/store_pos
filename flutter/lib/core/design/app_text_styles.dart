import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_color_scheme.dart';

/// The application's type scale, exposed on the [Theme] so every screen
/// names a role ("this is a card title") instead of inventing a size.
///
/// Before the redesign the codebase contained font sizes of 9.5, 11, 12,
/// 12.5, 13, 13.5, 14, 15, 16, 20, 22 and 30 — several of them below the
/// ~12px floor that is readable on a register screen at arm's length, and
/// a 9.5px button label in the POS cart that was effectively unreadable.
/// This scale has nine roles and nothing between them.
///
/// Read it with `context.text` (extension at the bottom of this file).
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  /// Screen title in the top bar. 22/w700.
  final TextStyle pageTitle;

  /// Supporting line under a page title. 13/w400, secondary color.
  final TextStyle pageSubtitle;

  /// Heading above a group of cards. 16/w700.
  final TextStyle sectionTitle;

  /// Title inside a card or panel. 15/w600.
  final TextStyle cardTitle;

  /// Default reading text. 14/w400.
  final TextStyle body;

  /// Supporting text, descriptions, metadata. 13/w400, secondary color.
  final TextStyle bodySecondary;

  /// Form field labels and small all-caps column headers. 12/w600.
  final TextStyle label;

  /// Text inside table cells. 13.5/w500 — tuned so a dense table still
  /// reads cleanly at a glance.
  final TextStyle tableCell;

  /// Table column headers. 12/w700, secondary color, slight tracking.
  final TextStyle tableHeader;

  /// Button labels. 14/w600.
  final TextStyle button;

  /// Numeric values in tables and KPI rows — tabular figures so columns
  /// of prices line up on the decimal point instead of shifting as digits
  /// change width.
  final TextStyle numeric;

  /// A price shown inline (product tile, cart line). 14/w700, tabular.
  final TextStyle price;

  /// The headline number on a KPI card. 26/w700, tabular.
  final TextStyle kpiValue;

  /// The order total in the POS cart and the keypad display. 28/w800,
  /// tabular — deliberately the largest text in the application, because
  /// it is the number the cashier and the customer both need to read.
  final TextStyle total;

  const AppTextStyles({
    required this.pageTitle,
    required this.pageSubtitle,
    required this.sectionTitle,
    required this.cardTitle,
    required this.body,
    required this.bodySecondary,
    required this.label,
    required this.tableCell,
    required this.tableHeader,
    required this.button,
    required this.numeric,
    required this.price,
    required this.kpiValue,
    required this.total,
  });

  factory AppTextStyles.from(AppColorScheme colors) {
    // Inter for prose: it is what the app already loaded, and its tall
    // x-height holds up at the small sizes a dense POS table needs.
    TextStyle base(double size, FontWeight weight, Color color,
            {double? height, double? spacing}) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: spacing,
        );

    // Tabular figures for anything the eye scans as a column of numbers.
    TextStyle numeric(double size, FontWeight weight, Color color) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return AppTextStyles(
      pageTitle: base(22, FontWeight.w700, colors.textPrimary, height: 1.25),
      pageSubtitle: base(13, FontWeight.w400, colors.textSecondary, height: 1.4),
      sectionTitle: base(16, FontWeight.w700, colors.textPrimary, height: 1.3),
      cardTitle: base(15, FontWeight.w600, colors.textPrimary, height: 1.3),
      body: base(14, FontWeight.w400, colors.textPrimary, height: 1.45),
      bodySecondary:
          base(13, FontWeight.w400, colors.textSecondary, height: 1.45),
      label: base(12, FontWeight.w600, colors.textSecondary, height: 1.3),
      tableCell: base(13.5, FontWeight.w500, colors.textPrimary, height: 1.3),
      tableHeader: base(12, FontWeight.w700, colors.textSecondary,
          height: 1.3, spacing: 0.3),
      button: base(14, FontWeight.w600, colors.textPrimary, height: 1.2),
      numeric: numeric(13.5, FontWeight.w600, colors.textPrimary),
      price: numeric(14, FontWeight.w700, colors.textPrimary),
      kpiValue: numeric(26, FontWeight.w700, colors.textPrimary),
      total: numeric(28, FontWeight.w800, colors.textPrimary),
    );
  }

  @override
  AppTextStyles copyWith({
    TextStyle? pageTitle,
    TextStyle? pageSubtitle,
    TextStyle? sectionTitle,
    TextStyle? cardTitle,
    TextStyle? body,
    TextStyle? bodySecondary,
    TextStyle? label,
    TextStyle? tableCell,
    TextStyle? tableHeader,
    TextStyle? button,
    TextStyle? numeric,
    TextStyle? price,
    TextStyle? kpiValue,
    TextStyle? total,
  }) {
    return AppTextStyles(
      pageTitle: pageTitle ?? this.pageTitle,
      pageSubtitle: pageSubtitle ?? this.pageSubtitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      cardTitle: cardTitle ?? this.cardTitle,
      body: body ?? this.body,
      bodySecondary: bodySecondary ?? this.bodySecondary,
      label: label ?? this.label,
      tableCell: tableCell ?? this.tableCell,
      tableHeader: tableHeader ?? this.tableHeader,
      button: button ?? this.button,
      numeric: numeric ?? this.numeric,
      price: price ?? this.price,
      kpiValue: kpiValue ?? this.kpiValue,
      total: total ?? this.total,
    );
  }

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTextStyles(
      pageTitle: l(pageTitle, other.pageTitle),
      pageSubtitle: l(pageSubtitle, other.pageSubtitle),
      sectionTitle: l(sectionTitle, other.sectionTitle),
      cardTitle: l(cardTitle, other.cardTitle),
      body: l(body, other.body),
      bodySecondary: l(bodySecondary, other.bodySecondary),
      label: l(label, other.label),
      tableCell: l(tableCell, other.tableCell),
      tableHeader: l(tableHeader, other.tableHeader),
      button: l(button, other.button),
      numeric: l(numeric, other.numeric),
      price: l(price, other.price),
      kpiValue: l(kpiValue, other.kpiValue),
      total: l(total, other.total),
    );
  }
}

/// `context.text.cardTitle` — the single way widgets should reach for a
/// text style. Falls back to a default-palette scale if the extension is
/// missing, so widgets rendered outside the app's theme still look right.
extension AppTextStylesX on BuildContext {
  AppTextStyles get text =>
      Theme.of(this).extension<AppTextStyles>() ?? _fallback(this);

  static AppTextStyles _fallback(BuildContext context) =>
      AppTextStyles.from(context.colors);
}
