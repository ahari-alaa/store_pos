import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../providers/reports_provider.dart';

/// "Dépenses" (spec §13) — total, count, and the real expense categories
/// present in the store's data for the period.
class ExpensesSection extends ConsumerWidget {
  const ExpensesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(reportExpensesProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.expenses'),
      action: expensesAsync.maybeWhen(
        data: (report) => Text(
          CurrencyFormatter.format(report.totalAmount),
          style: context.text.cardTitle.copyWith(color: context.colors.danger),
        ),
        orElse: () => null,
      ),
      child: expensesAsync.when(
        loading: () => Column(
          children: List.generate(
            3,
            (i) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: double.infinity, child: AppSkeleton(height: 16)),
            ),
          ),
        ),
        error: (error, _) => DashboardErrorInline(
          error: error,
          onRetry: () => ref.invalidate(reportExpensesProvider),
        ),
        data: (report) {
          if (report.byCategory.isEmpty) {
            return AppEmptyState(
              icon: Icons.receipt_outlined,
              title: tr(ref, 'reports.empty_title'),
              message: tr(ref, 'reports.empty_message'),
              compact: true,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final category in report.byCategory) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.category,
                        style: context.text.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('${category.count}', style: context.text.bodySecondary),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      CurrencyFormatter.format(category.amount),
                      style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        },
      ),
    );
  }
}
