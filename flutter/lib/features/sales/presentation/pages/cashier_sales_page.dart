import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/design_system.dart';
import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/ui/ui.dart';
import '../../../reports/domain/entities/my_report.dart';
import '../providers/my_orders_list_provider.dart';
import '../utils/order_actions.dart';
import '../widgets/my_order_card.dart';

/// "Ventes" for a CASHIER: their own operational orders, each with its
/// products, total, payment status and serving state.
///
/// The server only ever returns this cashier's orders (`/reports/my-orders`
/// is scoped to the signed-in user), and there are no store-wide analytics
/// here. Admin and manager keep the existing [SalesPage].
class CashierSalesPage extends ConsumerStatefulWidget {
  const CashierSalesPage({super.key});

  @override
  ConsumerState<CashierSalesPage> createState() => _CashierSalesPageState();
}

class _CashierSalesPageState extends ConsumerState<CashierSalesPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(myOrdersSearchProvider.notifier).state = value.trim();
    });
  }

  static const _filters = [
    (MyOrdersFilter.all, 'mine.filter_all'),
    (MyOrdersFilter.toServe, 'mine.filter_to_serve'),
    (MyOrdersFilter.served, 'mine.filter_served'),
    (MyOrdersFilter.paid, 'mine.filter_paid'),
    (MyOrdersFilter.unpaid, 'mine.filter_unpaid'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = context.text;
    final filter = ref.watch(myOrdersFilterProvider);
    final state = ref.watch(myOrdersListProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(tr(ref, 'mine.sales_subtitle'), style: text.bodySecondary),
              ),
              const SizedBox(width: AppSpacing.md),
              AppButton.outline(
                label: tr(ref, 'reports.refresh'),
                icon: Icons.refresh_rounded,
                onPressed: () => ref.read(myOrdersListProvider.notifier).reload(keepRows: true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              SizedBox(
                width: 320,
                child: AppTextField(
                  controller: _searchController,
                  hint: tr(ref, 'mine.search_hint'),
                  prefixIcon: Icons.search_rounded,
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (value, key) in _filters)
                      ChoiceChip(
                        label: Text(tr(ref, key)),
                        selected: filter == value,
                        onSelected: (_) => ref.read(myOrdersFilterProvider.notifier).state = value,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(child: _Body(state: state)),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final MyOrdersListState state;

  const _Body({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      final error = state.error;
      return AppErrorState(
        title: tr(ref, 'mine.load_error'),
        message: error is ApiException ? error.message : tr(ref, 'mine.load_error'),
        retryLabel: tr(ref, 'reports.retry'),
        onRetry: () => ref.read(myOrdersListProvider.notifier).reload(),
      );
    }
    if (state.items.isEmpty) {
      return AppEmptyState(
        icon: Icons.receipt_long_outlined,
        title: tr(ref, 'mine.sales_empty'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyOrderGrid(
            children: [
              for (final MyOrder order in state.items)
                MyOrderCard(
                  key: ValueKey('order-${order.id}'),
                  order: order,
                  // Page-level context/ref: the card can vanish from the
                  // current filter as soon as the order is served.
                  onServe: order.isServed ? null : () => OrderActions.serve(context, ref, order),
                  onReprint: order.isServed ? () => OrderActions.reprint(context, ref, order) : null,
                ),
            ],
          ),
          if (state.hasMore) ...[
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: AppButton.outline(
                label: tr(ref, 'mine.load_more'),
                icon: Icons.expand_more_rounded,
                loading: state.loadingMore,
                onPressed: () => ref.read(myOrdersListProvider.notifier).loadMore(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
