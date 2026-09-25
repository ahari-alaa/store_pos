/// The Store POS design system.
///
/// A single import gives a widget the whole vocabulary it should need:
///
/// ```dart
/// import '../../../../core/design/design_system.dart';
///
/// Container(
///   padding: const EdgeInsets.all(AppSpacing.lg),
///   decoration: BoxDecoration(
///     color: context.colors.surface,
///     borderRadius: AppRadius.mdAll,
///     border: Border.all(color: context.colors.border),
///   ),
///   child: Text('Produits', style: context.text.cardTitle),
/// )
/// ```
///
/// Rules this system exists to enforce:
///   * colors come from `context.colors`, never from a literal or a
///     static const, so every palette and dark mode work everywhere;
///   * sizes come from [AppSpacing] / [AppRadius] / [AppSizes], so
///     spacing and control heights are consistent by construction;
///   * text comes from `context.text`, which has named roles instead of
///     arbitrary font sizes.
library;

export 'app_color_scheme.dart';
export 'app_shadows.dart';
export 'app_text_styles.dart';
export 'design_tokens.dart';
