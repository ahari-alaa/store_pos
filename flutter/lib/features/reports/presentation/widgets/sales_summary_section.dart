import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../../domain/entities/reports_models.dart';
import '../providers/reports_provider.dart';

/// "Résumé des ventes" (spec §8) — real sale_status / payment_status
/// counts only, straight from reportService.js#salesSummary's
/// `status_summary`. No invented "pending sales" bucket: every figure
/// here is a value the schema actually defines.
class SalesSummarySection extends ConsumerWidget {
  const SalesSummarySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(reportSalesSummaryProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.sales_summary'),
      child: summaryAsync.when(
        loading: () => const AppTableSkeleton(rows: 3, columns: 2),
        error: (error, _) => DashboardErrorInline(
          error: error,
          onRetry: () => ref.invalidate(reportSalesSummaryProvider),
        ),
        data: (report) => _SummaryGrid(status: report.statusSummary),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final SalesStatusSummary status;

  const _SummaryGrid({required this.status});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final rows = [
          (tr(ref, 'reports.status_total'), status.total, context.colors.textPrimary),
          (tr(ref, 'reports.status_completed'), status.completed, context.colors.success),
          (tr(ref, 'reports.status_paid'), status.paid, context.colors.success),
          (tr(ref, 'reports.status_not_paid'), status.notPaid, context.colors.warning),
          (tr(ref, 'reports.status_partially_paid'), status.partiallyPaid, context.colors.info),
          (tr(ref, 'reports.status_cancelled'), status.cancelled, context.colors.danger),
          if (status.refundedSales > 0 || status.refundedPayments > 0)
            (
              tr(ref, 'reports.status_refunded'),
              status.refundedSales > 0 ? status.refundedSales : status.refundedPayments,
              context.colors.danger,
            ),
        ];

        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.lg,
          children: [
            for (final row in rows)
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${row.$2}', style: context.text.kpiValue.copyWith(color: row.$3)),
                    const SizedBox(height: 2),
                    Text(row.$1, style: context.text.bodySecondary),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
