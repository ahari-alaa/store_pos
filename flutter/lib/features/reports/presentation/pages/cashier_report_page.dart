import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sales/presentation/utils/order_actions.dart';
import '../../../sales/presentation/widgets/my_order_card.dart';
import '../../../settlements/presentation/widgets/settlement_section.dart';
import '../../domain/entities/my_report.dart';
import '../../domain/entities/report_period.dart';
import '../providers/my_report_provider.dart';
import '../utils/cashier_report_printer.dart';
import '../widgets/report_widgets.dart';

/// "Rapport" — the CASHIER's personal report. It answers one question: what
/// did THIS cashier sell?
///
/// Deliberately not the admin Rapports screen: no store-wide figures, no
/// other cashiers, no expenses. Every number comes from `/reports/my-sales`,
/// which the server computes for the signed-in cashier (the client never
/// names one), so the quantities here are this cashier's only — if A sold 20
/// coffees and B sold 50, A sees 20.
///
/// It also hosts the operational queue: "Commandes à servir" (IMPRIMER /
/// SERVIR) and "Commandes servies" (RÉIMPRIMER).
class CashierReportPage extends ConsumerStatefulWidget {
  const CashierReportPage({super.key});

  @override
  ConsumerState<CashierReportPage> createState() => _CashierReportPageState();
}

class _CashierReportPageState extends ConsumerState<CashierReportPage> {
  bool _printing = false;

  static const _periods = [
    ReportPeriod.today,
    ReportPeriod.yesterday,
    ReportPeriod.week,
    ReportPeriod.month,
    ReportPeriod.custom,
  ];

  void _refresh() {
    ref.invalidate(myReportProvider);
    ref.invalidate(myToServeProvider);
    ref.invalidate(myServedProvider);
  }

  Future<void> _pickRange() async {
    final filter = ref.read(myReportFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (filter.customFrom != null && filter.customTo != null)
        ? DateTimeRange(start: filter.customFrom!, end: filter.customTo!)
        : DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: today,
      initialDateRange: initial,
    );
    if (picked == null || !mounted) return;
    ref.read(myReportFilterProvider.notifier).state =
        filter.copyWithCustomRange(picked.start, picked.end);
  }

  void _selectPeriod(ReportPeriod period) {
    final filter = ref.read(myReportFilterProvider);
    if (period == ReportPeriod.custom) {
      // Keep any range already picked; otherwise ask for one straight away.
      if (filter.customFrom != null && filter.customTo != null) {
        ref.read(myReportFilterProvider.notifier).state = filter.copyWithPeriod(period);
      } else {
        _pickRange();
      }
      return;
    }
    ref.read(myReportFilterProvider.notifier).state = filter.copyWithPeriod(period);
  }

