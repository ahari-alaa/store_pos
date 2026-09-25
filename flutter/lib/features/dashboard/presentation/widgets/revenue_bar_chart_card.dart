import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/dashboard_extras.dart';
import '../providers/dashboard_provider.dart';
import 'dashboard_error_view.dart';

/// Revenue bar chart with the Jour/Semaine/Mois toggle (spec: "Allow the
/// user to switch between Jour / Semaine / Mois"). Every bucket comes
/// from SQL aggregation (GROUP BY DATE/week-start/month — see
/// reportService.js#dashboardRevenueSeries), never raw sales rows.
class RevenueBarChartCard extends ConsumerWidget {
  const RevenueBarChartCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seriesAsync = ref.watch(revenueSeriesProvider);
    final granularity = ref.watch(revenueGranularityProvider);
    final locale = ref.watch(localeProvider);
    final primary = Theme.of(context).colorScheme.primary;

    String segLabel(RevenueGranularity g) =>
        locale.name == 'ar' ? g.labelAr() : g.labelFr();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr(ref, 'dashboard.revenue_chart_title'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                SegmentedButton<RevenueGranularity>(
                  segments: RevenueGranularity.values
                      .map((g) => ButtonSegment(value: g, label: Text(segLabel(g))))
                      .toList(),
                  selected: {granularity},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    ref.read(revenueGranularityProvider.notifier).state = selection.first;
                  },
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 220,
              child: seriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (error, _) => DashboardErrorInline(
                  error: error,
                  onRetry: () => ref.invalidate(revenueSeriesProvider),
                ),
                data: (buckets) {
                  if (buckets.isEmpty || buckets.every((b) => b.revenue == 0)) {
                    return Center(
                      child: Text(tr(ref, 'dashboard.no_sales_period'),
                          style: const TextStyle(color: AppColors.textMuted)),
                    );
                  }
                  return _RevenueBars(
                    buckets: buckets,
                    granularity: granularity,
                    color: primary,
                    locale: locale.name,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueBars extends StatelessWidget {
  final List<RevenueBucket> buckets;
  final RevenueGranularity granularity;
  final Color color;
  final String locale;

  const _RevenueBars({
    required this.buckets,
    required this.granularity,
    required this.color,
    required this.locale,
  });

  static const _weekdaysFr = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _weekdaysAr = ['إث', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح'];
  static const _monthsFr = [
    'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'
  ];
  static const _monthsAr = [
    'ينا', 'فبر', 'مار', 'أبر', 'ماي', 'يون', 'يول', 'أغس', 'سبت', 'أكت', 'نوف', 'ديس'
  ];

  String _labelFor(DateTime d) {
    final isAr = locale == 'ar';
    switch (granularity) {
      case RevenueGranularity.day:
        final idx = (d.weekday - 1) % 7; // Monday = 0
        return isAr ? _weekdaysAr[idx] : _weekdaysFr[idx];
      case RevenueGranularity.week:
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      case RevenueGranularity.month:
        final idx = (d.month - 1) % 12;
        return isAr ? _monthsAr[idx] : _monthsFr[idx];
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxValue = buckets.map((b) => b.revenue).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: buckets
                .map(
                  (b) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message: CurrencyFormatter.format(b.revenue),
                        child: FractionallySizedBox(
                          heightFactor: maxValue == 0 ? 0 : (b.revenue / maxValue).clamp(0.02, 1.0),
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: buckets
              .map(
                (b) => Expanded(
                  child: Text(
                    _labelFor(b.bucketStart),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
