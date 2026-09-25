import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Icon/color styling for each category id. Lives in the presentation
/// layer on purpose — the domain [ProductCategory] entity stays pure Dart.
/// Falls back to a neutral style for any category id it doesn't recognize
/// (e.g. once real categories come from the database).
class CategoryStyle {
  final IconData icon;
  final Color color;

  const CategoryStyle(this.icon, this.color);

  static const Map<String, CategoryStyle> _styles = {
    'all': CategoryStyle(Icons.apps_rounded, AppColors.textPrimary),
    'drinks': CategoryStyle(Icons.local_drink_rounded, AppColors.accentBlue),
    'food': CategoryStyle(Icons.restaurant_rounded, AppColors.accentOrange),
    'snacks': CategoryStyle(Icons.cookie_rounded, AppColors.accentPurple),
    'hygiene': CategoryStyle(Icons.soap_rounded, AppColors.accentTeal),
    'household': CategoryStyle(Icons.home_rounded, AppColors.primary),
    'others': CategoryStyle(Icons.category_rounded, AppColors.textSecondary),
  };

  static CategoryStyle of(String categoryId) {
    return _styles[categoryId] ??
        const CategoryStyle(Icons.category_rounded, AppColors.textSecondary);
  }
}
