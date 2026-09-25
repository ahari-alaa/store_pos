import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/app_color_scheme.dart';
import '../design/app_text_styles.dart';
import '../design/design_tokens.dart';
import 'app_palette.dart';

/// Builds the [ThemeData] used across the app from an [AppPalette].
///
/// Two things happen here that did not before:
///
/// 1. The design system is registered as theme extensions
///    ([AppColorScheme] and [AppTextStyles]), so `context.colors` and
///    `context.text` resolve on every screen. This is what makes the
///    Settings -> Apparence palettes — the Dark preset above all — apply
///    to card bodies, tables, badges and the POS panels, instead of only
///    to the chrome that happened to read `Theme.of(context)`.
///
/// 2. Every Material component this app actually uses is themed here
///    (inputs, buttons, dialogs, menus, tooltips, chips, snackbars,
///    scrollbars, progress indicators), at the sizes and radii from
///    [AppSizes] / [AppRadius]. Screens should not need to restate any of
///    it, which is what stops the eleven slightly-different button styles
///    from growing back.
///
/// Desktop-first (cashier workstations), but every value is density- and
/// size-based rather than platform-based, so the same theme scales to a
/// tablet without a second theme file.
class AppTheme {
  AppTheme._();

  /// Backward-compatible default. Identical look to the default palette.
  static ThemeData get light => build(AppPalettes.defaultPalette);

  static ThemeData build(AppPalette palette) {
    final colors = AppColorScheme.fromPalette(palette);
    final text = AppTextStyles.from(colors);
    final isDark = palette.brightness == Brightness.dark;

    final base = ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: palette.brightness,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        secondary: colors.secondary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: colors.danger,
      ),
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[colors, text],

      // The Material text theme is kept in sync with the design-system
      // scale so widgets that still read `Theme.of(context).textTheme`
      // (the screens not yet migrated) land on the same sizes and colors
      // instead of drifting from the migrated ones.
      textTheme: base.textTheme.copyWith(
        headlineSmall: text.pageTitle,
        titleLarge: text.pageTitle,
        titleMedium: text.cardTitle,
        titleSmall: text.label,
        bodyLarge: text.body,
        bodyMedium: text.bodySecondary,
        bodySmall: text.bodySecondary.copyWith(color: colors.textMuted),
        labelLarge: text.button,
        labelMedium: text.label,
      ),

      iconTheme: IconThemeData(color: colors.textSecondary, size: AppSizes.iconMd),
      primaryIconTheme:
          IconThemeData(color: colors.onPrimary, size: AppSizes.iconMd),

      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.pageTitle,
        iconTheme: IconThemeData(color: colors.textSecondary),
      ),

      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: colors.border),
        ),
        margin: EdgeInsets.zero,
      ),

      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),

      // --- Inputs ---------------------------------------------------
      // One fill, one radius, one padding, one focus treatment. The old
      // theme left errorBorder/disabledBorder unset, so an invalid or
      // disabled field silently fell back to Material defaults that did
      // not match anything else on screen.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceMuted,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: text.body.copyWith(color: colors.textMuted),
        labelStyle: text.label,
        floatingLabelStyle: text.label.copyWith(color: colors.primary),
        helperStyle: text.bodySecondary.copyWith(fontSize: 12),
        errorStyle: text.bodySecondary.copyWith(
          fontSize: 12,
          color: colors.danger,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: colors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: colors.danger, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.smAll,
          borderSide: BorderSide(color: colors.disabled),
        ),
      ),

      // --- Buttons --------------------------------------------------
      // These keep the legacy Material buttons on-system for screens not
      // yet migrated to AppButton, so the app never shows two visual
      // generations of button side by side during the migration.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.disabled,
          disabledForegroundColor: colors.onDisabled,
          elevation: 0,
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: text.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: text.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          disabledForegroundColor: colors.onDisabled,
          side: BorderSide(color: colors.border),
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: text.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.primary,
          disabledForegroundColor: colors.onDisabled,
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: text.button,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.textSecondary,
          minimumSize:
              const Size(AppSizes.iconButtonSize, AppSizes.iconButtonSize),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        ),
      ),

      // --- Overlays -------------------------------------------------
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: text.sectionTitle,
        contentTextStyle: text.body,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withOpacity(isDark ? 0.5 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: colors.border),
        ),
        textStyle: text.body,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.sm - 2,
        ),
        decoration: BoxDecoration(
          color: colors.textPrimary,
          borderRadius: AppRadius.xsAll,
        ),
        textStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.surface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.textPrimary,
        contentTextStyle: TextStyle(fontSize: 13.5, color: colors.surface),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),

      // --- Small controls -------------------------------------------
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.surfaceMuted,
        selectedColor: colors.primary,
        disabledColor: colors.disabled,
        labelStyle: text.label.copyWith(color: colors.textPrimary),
        secondaryLabelStyle: text.label.copyWith(color: colors.onPrimary),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(colors.onPrimary),
        side: BorderSide(color: colors.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.borderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(colors.borderStrong),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        radius: const Radius.circular(AppRadius.xs),
        thickness: const WidgetStatePropertyAll(8),
        crossAxisMargin: 2,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        titleTextStyle: text.body,
        subtitleTextStyle: text.bodySecondary,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: text.body,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
    );
  }
}
