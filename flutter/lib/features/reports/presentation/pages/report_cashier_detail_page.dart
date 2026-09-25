import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../../domain/entities/cashier_sales_report.dart';
import '../providers/reports_provider.dart';

/// Rapports §11 — one cashier's activity over the currently selected
/// period: summary, sales-by-day table, and payment breakdown. Reached
/// by tapping a row in [CashierPerformanceSection]; [fallback] (the
/// ranking row passed as `extra`) lets the header render immediately
/// while the full detail is still loading.
class ReportCashierDetailPage extends ConsumerWidget {
  final String cashierId;
  final CashierRankingEntry? fallback;

  const ReportCashierDetailPage({super.key, required this.cashierId, this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(reportCashierDetailProvider(cashierId));

    // No own Scaffold/AppBar: this route renders inside the shared
    // AppShell, which already supplies the top bar (with a back button —
    // see app_shell.dart's '/reports/cashiers/' chrome case) and the
    // cashier's name as its title via [fallback].
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            detailAsync.valueOrNull?.cashier?.name ?? fallback?.cashierName ?? '—',
            style: context.text.pageTitle,
          ),
          const SizedBox(height: AppSpacing.lg),
          detailAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: AppLoadingState(),
            ),
            error: (error, _) => DashboardErrorInline(
              error: error,
              onRetry: () => ref.invalidate(reportCashierDetailProvider(cashierId)),
            ),
            data: (report) => _CashierDetailBody(report: report),
          ),
        ],
      ),
    );
  }
}

class _CashierDetailBody extends StatelessWidget {
  final CashierSalesReport report;

  const _CashierDetailBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 4 : (constraints.maxWidth >= 560 ? 2 : 1);
            return Consumer(
              builder: (context, ref, _) => GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: AppSpacing.lg,
                crossAxisSpacing: AppSpacing.lg,
                childAspectRatio: columns == 1 ? 2.6 : 1.7,
                children: [
                  KpiCard(
                    label: tr(ref, 'reports.kpi_revenue'),
                    value: CurrencyFormatter.format(summary.totalSales),
                    icon: Icons.payments_outlined,
                    accent: context.colors.primary,
                  ),
                  KpiCard(
                    label: tr(ref, 'reports.kpi_orders'),
                    value: '${summary.orders}',
                    icon: Icons.receipt_long_outlined,
                    accent: context.colors.info,
                  ),
                  KpiCard(
                    label: tr(ref, 'reports.kpi_items_sold'),
                    value: '${summary.itemsSold}',
                    icon: Icons.inventory_2_outlined,
                    accent: context.colors.success,
                  ),
                  KpiCard(
                    label: tr(ref, 'reports.kpi_average_sale'),
                    value: CurrencyFormatter.format(summary.averageTicket),
                    icon: Icons.trending_up_rounded,
                    accent: context.colors.warning,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Consumer(
          builder: (context, ref, _) => AppSectionCard(
            title: tr(ref, 'reports.payment_breakdown'),
            child: report.paymentBreakdown.isEmpty
                ? AppEmptyState(
                    icon: Icons.pie_chart_outline_rounded,
                    title: tr(ref, 'reports.empty_title'),
                    message: tr(ref, 'reports.empty_message'),
                    compact: true,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in report.paymentBreakdown) ...[
                        Row(
                          children: [
                            Expanded(child: Text(entry.paymentMethod, style: context.text.body)),
                            Text('${entry.percent.toStringAsFixed(1)}%', style: context.text.bodySecondary),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              CurrencyFormatter.format(entry.amount),
                              style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Consumer(
          builder: (context, ref, _) => AppSectionCard(
            title: tr(ref, 'reports.sales_by_day'),
            bodyFlush: true,
            child: AppDataTable<CashierDailyBreakdown>(
              minWidth: 560,
              rows: report.days,
              emptyState: AppEmptyState(
                icon: Icons.calendar_today_outlined,
                title: tr(ref, 'reports.empty_title'),
                message: tr(ref, 'reports.empty_message'),
                compact: true,
              ),
              columns: [
                AppTableColumn<CashierDailyBreakdown>(
                  label: tr(ref, 'reports.column_date'),
                  cell: (context, row) => Text(DateFormat('dd/MM/yyyy').format(row.date)),
                  sortKey: (row) => row.date,
                ),
                AppTableColumn<CashierDailyBreakdown>(
                  label: tr(ref, 'reports.column_orders'),
                  align: AppColumnAlign.right,
                  cell: (context, row) => Text('${row.summary.orders}'),
                  sortKey: (row) => row.summary.orders,
                ),
                AppTableColumn<CashierDailyBreakdown>(
                  label: tr(ref, 'reports.column_items'),
                  align: AppColumnAlign.right,
                  cell: (context, row) => Text('${row.summary.itemsSold}'),
                  sortKey: (row) => row.summary.itemsSold,
                ),
                AppTableColumn<CashierDailyBreakdown>(
                  label: tr(ref, 'reports.column_revenue'),
                  align: AppColumnAlign.right,
                  flex: 3,
                  cell: (context, row) => Text(
                    CurrencyFormatter.format(row.summary.totalSales),
                    style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
                  ),
                  sortKey: (row) => row.summary.totalSales,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
