import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../providers/reports_provider.dart';

/// "Performance des caissiers" (spec §10) — every cashier who logged at
/// least one sale in the period, sortable by CA/commandes/articles/ticket
/// moyen. Tapping a row opens the cashier-detail drill-down (spec §11).
class CashierPerformanceSection extends ConsumerWidget {
  const CashierPerformanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankingAsync = ref.watch(reportCashierRankingProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.cashier_performance'),
      bodyFlush: true,
      child: rankingAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: AppTableSkeleton(rows: 4, columns: 5),
        ),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppErrorState(
            title: tr(ref, 'reports.error_title'),
            message: tr(ref, 'reports.error_message'),
            onRetry: () => ref.invalidate(reportCashierRankingProvider),
            compact: true,
          ),
        ),
        data: (rows) => AppDataTable<CashierRankingEntry>(
          minWidth: 640,
          rows: rows,
          onRowTap: (row) => context.push('/reports/cashiers/${row.cashierId}', extra: row),
          emptyState: AppEmptyState(
            icon: Icons.people_outline_rounded,
            title: tr(ref, 'reports.empty_title'),
            message: tr(ref, 'reports.empty_message'),
            compact: true,
          ),
          columns: [
            AppTableColumn<CashierRankingEntry>(
              label: tr(ref, 'reports.column_cashier'),
              flex: 3,
              cell: (context, row) => Text(row.cashierName),
              sortKey: (row) => row.cashierName,
            ),
            AppTableColumn<CashierRankingEntry>(
              label: tr(ref, 'reports.column_orders'),
              align: AppColumnAlign.right,
              cell: (context, row) => Text('${row.saleCount}'),
              sortKey: (row) => row.saleCount,
            ),
            AppTableColumn<CashierRankingEntry>(
              label: tr(ref, 'reports.column_items'),
              align: AppColumnAlign.right,
              cell: (context, row) => Text('${row.itemsSold}'),
              sortKey: (row) => row.itemsSold,
            ),
            AppTableColumn<CashierRankingEntry>(
              label: tr(ref, 'reports.column_revenue'),
              align: AppColumnAlign.right,
              flex: 3,
              cell: (context, row) => Text(
                CurrencyFormatter.format(row.totalSales),
                style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
              ),
              sortKey: (row) => row.totalSales,
            ),
            AppTableColumn<CashierRankingEntry>(
              label: tr(ref, 'reports.column_average_ticket'),
              align: AppColumnAlign.right,
              flex: 3,
              cell: (context, row) => Text(CurrencyFormatter.format(row.averageSale)),
              sortKey: (row) => row.averageSale,
            ),
          ],
        ),
      ),
    );
  }
}
