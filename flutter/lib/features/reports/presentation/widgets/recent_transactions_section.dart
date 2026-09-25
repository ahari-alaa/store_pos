import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../sales/domain/entities/sale.dart';
import '../../../sales/presentation/widgets/sale_detail_dialog.dart';
import '../../../sales/presentation/widgets/sale_status_badge.dart';
import '../providers/reports_provider.dart';

/// "Transactions récentes" (spec §15) — reuses GET /sales (paginated
/// server-side, spec §21) rather than a Rapports-only endpoint, and opens
/// the SAME [SaleDetailDialog] the Sales screen uses rather than a
/// duplicate transaction-detail view (spec: "Do not create a duplicate
/// transaction-detail system").
class RecentTransactionsSection extends ConsumerWidget {
  const RecentTransactionsSection({super.key});

  String _methodLabel(WidgetRef ref, String? method) {
    switch (method) {
      case 'CASH':
        return tr(ref, 'payment_method.cash');
      case 'CARD':
        return tr(ref, 'payment_method.card');
      case 'TRANSFER':
        return tr(ref, 'payment_method.transfer');
      case 'MIXED':
        return tr(ref, 'payment_method.mixed');
      default:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateAsync = ref.watch(reportTransactionsProvider);
    final notifier = ref.read(reportTransactionsProvider.notifier);

    return AppSectionCard(
      title: tr(ref, 'reports.recent_transactions'),
      bodyFlush: true,
      child: stateAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: AppTableSkeleton(rows: 5, columns: 6),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppErrorState(
            title: tr(ref, 'reports.error_title'),
            message: tr(ref, 'reports.error_message'),
            onRetry: () => notifier.load(page: 1),
            compact: true,
          ),
        ),
        data: (data) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDataTable<Sale>(
                minWidth: 760,
                rows: data.items,
                onRowTap: (sale) => showDialog(context: context, builder: (_) => SaleDetailDialog(sale: sale)),
                emptyState: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: tr(ref, 'reports.empty_title'),
                  message: tr(ref, 'reports.empty_message'),
                  compact: true,
                ),
                columns: [
                  AppTableColumn<Sale>(
                    label: tr(ref, 'reports.column_reference'),
                    cell: (context, sale) => Text('#${sale.id.substring(0, sale.id.length >= 6 ? 6 : sale.id.length).toUpperCase()}'),
                  ),
                  AppTableColumn<Sale>(
                    label: tr(ref, 'reports.column_date'),
                    flex: 3,
                    cell: (context, sale) => Text(DateFormat('dd/MM/yy HH:mm').format(sale.occurredAt)),
                  ),
                  AppTableColumn<Sale>(
                    label: tr(ref, 'reports.column_cashier'),
                    flex: 3,
                    cell: (context, sale) => Text(sale.cashierName ?? '—'),
                  ),
                  AppTableColumn<Sale>(
                    label: tr(ref, 'reports.column_total'),
                    align: AppColumnAlign.right,
                    cell: (context, sale) => Text(
                      CurrencyFormatter.format(sale.total),
                      style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  AppTableColumn<Sale>(
                    label: tr(ref, 'reports.column_payment_method'),
                    cell: (context, sale) =>
                        Text(_methodLabel(ref, sale.primaryPaymentMethod?.name.toUpperCase() ?? sale.rawPaymentMethod)),
                  ),
                  AppTableColumn<Sale>(
                    label: tr(ref, 'reports.column_status'),
                    align: AppColumnAlign.center,
                    cell: (context, sale) => SaleStatusBadge(status: sale.status),
                  ),
                ],
              ),
              if (data.total > 0)
                AppPagination(
                  page: data.page,
                  pageCount: data.pageCount,
                  totalItems: data.total,
                  pageSize: data.pageSize,
                  onPageChanged: (page) => notifier.goToPage(page),
                ),
            ],
          );
        },
      ),
    );
  }
}
