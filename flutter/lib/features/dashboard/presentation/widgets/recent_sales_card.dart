import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../providers/dashboard_provider.dart';
import 'dashboard_error_view.dart';

/// "Ventes récentes" / "المبيعات الأخيرة" — real recent transactions
/// (GET /reports/dashboard-recent-sales), with a "Voir tout" button that
/// opens the existing Sales/history page (spec §F) instead of duplicating
/// it here.
class RecentSalesCard extends ConsumerWidget {
  const RecentSalesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(recentSalesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr(ref, 'dashboard.recent_sales'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                TextButton(
                  onPressed: () => context.go('/sales'),
                  child: Text(tr(ref, 'dashboard.see_all')),
                ),
              ],
            ),
            salesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, _) => DashboardErrorInline(
                error: error,
                onRetry: () => ref.invalidate(recentSalesProvider),
              ),
              data: (sales) {
                if (sales.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(tr(ref, 'dashboard.no_recent_sales'),
                        style: const TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(
                  children: sales.map((s) => _RecentSaleRow(sale: s)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentSaleRow extends ConsumerWidget {
  final RecentSale sale;

  const _RecentSaleRow({required this.sale});

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.danger;
      case 'REFUNDED':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  String _statusLabel(WidgetRef ref, String status) {
    switch (status) {
      case 'COMPLETED':
        return tr(ref, 'status.completed');
      case 'CANCELLED':
        return tr(ref, 'status.cancelled');
      case 'REFUNDED':
        return tr(ref, 'status.refunded');
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(sale.saleStatus);
    final date = sale.occurredAt;
    final dateLabel = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sale.reference,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(sale.cashierName,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            child: Text(dateLabel,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          Expanded(
            child: Text(sale.paymentMethod ?? '—',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
          SizedBox(
            width: 78,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _statusLabel(ref, sale.saleStatus),
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              CurrencyFormatter.format(sale.total),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
