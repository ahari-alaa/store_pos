import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shown briefly at startup while [AuthNotifier] checks secure storage for
/// an existing session. The router redirects away from here as soon as
/// auth status resolves to authenticated or unauthenticated.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, color: AppColors.primary, size: 40),
            SizedBox(height: 16),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
