import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../providers/reports_provider.dart';

/// Rapports §6: chiffre d'affaires / commandes / articles vendus / ticket
/// moyen for the selected period — the same [DashboardOverview] shape and
/// endpoint the Accueil dashboard's KPI cards already use (spec §25: the
/// backend, not this widget, computes these).
class ReportKpiRow extends ConsumerWidget {
  const ReportKpiRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(reportKpisProvider);

    return overviewAsync.when(
      loading: () => _grid(context, loading: true, overview: DashboardOverview.empty),
      error: (error, _) => DashboardErrorInline(
        error: error,
        onRetry: () => ref.invalidate(reportKpisProvider),
      ),
      data: (overview) => _grid(context, loading: false, overview: overview),
    );
  }

  Widget _grid(BuildContext context, {required bool loading, required DashboardOverview overview}) {
    return Consumer(
      builder: (context, ref, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 4 : (constraints.maxWidth >= 560 ? 2 : 1);
            final cards = [
              KpiCard(
                label: tr(ref, 'reports.kpi_revenue'),
                value: CurrencyFormatter.format(overview.totalRevenue),
                icon: Icons.payments_outlined,
                accent: context.colors.primary,
                loading: loading,
              ),
              KpiCard(
                label: tr(ref, 'reports.kpi_orders'),
                value: '${overview.saleCount}',
                icon: Icons.receipt_long_outlined,
                accent: context.colors.info,
                loading: loading,
              ),
              KpiCard(
                label: tr(ref, 'reports.kpi_items_sold'),
                value: '${overview.itemsSold}',
                icon: Icons.inventory_2_outlined,
                accent: context.colors.success,
                loading: loading,
              ),
              KpiCard(
                label: tr(ref, 'reports.kpi_average_sale'),
                value: CurrencyFormatter.format(overview.averageSale),
                icon: Icons.trending_up_rounded,
                accent: context.colors.warning,
                loading: loading,
              ),
            ];

            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.lg,
              crossAxisSpacing: AppSpacing.lg,
              childAspectRatio: columns == 1 ? 2.6 : 1.7,
              children: cards,
            );
          },
        );
      },
    );
  }
}
