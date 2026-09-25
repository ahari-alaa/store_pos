import 'package:flutter/widgets.dart';

/// Spacing scale for the whole application.
///
/// Every gap, padding and margin in the redesigned UI comes from here so
/// the product reads as one designed surface instead of a set of screens
/// each inventing its own 7px/13px/18px rhythm. The scale is a 4px grid,
/// which is what the icon sizes and control heights below are tuned to.
class AppSpacing {
  AppSpacing._();

  /// 4 — hairline gaps (icon to its own label, badge internals).
  static const double xs = 4;

  /// 8 — tight gaps inside a single control.
  static const double sm = 8;

  /// 12 — gap between related controls in a row.
  static const double md = 12;

  /// 16 — default padding inside cards, gap between list rows.
  static const double lg = 16;

  /// 24 — page gutter, gap between cards in a grid.
  static const double xl = 24;

  /// 32 — gap between major page sections.
  static const double xxl = 32;

  /// 48 — large vertical breathing room (empty states, auth screens).
  static const double xxxl = 48;

  /// Standard page gutter. Screens use this as their outer padding so
  /// content lines up across modules.
  static const EdgeInsets pagePadding = EdgeInsets.all(xl);

  /// Default padding inside a surface/card.
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);

  /// Horizontal-only page gutter, for screens that manage their own
  /// vertical rhythm (tables with sticky headers, for instance).
  static const EdgeInsets pageGutter = EdgeInsets.symmetric(horizontal: xl);
}

/// Corner radius scale. Four steps, deliberately: anything more and the
/// UI stops looking like one product.
class AppRadius {
  AppRadius._();

  /// 6 — chips, badges, small inline controls.
  static const double xs = 6;

  /// 10 — buttons, inputs, table cells, keypad keys.
  static const double sm = 10;

  /// 14 — cards, panels, list tiles.
  static const double md = 14;

  /// 20 — dialogs and modals.
  static const double lg = 20;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Fixed sizes for chrome and controls. Having these in one place is what
/// makes "every button is the same height" actually true, rather than
/// approximately true.
class AppSizes {
  AppSizes._();

  // --- Application shell ---
  /// Sidebar width when labels are shown.
  static const double sidebarWidth = 248;

  /// Sidebar width when collapsed to icons only (narrow windows).
  static const double sidebarCollapsedWidth = 72;

  /// Window width below which the sidebar collapses to icons. Chosen so a
  /// half-screen window on a 1920px monitor still shows full labels.
  static const double sidebarCollapseBreakpoint = 1180;

  /// Window width below which the POS cart panel narrows.
  static const double posCompactBreakpoint = 1340;

  static const double topBarHeight = 68;

  // --- Controls ---
  /// Primary/secondary button height. One value, everywhere.
  static const double buttonHeight = 44;

  /// Compact button height, for toolbars and table row actions.
  static const double buttonHeightSm = 36;

  /// Large button height, for the POS pay button and keypad confirm.
  static const double buttonHeightLg = 56;

  /// Text field height (content box; the theme's contentPadding matches).
  static const double inputHeight = 44;

  /// Square icon-button hit target.
  static const double iconButtonSize = 40;

  // --- Icons ---
  /// Inline with body text (badges, table cells, input affixes).
  static const double iconSm = 16;

  /// Default icon size: buttons, navigation, toolbars.
  static const double iconMd = 20;

  /// Section and card header icons.
  static const double iconLg = 24;

  /// Empty/error state illustrations.
  static const double iconXl = 40;

  // --- Tables ---
  static const double tableHeaderHeight = 44;
  static const double tableRowHeight = 56;

  // --- POS ---
  static const double cartPanelWidth = 380;
  static const double cartPanelWidthCompact = 320;
  static const double posCategoryRailWidth = 176;

  /// Target width of a product tile; the grid derives its column count
  /// from this so tiles never stretch or squash awkwardly.
  static const double productTileTarget = 200;
}

/// Animation durations. The rule for this application is: motion only
/// where it explains a state change. Nothing decorative.
class AppDurations {
  AppDurations._();

  /// Hover/press/selection feedback.
  static const Duration fast = Duration(milliseconds: 120);

  /// Panel and expansion transitions.
  static const Duration medium = Duration(milliseconds: 200);
}