  /// IMPRIMER LE RAPPORT — prints this cashier's report for the selected
  /// period. (Printing an ORDER is a different action, on the order cards.)
  Future<void> _printReport() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final printed = await CashierReportPrinter.print(ref);
      if (!mounted) return;
      if (printed != null && printed.ordersTruncated) {
        showAppToast(
          context,
          message: trRead(ref, 'mine.report_truncated'),
          kind: AppToastKind.info,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: e.code == 'NETWORK_ERROR' ? trRead(ref, 'mine.msg_offline') : e.message,
        kind: AppToastKind.error,
      );
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, message: trRead(ref, 'mine.report_failed'), kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  String _periodLabel(ReportDateFilter filter, {required bool isAr}) {
    if (filter.period == ReportPeriod.custom) {
      if (filter.customFrom != null && filter.customTo != null) {
        return '${ReportFormat.date(filter.customFrom!)}  →  ${ReportFormat.date(filter.customTo!)}';
      }
      return tr(ref, 'mine.period_custom');
    }
    return isAr ? filter.period.labelAr() : filter.period.labelFr();
  }

  @override
  Widget build(BuildContext context) {
    // Backend enforces this too (reports.view_own is a cashier permission);
    // this is the fallback for a direct navigation from another role.
    final user = ref.watch(authProvider).user;
    if (user != null && !user.isCashier) {
      return RestrictedPage(message: tr(ref, 'mine.restricted'));
    }

    final text = context.text;
    final isAr = ref.watch(localeProvider).name == 'ar';
    final filter = ref.watch(myReportFilterProvider);
    final async = ref.watch(myReportProvider);
    final data = async.valueOrNull;

    // While a different period is loading, the previous period's numbers must
    // not sit under the new label.
    final stale = data != null && filter.isReady && data.periodKey != filter.period.apiValue;
    final report = stale ? null : data;
    final busyLoading = async.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 2,
          child: (busyLoading && report != null) ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Header: title, "Ahmed • Aujourd'hui", print ----
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(ref, 'mine.title'), style: text.pageTitle),
                          const SizedBox(height: 2),
                          Text(
                            '${user?.name ?? ''} • ${_periodLabel(filter, isAr: isAr)}',
                            style: text.bodySecondary,
                          ),
                        ],
                      ),
                    ),
                    AppButton.outline(
                      label: tr(ref, 'reports.refresh'),
                      icon: Icons.refresh_rounded,
                      onPressed: _refresh,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton.primary(
                      label: tr(ref, 'mine.print_report'),
                      icon: Icons.print_rounded,
                      loading: _printing,
                      onPressed: filter.isReady ? _printReport : null,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ---- Period selector ----
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final p in _periods)
                      ChoiceChip(
                        label: Text(
                          p == ReportPeriod.custom
                              ? tr(ref, 'mine.period_custom')
                              : (isAr ? p.labelAr() : p.labelFr()),
                        ),
                        selected: filter.period == p,
                        onSelected: (_) => _selectPeriod(p),
                      ),
                    if (filter.period == ReportPeriod.custom && filter.isReady)
                      TextButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                        label: Text(tr(ref, 'reports.change_dates')),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                if (!filter.isReady)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(
                      child: Text(tr(ref, 'reports.pick_custom_range'), style: text.bodySecondary),
                    ),
                  )
                else if (report != null)
                  _Kpis(report: report)
                else if (async.hasError)
                  AppErrorState(
                    title: tr(ref, 'mine.load_error'),
                    message: async.error is ApiException
                        ? (async.error as ApiException).message
                        : tr(ref, 'mine.load_error'),
                    retryLabel: tr(ref, 'reports.retry'),
                    onRetry: _refresh,
                  )
                else
                  const _KpisSkeleton(),

                if (filter.isReady && report != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _ProductsSold(report: report),
                ],

                // ---- Justificatif de travail (cashier work-payment
                // settlement — spec §1-§21). Never date-filtered by the
                // period picker above: "commandes disponibles" and "déjà
                // justifiées" mean every eligible/settled order, exactly
                // like the "à servir" queue below is never period-bound.
                const SizedBox(height: AppSpacing.lg),
                const SettlementSection(),

                // ---- Operational queue ----
                if (filter.isReady) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const _ToServeSection(),
                  const SizedBox(height: AppSpacing.lg),
                  const _ServedSection(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// KPIs
// ---------------------------------------------------------------------------

String _plural(WidgetRef ref, int n, String oneKey, String manyKey) =>
    tr(ref, n == 1 ? oneKey : manyKey);

class _Kpis extends ConsumerWidget {
  final MyReport report;

  const _Kpis({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = report.kpis;
    final cards = <Widget>[
      KpiCard(
        label: tr(ref, 'mine.kpi_sales'),
        value: ReportFormat.money(k.revenue),
        icon: Icons.payments_outlined,
        accent: context.colors.success,
      ),
      KpiCard(
        label: tr(ref, 'mine.kpi_orders'),
        value:
            '${ReportFormat.integer(k.orderCount)} ${_plural(ref, k.orderCount, 'mine.unit_order_one', 'mine.unit_order_many')}',
        icon: Icons.receipt_long_outlined,
      ),
      KpiCard(
        label: tr(ref, 'mine.kpi_items'),
        value:
            '${ReportFormat.integer(k.itemsSold)} ${_plural(ref, k.itemsSold, 'mine.unit_item_one', 'mine.unit_item_many')}',
        icon: Icons.shopping_bag_outlined,
      ),
      KpiCard(
        label: tr(ref, 'mine.kpi_average'),
        value: ReportFormat.money(k.averageTicket),
        icon: Icons.analytics_outlined,
      ),
    ];
    return _KpiGrid(children: cards);
  }
}

class _KpisSkeleton extends StatelessWidget {
  const _KpisSkeleton();

  @override
  Widget build(BuildContext context) {
    return _KpiGrid(
      children: List.generate(4, (_) => const KpiCard(label: '', value: '', icon: Icons.circle, loading: true)),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final List<Widget> children;

  const _KpiGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in children) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Products sold by THIS cashier
// ---------------------------------------------------------------------------

class _ProductsSold extends ConsumerWidget {
  final MyReport report;

  const _ProductsSold({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = context.text;
    final head = text.label.copyWith(color: colors.textSecondary);

    return AppSectionCard(
      title: tr(ref, 'mine.products_title'),
      subtitle: tr(ref, 'mine.products_subtitle'),
      icon: Icons.inventory_2_outlined,
      child: report.products.isEmpty
          ? AppEmptyState(
              compact: true,
              icon: Icons.inventory_2_outlined,
              title: tr(ref, 'mine.products_empty'),
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(flex: 5, child: Text(tr(ref, 'mine.col_product'), style: head)),
                    Expanded(
                      flex: 2,
                      child: Text(tr(ref, 'mine.col_quantity'), textAlign: TextAlign.end, style: head),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(tr(ref, 'mine.col_revenue'), textAlign: TextAlign.end, style: head),
                    ),
                  ],
                ),
                Divider(height: AppSpacing.lg, color: colors.border),
                for (final p in report.products)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.body),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            ReportFormat.integer(p.quantity),
                            textAlign: TextAlign.end,
                            style: text.body.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(ReportFormat.money(p.revenue), textAlign: TextAlign.end, style: text.body),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// À servir / Servies
// ---------------------------------------------------------------------------

class _ToServeSection extends ConsumerWidget {
  const _ToServeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myToServeProvider);
    final orders = async.valueOrNull;

    return AppSectionCard(
      title: tr(ref, 'mine.to_serve_title'),
      subtitle: orders == null || orders.isEmpty
          ? tr(ref, 'mine.to_serve_subtitle')
          : '${orders.length} ${tr(ref, 'mine.pending')}',
      icon: Icons.pending_actions_rounded,
      child: _OrderList(
        async: async,
        emptyText: tr(ref, 'mine.to_serve_empty'),
        emptyIcon: Icons.check_circle_outline_rounded,
        onRetry: () => ref.invalidate(myToServeProvider),
        cardBuilder: (order) => MyOrderCard(
          key: ValueKey('to-serve-${order.id}'),
          order: order,
          // The PAGE's context, not the card's: the card disappears as soon
          // as the order is served, the toast must outlive it.
          onServe: () => OrderActions.serve(context, ref, order),
        ),
      ),
    );
  }
}

class _ServedSection extends ConsumerWidget {
  const _ServedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myServedProvider);

    return AppSectionCard(
      title: tr(ref, 'mine.served_title'),
      subtitle: tr(ref, 'mine.served_subtitle'),
      icon: Icons.task_alt_rounded,
      child: _OrderList(
        async: async,
        emptyText: tr(ref, 'mine.served_empty'),
        emptyIcon: Icons.inbox_outlined,
        onRetry: () => ref.invalidate(myServedProvider),
        cardBuilder: (order) => MyOrderCard(
          key: ValueKey('served-${order.id}'),
          order: order,
          onReprint: () => OrderActions.reprint(context, ref, order),
        ),
      ),
    );
  }
}

class _OrderList extends ConsumerWidget {
  final AsyncValue<List<MyOrder>> async;
  final String emptyText;
  final IconData emptyIcon;
  final VoidCallback onRetry;
  final Widget Function(MyOrder order) cardBuilder;

  const _OrderList({
    required this.async,
    required this.emptyText,
    required this.emptyIcon,
    required this.onRetry,
    required this.cardBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = async.valueOrNull;

    if (orders != null) {
      if (orders.isEmpty) {
        return AppEmptyState(compact: true, icon: emptyIcon, title: emptyText);
      }
      return MyOrderGrid(children: [for (final o in orders) cardBuilder(o)]);
    }
    if (async.hasError) {
      return AppErrorState(
        compact: true,
        title: tr(ref, 'mine.load_error'),
        message: async.error is ApiException
            ? (async.error as ApiException).message
            : tr(ref, 'mine.load_error'),
        retryLabel: tr(ref, 'reports.retry'),
        onRetry: onRetry,
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}
