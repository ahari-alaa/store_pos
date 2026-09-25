import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../domain/entities/report_overview.dart';
import 'report_widgets.dart';

/// The six headline figures: CA, number of sales, items sold, average
/// ticket, expenses, estimated result. Compact tiles (one row on a wide
/// desktop, 3 x 2 on a narrower window); colour is only used where it
/// carries meaning — the result turns red when negative.
class ReportKpiStrip extends ConsumerWidget {
  /// Null while loading (tiles show a skeleton).
  final ReportOverview? data;

  const ReportKpiStrip({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final k = data?.kpis;

    final tiles = <_KpiTile>[
      _KpiTile(
        label: tr(ref, 'reports.kpi_revenue'),
        value: k == null ? null : ReportFormat.money(k.revenue),
        icon: Icons.payments_outlined,
        accent: colors.primary,
      ),
      _KpiTile(
        label: tr(ref, 'reports.kpi_sales_count'),
        value: k == null ? null : ReportFormat.integer(k.saleCount),
        icon: Icons.receipt_long_outlined,
        accent: colors.primary,
      ),
      _KpiTile(
        label: tr(ref, 'reports.kpi_items_sold'),
        value: k == null ? null : ReportFormat.integer(k.itemsSold),
        icon: Icons.inventory_2_outlined,
        accent: colors.primary,
      ),
      _KpiTile(
        label: tr(ref, 'reports.kpi_average_sale'),
        value: k == null ? null : ReportFormat.money(k.averageTicket),
        icon: Icons.trending_up_rounded,
        accent: colors.primary,
      ),
      _KpiTile(
        label: tr(ref, 'reports.kpi_expenses'),
        value: k == null ? null : ReportFormat.money(k.expenses),
        icon: Icons.account_balance_wallet_outlined,
        accent: colors.textSecondary,
      ),
      _KpiTile(
        label: tr(ref, 'reports.kpi_result'),
        value: k == null ? null : ReportFormat.money(k.estimatedResult),
        icon: Icons.savings_outlined,
        accent: (k != null && k.estimatedResult < 0) ? colors.danger : colors.success,
        valueColor: (k != null && k.estimatedResult < 0) ? colors.danger : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000 ? 6 : (width >= 640 ? 3 : 2);
        const gap = AppSpacing.md;
        final tileWidth = (width - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, height: 76, child: tile),
          ],
        );
      },
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final Color accent;
  final Color? valueColor;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Color.alphaBlend(accent.withOpacity(0.12), colors.surface),
              borderRadius: AppRadius.xsAll,
            ),
            child: Icon(icon, size: AppSizes.iconMd, color: accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.label.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 3),
                if (value == null)
                  const AppSkeleton(width: 80, height: 18)
                else
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value!,
                      maxLines: 1,
                      style: text.kpiValue.copyWith(fontSize: 19, color: valueColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
