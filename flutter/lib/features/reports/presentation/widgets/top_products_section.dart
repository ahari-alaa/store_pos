import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../dashboard/domain/entities/dashboard_extras.dart';
import '../../../dashboard/presentation/widgets/dashboard_error_view.dart';
import '../providers/reports_provider.dart';

/// "Articles les plus vendus" (spec §12) — ranked by quantity sold
/// (SUM(sale_items.quantity), never the number of sale rows), each with a
/// proportional bar against the top seller and its revenue.
class TopProductsSection extends ConsumerWidget {
  const TopProductsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(reportTopProductsProvider);

    return AppSectionCard(
      title: tr(ref, 'reports.top_products'),
      child: productsAsync.when(
        loading: () => Column(
          children: List.generate(
            5,
            (i) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(width: double.infinity, child: AppSkeleton(height: 18)),
            ),
          ),
        ),
        error: (error, _) => DashboardErrorInline(
          error: error,
          onRetry: () => ref.invalidate(reportTopProductsProvider),
        ),
        data: (products) {
          if (products.isEmpty) {
            return AppEmptyState(
              icon: Icons.local_cafe_outlined,
              title: tr(ref, 'reports.empty_title'),
              message: tr(ref, 'reports.empty_message'),
              compact: true,
            );
          }
          final maxQty = products.map((p) => p.quantitySold).fold<int>(0, (a, b) => a > b ? a : b);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final product in products) ...[
                _ProductRow(product: product, maxQty: maxQty == 0 ? 1 : maxQty),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final ArticleSoldEntry product;
  final int maxQty;

  const _ProductRow({required this.product, required this.maxQty});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ratio = (product.quantitySold / maxQty).clamp(0.0, 1.0);

    return Consumer(
      builder: (context, ref, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(product.name, style: context.text.body, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text(
                '${product.quantitySold} ${tr(ref, 'reports.units_suffix')}',
                style: context.text.bodySecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 84,
                child: Text(
                  CurrencyFormatter.format(product.revenue),
                  textAlign: TextAlign.right,
                  style: context.text.tableCell.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppRadius.xsAll,
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
