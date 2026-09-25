import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../reports/presentation/widgets/report_widgets.dart';
import '../../domain/entities/settlement.dart';
import '../providers/settlement_controller.dart';
import '../providers/settlement_provider.dart';

/// "Justificatif de travail" — the settlement part of the cashier's
/// Rapport screen (spec §4/§18/§28): the KPI header, the selectable
/// "commandes à justifier" list with IMPRIMER LE JUSTIFICATIF, and the
/// read-only "commandes déjà justifiées" history.
///
/// Deliberately separate from the "à servir / servies" serving queue
/// above it on the same page (see CashierReportPage) — this answers "how
/// many orders has the manager not paid me for yet", never "has this
/// order been printed/handed to the customer".
class SettlementSection extends StatelessWidget {
  const SettlementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettlementKpis(),
        SizedBox(height: AppSpacing.lg),
        _EligibleOrdersCard(),
        SizedBox(height: AppSpacing.lg),
        _JustifiedHistoryCard(),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// KPIs
// ---------------------------------------------------------------------

class _SettlementKpis extends ConsumerWidget {
  const _SettlementKpis();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settlementSummaryProvider);
    final s = async.valueOrNull ?? SettlementSummary.zero;
    final loading = async.isLoading && async.valueOrNull == null;

    final cards = <Widget>[
      KpiCard(
        label: tr(ref, 'settlements.kpi_available'),
        value: ReportFormat.integer(s.ordersAvailable),
        icon: Icons.fact_check_outlined,
        loading: loading,
      ),
      KpiCard(
        label: tr(ref, 'settlements.kpi_justified'),
        value: ReportFormat.integer(s.ordersJustified),
        icon: Icons.verified_outlined,
        loading: loading,
      ),
      KpiCard(
        label: tr(ref, 'settlements.kpi_to_pay'),
        value: ReportFormat.money(s.toPay),
        icon: Icons.hourglass_bottom_rounded,
        accent: context.colors.warning,
        loading: loading,
      ),
      KpiCard(
        label: tr(ref, 'settlements.kpi_already_paid'),
        value: ReportFormat.money(s.alreadyPaid),
        icon: Icons.payments_outlined,
        accent: context.colors.success,
        loading: loading,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final columns = constraints.maxWidth >= 900 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final c in cards) SizedBox(width: width, child: c)],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Commandes à justifier — checkboxes + IMPRIMER LE JUSTIFICATIF
// ---------------------------------------------------------------------

class _EligibleOrdersCard extends ConsumerStatefulWidget {
  const _EligibleOrdersCard();

  @override
  ConsumerState<_EligibleOrdersCard> createState() => _EligibleOrdersCardState();
}

class _EligibleOrdersCardState extends ConsumerState<_EligibleOrdersCard> {
  bool _printing = false;

