import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/dashboard_provider.dart';
import 'dashboard_error_view.dart';

/// "Articles vendus aujourd'hui" / "المنتجات المباعة اليوم" — compact bar
/// list of units sold per product for the selected period (spec §5/§9).
/// Backed by GET /reports/dashboard-articles, which already aggregates
/// SUM(sale_items.quantity) in SQL and caps the result to the top few
/// products, so this widget never has to sum anything client-side or
/// truncate an unbounded list itself.
class ArticlesSoldCard extends ConsumerWidget {
  const ArticlesSoldCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articlesAsync = ref.watch(articlesSoldProvider);
    final locale = ref.watch(localeProvider);
    final isAr = locale.name == 'ar';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isAr ? 'المنتجات المباعة اليوم' : tr(ref, 'dashboard.articles_sold'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/reports'),
                  child: Text(tr(ref, 'dashboard.see_more')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            articlesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, _) => DashboardErrorInline(
                error: error,
                onRetry: () => ref.invalidate(articlesSoldProvider),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(tr(ref, 'dashboard.no_sales_period'),
                        style: const TextStyle(color: AppColors.textMuted)),
                  );
                }
                final maxQty = entries.map((e) => e.quantitySold).reduce((a, b) => a > b ? a : b);
                return Column(
                  children: entries
                      .map((e) => _ArticleBar(
                            label: e.name,
                            quantity: e.quantitySold,
                            maxQuantity: maxQty,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleBar extends StatelessWidget {
  final String label;
  final int quantity;
  final int maxQuantity;

  const _ArticleBar({
    required this.label,
    required this.quantity,
    required this.maxQuantity,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxQuantity == 0 ? 0.0 : quantity / maxQuantity;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(height: 14, color: AppColors.background),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        height: 14,
                        width: constraints.maxWidth * ratio,
                        color: primary,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text('$quantity',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
