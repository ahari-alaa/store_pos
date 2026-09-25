import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/restricted_page.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../reports/presentation/widgets/report_widgets.dart';
import '../../domain/entities/settlement.dart';
import '../providers/admin_settlement_controller.dart';
import '../providers/settlement_provider.dart';

/// "Paiements caissiers" — admin/manager only (spec §22-§23, §26, §33):
/// every cashier's work-payment justificatifs, and the ability to mark one
/// paid, cancel it, or print an admin-only duplicate copy.
///
/// Deliberately a different screen from the cashier's own Rapport
/// (SettlementSection): a cashier never reaches this page (see
/// AppUser.canManageCashierSettlements / app_sidebar.dart), and every
/// action it offers is refused server-side for a cashier role regardless
/// (adminCashierSettlementRoutes.js).
class AdminCashierSettlementsPage extends ConsumerWidget {
  const AdminCashierSettlementsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    if (user != null && !user.canManageCashierSettlements) {
      return RestrictedPage(message: tr(ref, 'reports.restricted'));
    }

    final async = ref.watch(adminSettlementsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StatusFilterBar(),
          const SizedBox(height: AppSpacing.md),
          AppSectionCard(
            title: tr(ref, 'admin_settlements.title'),
            bodyFlush: true,
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: AppTableSkeleton(rows: 6, columns: 6),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppErrorState(
                  compact: true,
                  title: tr(ref, 'admin_settlements.load_error'),
                  message: error is ApiException ? error.message : tr(ref, 'admin_settlements.load_error'),
                  retryLabel: tr(ref, 'reports.retry'),
                  onRetry: () => ref.invalidate(adminSettlementsProvider),
                ),
              ),
              data: (items) => AppDataTable<CashierSettlement>(
                minWidth: 760,
                rows: items,
                onRowTap: (s) => showDialog(
                  context: context,
                  builder: (_) => _SettlementDetailDialog(settlementId: s.id),
                ),
                emptyState: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: tr(ref, 'admin_settlements.empty'),
                  compact: true,
                ),
                columns: [
                  AppTableColumn<CashierSettlement>(
                    label: tr(ref, 'admin_settlements.col_settlement'),
                    cell: (context, s) => Text(s.settlementNumber, style: context.text.tableCell),
                  ),
                  AppTableColumn<CashierSettlement>(
                    label: tr(ref, 'admin_settlements.col_cashier'),
                    flex: 2,
                    cell: (context, s) => Text(s.cashierName),
                  ),
                  AppTableColumn<CashierSettlement>(
                    label: tr(ref, 'admin_settlements.col_orders'),
                    align: AppColumnAlign.center,
                    cell: (context, s) => Text(ReportFormat.integer(s.orderCount)),
                  ),
                  AppTableColumn<CashierSettlement>(
                    label: tr(ref, 'admin_settlements.col_total'),
                    align: AppColumnAlign.right,
                    cell: (context, s) => Text(
                      ReportFormat.money(s.totalAmount),
                      style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  AppTableColumn<CashierSettlement>(
                    label: tr(ref, 'admin_settlements.col_date'),
                    flex: 2,
                    cell: (context, s) => Text(ReportFormat.dateTime(s.createdAt)),
                  ),
                  AppTableColumn<CashierSettlement>(
                    label: tr(ref, 'admin_settlements.col_status'),
                    align: AppColumnAlign.center,
                    cell: (context, s) => _StatusChip(status: s.status),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends ConsumerWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = switch (status) {
      'PAID' => tr(ref, 'settlements.status_paid'),
      'CANCELLED' => tr(ref, 'settlements.status_cancelled'),
      _ => tr(ref, 'settlements.status_printed'),
    };
    return StatusBadge(status: status, label: label, size: StatusBadgeSize.small);
  }
}

class _StatusFilterBar extends ConsumerWidget {
  const _StatusFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(adminSettlementFilterProvider);

    Widget chip(String label, String? value) {
      final selected = filter.status == value;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => ref.read(adminSettlementFilterProvider.notifier).state =
              filter.copyWith(status: () => value),
        ),
      );
    }

    return Row(
      children: [
        chip(tr(ref, 'admin_settlements.filter_all'), null),
        chip(tr(ref, 'admin_settlements.filter_printed'), 'PRINTED'),
        chip(tr(ref, 'admin_settlements.filter_paid'), 'PAID'),
        chip(tr(ref, 'admin_settlements.filter_cancelled'), 'CANCELLED'),
        const Spacer(),
        IconButton(
          tooltip: tr(ref, 'reports.retry'),
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => ref.read(adminSettlementRefreshProvider.notifier).state++,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Detail dialog — orders list + MARQUER COMME PAYÉ / annuler / réimprimer
// ---------------------------------------------------------------------

class _SettlementDetailDialog extends ConsumerStatefulWidget {
  final String settlementId;
  const _SettlementDetailDialog({required this.settlementId});

  @override
  ConsumerState<_SettlementDetailDialog> createState() => _SettlementDetailDialogState();
}

class _SettlementDetailDialogState extends ConsumerState<_SettlementDetailDialog> {
  CashierSettlement? _settlement;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(settlementApiProvider).adminFetchSettlement(widget.settlementId);
      if (!mounted) return;
      setState(() {
        _settlement = CashierSettlement.fromJson((data['settlement'] as Map<String, dynamic>?) ?? const {});
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _markPaid() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: tr(ref, 'admin_settlements.mark_paid_confirm_title'),
      message: tr(ref, 'admin_settlements.mark_paid_confirm_message'),
      icon: Icons.payments_outlined,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref.read(adminSettlementControllerProvider).markPaid(widget.settlementId);
      if (!mounted) return;
      setState(() {
        _settlement = updated;
        _busy = false;
      });
      showAppToast(context, message: tr(ref, 'admin_settlements.mark_paid_success'), kind: AppToastKind.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    }
  }

  Future<void> _cancel() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: tr(ref, 'admin_settlements.cancel_confirm_title'),
        icon: Icons.block_rounded,
        actions: [
          AppButton.text(
            label: tr(ref, 'admin_settlements.close'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton.destructive(
            label: tr(ref, 'admin_settlements.cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(ref, 'admin_settlements.cancel_confirm_message'), style: context.text.body),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(hintText: tr(ref, 'admin_settlements.cancel_reason_hint')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(adminSettlementControllerProvider)
          .cancel(widget.settlementId, reason: reasonController.text);
      if (!mounted) return;
      setState(() {
        _settlement = updated;
        _busy = false;
      });
      showAppToast(context, message: tr(ref, 'admin_settlements.cancel_success'), kind: AppToastKind.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    }
  }

  Future<void> _reprint() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: tr(ref, 'admin_settlements.reprint_confirm_title'),
      message: tr(ref, 'admin_settlements.reprint_confirm_message'),
      icon: Icons.print_outlined,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminSettlementControllerProvider).reprintCopy(widget.settlementId);
      await _load();
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, message: tr(ref, 'admin_settlements.reprint_success'), kind: AppToastKind.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, message: e.message, kind: AppToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settlement;
    final text = context.text;

    return AppDialog(
      title: s?.settlementNumber ?? tr(ref, 'admin_settlements.detail_title'),
      subtitle: s?.cashierName,
      icon: Icons.receipt_long_rounded,
      width: 560,
      actions: s == null
          ? const []
          : [
              AppButton.text(
                label: tr(ref, 'admin_settlements.close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              AppButton.outline(
                label: tr(ref, 'admin_settlements.reprint'),
                icon: Icons.print_outlined,
                loading: _busy,
                onPressed: _busy ? null : _reprint,
              ),
              if (!s.isCancelled)
                AppButton.destructive(
                  label: tr(ref, 'admin_settlements.cancel'),
                  icon: Icons.block_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : _cancel,
                ),
              if (s.isPrinted)
                AppButton.primary(
                  label: tr(ref, 'admin_settlements.mark_paid'),
                  icon: Icons.check_circle_outline_rounded,
                  loading: _busy,
                  onPressed: _busy ? null : _markPaid,
                ),
            ],
      child: SizedBox(
        width: double.infinity,
        child: s == null
            ? (_error != null
                ? AppErrorState(
                    compact: true,
                    title: tr(ref, 'admin_settlements.load_error'),
                    message: _error!,
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusBadge(
                        status: s.status,
                        label: switch (s.status) {
                          'PAID' => tr(ref, 'settlements.status_paid'),
                          'CANCELLED' => tr(ref, 'settlements.status_cancelled'),
                          _ => tr(ref, 'settlements.status_printed'),
                        },
                      ),
                      const Spacer(),
                      Text(
                        '${ReportFormat.integer(s.orderCount)} • ${ReportFormat.money(s.totalAmount)}',
                        style: text.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '${ReportFormat.date(s.periodStart)} → ${ReportFormat.date(s.periodEnd)}',
                    style: text.bodySecondary,
                  ),
                  if (s.isPaid && s.paidAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${tr(ref, 'settlements.status_paid')} • ${ReportFormat.dateTime(s.paidAt!)}'
                        '${s.paidByName != null ? ' • ${s.paidByName}' : ''}',
                        style: text.bodySecondary,
                      ),
                    ),
                  if (s.isCancelled && s.cancelReason != null && s.cancelReason!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(s.cancelReason!, style: text.bodySecondary),
                    ),
                  if (s.reprintCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${tr(ref, 'admin_settlements.reprint')}: ${s.reprintCount}'
                        '${s.lastReprintedByName != null ? ' • ${s.lastReprintedByName}' : ''}',
                        style: text.bodySecondary,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(tr(ref, 'admin_settlements.orders_title'),
                      style: text.body.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final o in s.orders ?? const <SettlementOrder>[])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(flex: 2, child: Text('#${o.receiptNumber}', style: text.body)),
                                  Expanded(
                                    flex: 3,
                                    child: Text(ReportFormat.dateTime(o.occurredAt), style: text.bodySecondary),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(ReportFormat.money(o.total),
                                        textAlign: TextAlign.end, style: text.body),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