  Future<void> _print(List<String> ids) async {
    if (_printing) return;
    setState(() => _printing = true);
    SettlementCreateResult result;
    try {
      result = await ref.read(settlementControllerProvider).createAndPrint(ids);
    } catch (_) {
      result = const SettlementCreateResult(SettlementCreateOutcome.failed);
    }
    if (!mounted) return;
    setState(() => _printing = false);

    switch (result.outcome) {
      case SettlementCreateOutcome.created:
        showAppToast(
          context,
          message: tr(ref, 'settlements.msg_created').replaceAll(
            '{number}',
            result.settlement?.settlementNumber ?? '',
          ),
          kind: AppToastKind.success,
        );
      case SettlementCreateOutcome.createdPrintFailed:
        showAppToast(
          context,
          message: tr(ref, 'settlements.msg_created_print_failed').replaceAll(
            '{number}',
            result.settlement?.settlementNumber ?? '',
          ),
          kind: AppToastKind.warning,
        );
      case SettlementCreateOutcome.noSelection:
        showAppToast(context, message: tr(ref, 'settlements.msg_no_selection'), kind: AppToastKind.warning);
      case SettlementCreateOutcome.rejected:
        showAppToast(
          context,
          message: result.message ?? tr(ref, 'settlements.msg_rejected'),
          kind: AppToastKind.error,
        );
      case SettlementCreateOutcome.failed:
        showAppToast(context, message: tr(ref, 'settlements.msg_offline'), kind: AppToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = context.text;
    final async = ref.watch(eligibleOrdersProvider);
    final selected = ref.watch(selectedOrderIdsProvider);
    final data = async.valueOrNull;

    return AppSectionCard(
      title: tr(ref, 'settlements.eligible_title'),
      subtitle: data == null
          ? tr(ref, 'settlements.eligible_subtitle')
          : '${data.count} ${tr(ref, 'settlements.eligible_subtitle')}',
      icon: Icons.checklist_rounded,
      action: data != null && data.items.isNotEmpty
          ? TextButton(
              onPressed: () {
                final allIds = data.items.map((o) => o.id).toSet();
                final allSelected = selected.length == allIds.length && allIds.every(selected.contains);
                ref.read(selectedOrderIdsProvider.notifier).state = allSelected ? <String>{} : allIds;
              },
              child: Text(tr(ref, 'settlements.select_all')),
            )
          : null,
      child: Builder(builder: (context) {
        if (data != null) {
          if (data.items.isEmpty) {
            return AppEmptyState(
              compact: true,
              icon: Icons.check_circle_outline_rounded,
              title: tr(ref, 'settlements.eligible_empty'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final o in data.items)
                _EligibleOrderRow(
                  order: o,
                  checked: selected.contains(o.id),
                  onChanged: (v) {
                    final next = {...selected};
                    v ? next.add(o.id) : next.remove(o.id);
                    ref.read(selectedOrderIdsProvider.notifier).state = next;
                  },
                ),
              Divider(height: AppSpacing.lg, color: colors.border),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.length} ${tr(ref, 'settlements.selected_count')}',
                      style: text.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  AppButton.primary(
                    label: tr(ref, 'settlements.print_justificatif'),
                    icon: Icons.print_rounded,
                    loading: _printing,
                    onPressed: selected.isEmpty ? null : () => _print(selected.toList()),
                  ),
                ],
              ),
            ],
          );
        }
        if (async.hasError) {
          return AppErrorState(
            compact: true,
            title: tr(ref, 'settlements.load_error'),
            message: async.error is ApiException
                ? (async.error as ApiException).message
                : tr(ref, 'settlements.load_error'),
            retryLabel: tr(ref, 'reports.retry'),
            onRetry: () => ref.invalidate(eligibleOrdersProvider),
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      }),
    );
  }
}

class _EligibleOrderRow extends StatelessWidget {
  final SettlementOrder order;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _EligibleOrderRow({required this.order, required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: checked, onChanged: (v) => onChanged(v ?? false)),
            Expanded(
              flex: 2,
              child: Text('#${order.receiptNumber}', style: text.body.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(flex: 3, child: Text(ReportFormat.dateTime(order.occurredAt), style: text.bodySecondary)),
            Expanded(
              flex: 2,
              child: Text(ReportFormat.money(order.total), textAlign: TextAlign.end, style: text.body),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Commandes déjà justifiées — read-only (spec §18)
// ---------------------------------------------------------------------

class _JustifiedHistoryCard extends ConsumerWidget {
  const _JustifiedHistoryCard();

  Future<void> _view(BuildContext context, WidgetRef ref, CashierSettlement s) async {
    final result = await ref.read(settlementControllerProvider).viewAgain(s.id);
    if (!context.mounted) return;
    if (!result.isOk) {
      showAppToast(
        context,
        message: result.error ?? tr(ref, 'settlements.load_error'),
        kind: AppToastKind.error,
      );
    }
    // On success, Printing.layoutPdf inside viewAgain already opened the
    // print/preview dialog — nothing else to show here.
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mySettlementsProvider);
    final items = async.valueOrNull;

    return AppSectionCard(
      title: tr(ref, 'settlements.history_title'),
      subtitle: items == null || items.isEmpty
          ? tr(ref, 'settlements.history_subtitle')
          : '${items.length} ${tr(ref, 'settlements.history_subtitle')}',
      icon: Icons.history_rounded,
      child: Builder(builder: (context) {
        if (items != null) {
          if (items.isEmpty) {
            return AppEmptyState(
              compact: true,
              icon: Icons.inbox_outlined,
              title: tr(ref, 'settlements.history_empty'),
            );
          }
          return Column(
            children: [for (final s in items) _SettlementTile(settlement: s, onView: () => _view(context, ref, s))],
          );
        }
        if (async.hasError) {
          return AppErrorState(
            compact: true,
            title: tr(ref, 'settlements.load_error'),
            message: async.error is ApiException
                ? (async.error as ApiException).message
                : tr(ref, 'settlements.load_error'),
            retryLabel: tr(ref, 'reports.retry'),
            onRetry: () => ref.invalidate(mySettlementsProvider),
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
        );
      }),
    );
  }
}

class _SettlementTile extends ConsumerWidget {
  final CashierSettlement settlement;
  final VoidCallback onView;

  const _SettlementTile({required this.settlement, required this.onView});

  String _statusLabel(WidgetRef ref) {
    switch (settlement.status) {
      case 'PAID':
        return tr(ref, 'settlements.status_paid');
      case 'CANCELLED':
        return tr(ref, 'settlements.status_cancelled');
      default:
        return tr(ref, 'settlements.status_printed');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.text;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(settlement.settlementNumber, style: text.body.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: AppSpacing.sm),
                    StatusBadge(status: settlement.status, label: _statusLabel(ref), size: StatusBadgeSize.small),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${settlement.orderCount} • ${ReportFormat.money(settlement.totalAmount)} • '
                  '${ReportFormat.date(settlement.periodStart)} → ${ReportFormat.date(settlement.periodEnd)}',
                  style: text.bodySecondary,
                ),
              ],
            ),
          ),
          AppButton.outline(
            label: tr(ref, 'settlements.view'),
            icon: Icons.visibility_outlined,
            size: AppButtonSize.small,
            onPressed: onView,
          ),
        ],
      ),
    );
  }
}
