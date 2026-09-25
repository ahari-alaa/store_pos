import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../providers/dashboard_provider.dart';
import 'dashboard_error_view.dart';

/// "Meilleur caissier" / "أفضل أمين صندوق" — ranks every cashier with at
/// least one completed sale in the selected period, built entirely from
/// GET /reports/dashboard-cashiers (never hard-codes a name).
class CashierRankingCard extends ConsumerWidget {
  const CashierRankingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(cashierRankingProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(ref, 'dashboard.best_cashier'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            rankingAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, _) => DashboardErrorInline(
                error: error,
                onRetry: () => ref.invalidate(cashierRankingProvider),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(tr(ref, 'dashboard.no_cashiers'),
                        style: const TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < entries.length; i++)
                      _CashierRow(
                        rank: i + 1,
                        entry: entries[i],
                        isBest: i == 0,
                        highlightColor: theme.colorScheme.primary,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CashierRow extends ConsumerWidget {
  final int rank;
  final CashierRankingEntry entry;
  final bool isBest;
  final Color highlightColor;

  const _CashierRow({
    required this.rank,
    required this.entry,
    required this.isBest,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isBest ? highlightColor.withOpacity(0.14) : AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: isBest ? highlightColor : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.cashierName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  '${entry.saleCount} vente(s) • ${entry.itemsSold} ${tr(ref, 'dashboard.items_sold_suffix')} • moy. ${CurrencyFormatter.format(entry.averageSale)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            CurrencyFormatter.format(entry.totalSales),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: isBest ? highlightColor : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
