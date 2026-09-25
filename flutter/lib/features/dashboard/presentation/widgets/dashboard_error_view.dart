import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';

/// Why this exists.
///
/// Every dashboard section used to render its failure state as
/// `error: (_, __) => Text('Impossible de charger le tableau de bord')`.
/// The error object was discarded at every single call site, so a dead
/// backend, a wrong `API_BASE_URL`, an expired token, a 403 and a genuine
/// 500 all produced the exact same sentence. That made the problem
/// undiagnosable from the UI — you could not tell whether the server was
/// down, the app was pointed at the wrong host, or a query had broken.
///
/// [DashboardErrorInfo.from] classifies the error instead, so the screen
/// says what actually went wrong and what to do about it. Note this is
/// the opposite of hiding the error: the generic sentence WAS the hiding.
class DashboardErrorInfo {
  /// Short headline, e.g. "Serveur injoignable".
  final String title;

  /// Actionable detail: the backend's own readable message, or — for a
  /// connection failure — the base URL that was actually attempted.
  final String? detail;

  final IconData icon;

  /// True when retrying is pointless until something changes outside the
  /// app (server down, wrong URL, missing permission). Used only to pick
  /// wording; the retry button is always offered.
  final bool needsOperatorAction;

  const DashboardErrorInfo({
    required this.title,
    required this.icon,
    this.detail,
    this.needsOperatorAction = false,
  });

  /// Classifies [error] into something worth showing a human.
  ///
  /// [t] is a translate function (`(key) => tr(ref, key)`), passed in so
  /// this stays a pure function and can be unit-tested without a
  /// WidgetRef.
  factory DashboardErrorInfo.from(Object? error, String Function(String) t) {
    if (error is! ApiException) {
      // Genuinely unexpected (parse bug, null deref, ...). Don't dump a
      // Dart stack trace on a shop owner, but don't pretend it's a
      // network problem either.
      return DashboardErrorInfo(
        title: t('dashboard.error_unexpected'),
        icon: Icons.error_outline_rounded,
      );
    }

    // Connection never reached the server. By far the most common cause
    // in the field, and the one the old message hid most damagingly —
    // showing the URL turns "it's broken" into "it's pointed at the
    // wrong machine" in one glance.
    if (error.code == 'NETWORK_ERROR') {
      return DashboardErrorInfo(
        title: t('dashboard.error_unreachable'),
        detail: '${t('dashboard.error_tried')}: ${ApiConfig.baseUrl}',
        icon: Icons.cloud_off_rounded,
        needsOperatorAction: true,
      );
    }

    if (error.statusCode == 401) {
      return DashboardErrorInfo(
        title: t('dashboard.error_session'),
        icon: Icons.lock_outline_rounded,
        needsOperatorAction: true,
      );
    }

    if (error.statusCode == 403) {
      return DashboardErrorInfo(
        title: t('dashboard.error_forbidden'),
        detail: error.message,
        icon: Icons.no_accounts_outlined,
        needsOperatorAction: true,
      );
    }

    // 4xx/5xx with a real envelope: the backend already wrote a readable
    // sentence (see apiResponse.js / errorHandler.js) — show it rather
    // than replacing it with a vaguer one of our own. The code/status is
    // appended because it's what makes a bug report actionable.
    return DashboardErrorInfo(
      title: error.message,
      detail: '${error.code}${error.statusCode != null ? ' · HTTP ${error.statusCode}' : ''}',
      icon: Icons.error_outline_rounded,
      needsOperatorAction: (error.statusCode ?? 0) >= 500,
    );
  }
}

/// Full-width failure state for a whole dashboard section.
class DashboardErrorView extends ConsumerWidget {
  final Object? error;
  final VoidCallback onRetry;

  const DashboardErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = DashboardErrorInfo.from(error, (key) => tr(ref, key));

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icon, color: AppColors.danger, size: 40),
            const SizedBox(height: 12),
            Text(
              info.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (info.detail != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                info.detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(tr(ref, 'dashboard.retry')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact failure state for an individual card (cashier ranking, recent
/// sales, ...), where a full-height error block would blow out the
/// card's layout. Same classification, less chrome.
class DashboardErrorInline extends ConsumerWidget {
  final Object? error;
  final VoidCallback? onRetry;

  const DashboardErrorInline({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = DashboardErrorInfo.from(error, (key) => tr(ref, key));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(info.icon, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                if (info.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    info.detail!,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null)
            IconButton(
              tooltip: tr(ref, 'dashboard.retry'),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: onRetry,
            ),
        ],
      ),
    );
  }
}
