import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../providers/dashboard_provider.dart';
import 'dashboard_error_view.dart';

/// "Statut des ventes" / "حالة المبيعات" bar chart. Only shows the
/// statuses that actually exist on `sales.sale_status`
/// (COMPLETED / CANCELLED / REFUNDED — see migrations/001_init.sql) —
/// there is no "pending" sale_status in this schema, so unlike the
/// original mock, no such bar is invented here.
class SalesStatusChart extends ConsumerWidget {
  const SalesStatusChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(salesStatusProvider);
    final locale = ref.watch(localeProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr(ref, 'dashboard.sales_status'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 16),
            statusAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, _) => DashboardErrorInline(
                error: error,
                onRetry: () => ref.invalidate(salesStatusProvider),
              ),
              data: (entries) {
                final total = entries.fold<int>(0, (sum, e) => sum + e.count);
                if (total == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(tr(ref, 'dashboard.no_sales_period'),
                        style: const TextStyle(color: AppColors.textMuted)),
                  );
                }
                return Column(
                  children: entries
                      .map((e) => _StatusBar(
                            label: locale.name == 'ar' ? e.labelAr() : e.labelFr(),
                            count: e.count,
                            maxCount: entries.map((x) => x.count).reduce((a, b) => a > b ? a : b),
                            color: _colorFor(e.status),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(String status) {
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
}

class _StatusBar extends StatelessWidget {
  final String label;
  final int count;
  final int maxCount;
  final Color color;

  const _StatusBar({
    required this.label,
    required this.count,
    required this.maxCount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount == 0 ? 0.0 : count / maxCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(height: 14, color: AppColors.background),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 14,
                        width: constraints.maxWidth * ratio,
                        color: color,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
