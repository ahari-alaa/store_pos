import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shown instead of a management page when the signed-in user's role
/// doesn't have permission for it (mirrors the server-side check in
/// store_pos_backend/src/middleware/authorize.js — the API would reject
/// these calls anyway, so the UI says so plainly instead of showing a
/// broken screen full of failed requests).
class RestrictedPage extends StatelessWidget {
  final String message;

  const RestrictedPage({
    super.key,
    this.message = "You don't have permission to view this page.",
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 32, color: AppColors.danger),
            ),
            const SizedBox(height: 20),
            Text('Restricted', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
