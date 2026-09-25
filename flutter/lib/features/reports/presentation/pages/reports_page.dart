import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../../domain/entities/report_overview.dart';
import '../providers/reports_provider.dart';
import '../widgets/report_kpi_strip.dart';
import '../widgets/report_sections.dart';
import '../widgets/report_toolbar.dart';
import '../widgets/report_widgets.dart';
import '../widgets/revenue_orders_chart.dart';

/// Rapports — the manager's one-glance view of a period: six KPIs, the
/// revenue/sales chart, orders per hour, payments, best sellers, cashiers,
/// expenses, alerts and the latest sales.
///
/// Everything below is rendered from ONE [ReportOverview] (one request,
/// one snapshot, one period), and the PDF / Excel / Print buttons export
/// that very same object — so the page and its exports cannot disagree.
class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Every /reports/* endpoint requires 'reports.view' (admin/manager);
    // the sidebar already hides the entry, this is the defensive fallback
    // for a direct/deep link from a cashier session.
    final user = ref.watch(authProvider).user;
    if (user != null && !user.canViewReports) {
      return RestrictedPage(message: tr(ref, 'reports.restricted'));
    }

    final filter = ref.watch(reportFilterProvider);
    final async = ref.watch(reportOverviewProvider);
    final data = async.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thin progress line while a manual refresh is in flight; the old
        // numbers stay readable underneath.
        SizedBox(
          height: 2,
          child: (async.isLoading && data != null) ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ReportToolbar(),
                const SizedBox(height: AppSpacing.md),
                if (!filter.isReady)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(
                      child: Text(tr(ref, 'reports.pick_custom_range'), style: context.text.bodySecondary),
                    ),
                  )
                else if (data != null)
                  _Content(data: data)
                else if (async.hasError)
                  _LoadError(error: async.error)
                else
                  const _Loading(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Places [children] side by side when there is room (`minWidth`),
/// otherwise stacks them — never squeezes a table below a readable width.
class _ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final List<int> flex;
  final double minWidth;

  const _ResponsiveRow({required this.children, required this.flex, required this.minWidth});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              Expanded(flex: flex[i], child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

class _Content extends ConsumerWidget {
  final ReportOverview data;

  const _Content({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    const gap = SizedBox(height: AppSpacing.md);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!data.hasSales) ...[
          _Banner(
            icon: Icons.info_outline_rounded,
            color: colors.info,
            background: colors.infoSurface,
            message: tr(ref, 'reports.no_sales'),
          ),
          gap,
        ],
        if (!data.integrityOk) ...[
          _Banner(
            icon: Icons.warning_amber_rounded,
            color: colors.warning,
            background: colors.warningSurface,
            message: tr(ref, 'reports.integrity_warning'),
          ),
          gap,
        ],
        ReportKpiStrip(data: data),
        gap,
        _ResponsiveRow(
          minWidth: 900,
          flex: const [3, 2],
          children: [
            ReportPanel(
              title: tr(ref, 'reports.revenue_evolution'),
              height: ReportPanelHeights.chartRow,
              child: data.revenueSeries.hasData
                  ? RevenueOrdersChart(
                      series: data.revenueSeries,
                      revenueLabel: tr(ref, 'reports.column_revenue'),
                      salesLabel: tr(ref, 'reports.kpi_sales_count'),
                    )
                  : ReportEmpty(message: tr(ref, 'reports.no_sales'), icon: Icons.bar_chart_rounded),
            ),
            OrdersByHourPanel(data: data, height: ReportPanelHeights.chartRow),
          ],
        ),
        gap,
        _ResponsiveRow(
          minWidth: 1000,
          flex: const [1, 1, 1],
          children: [
            PaymentsPanel(data: data, height: ReportPanelHeights.tablesRow),
            TopProductsPanel(data: data, height: ReportPanelHeights.tablesRow),
            CashiersPanel(data: data, height: ReportPanelHeights.tablesRow),
          ],
        ),
        gap,
        _ResponsiveRow(
          minWidth: 700,
          flex: const [1, 1],
          children: [
            ExpensesPanel(data: data, height: ReportPanelHeights.lowerRow),
            StockAlertsPanel(data: data, height: ReportPanelHeights.lowerRow),
          ],
        ),
        gap,
        RecentSalesPanel(data: data),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String message;

  const _Banner({
    required this.icon,
    required this.color,
    required this.background,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSizes.iconMd, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: context.text.body.copyWith(fontSize: 13))),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: AppSpacing.md);
    Widget block(double height) => Container(
          height: height,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: context.colors.border),
          ),
          child: const Center(child: AppLoadingState()),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ReportKpiStrip(data: null),
        gap,
        block(ReportPanelHeights.chartRow),
        gap,
        block(ReportPanelHeights.tablesRow),
      ],
    );
  }
}

class _LoadError extends ConsumerWidget {
  final Object? error;

  const _LoadError({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = DashboardErrorInfo.from(error, (key) => tr(ref, key));
    final detail = info.detail == null ? info.title : '${info.title} — ${info.detail}';

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: context.colors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: AppErrorState(
        title: tr(ref, 'reports.error_title'),
        message: detail,
        retryLabel: tr(ref, 'reports.retry'),
        onRetry: () => ref.read(reportOverviewProvider.notifier).load(),
        compact: true,
      ),
    );
  }
}
