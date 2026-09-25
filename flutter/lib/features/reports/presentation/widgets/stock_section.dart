import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../../domain/entities/reports_models.dart';
import '../providers/reports_provider.dart';

/// "État du stock" (spec §14) — products AND ingredients that are low or
/// out of stock. Severity badges are computed from the actual quantity
/// vs. the actual minimum (via [StatusBadge.stock]), never from a
/// negative quantity presented as normal (spec: "Do not allow negative
/// stock to be presented as a normal situation" — [StatusBadge.stock]
/// already treats <= 0 as rupture unconditionally).
class StockSection extends ConsumerWidget {
  const StockSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(reportStockProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.stock'),
      action: stockAsync.maybeWhen(
        data: (report) => Text(
          '${report.outOfStockCount + report.lowStockCount}',
          style: context.text.cardTitle,
        ),
        orElse: () => null,
      ),
      child: stockAsync.when(
        loading: () => const AppTableSkeleton(rows: 4, columns: 3),
        error: (error, _) => DashboardErrorInline(
          error: error,
          onRetry: () => ref.invalidate(reportStockProvider),
        ),
        data: (report) {
          final items = [...report.products, ...report.ingredients]
            ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
          if (items.isEmpty) {
            return AppEmptyState(
              icon: Icons.inventory_2_outlined,
              title: tr(ref, 'reports.stock_ok_title'),
              message: tr(ref, 'reports.stock_ok_message'),
              compact: true,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) ...[
                _StockRow(item: item),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final StockItemEntry item;

  const _StockRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: context.text.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (item.secondaryLabel != null && item.secondaryLabel!.isNotEmpty)
                  Text(item.secondaryLabel!, style: context.text.bodySecondary),
              ],
            ),
          ),
          Text(
            '${item.stockQuantity.toStringAsFixed(item.stockQuantity == item.stockQuantity.roundToDouble() ? 0 : 2)}',
            style: context.text.tableCell,
          ),
          const SizedBox(width: AppSpacing.md),
          StatusBadge.stock(
            quantity: item.stockQuantity,
            minimum: item.minimum,
            inStockLabel: tr(ref, 'stock.in_stock'),
            lowStockLabel: tr(ref, 'stock.low_stock'),
            outOfStockLabel: tr(ref, 'stock.out_of_stock'),
            size: StatusBadgeSize.small,
          ),
        ],
      ),
    );
  }
}
