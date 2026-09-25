import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/sale.dart';
import '../providers/sales_provider.dart';
import '../widgets/pay_sale_dialog.dart';
import '../widgets/sale_detail_dialog.dart';
import '../widgets/sale_status_badge.dart';

/// The Sales screen — "the history of all receipts" (spec §1). Every sale
/// created from the POS (paid or not) shows up here, newest first (§16),
/// searchable and filterable by payment status (§15).
class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesProvider);
    final filtered = ref.watch(filteredSalesProvider);
    final statusFilter = ref.watch(saleStatusFilterProvider);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Sales', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.read(salesProvider.notifier).refresh(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Every receipt created from the POS, paid or not.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search by receipt number, cashier, or date...',
                  ),
                  onChanged: (v) => ref.read(saleSearchQueryProvider.notifier).state = v,
                ),
              ),
              const SizedBox(width: 12),
              _StatusFilterChips(
                value: statusFilter,
                onChanged: (v) => ref.read(saleStatusFilterProvider.notifier).state = v,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                message: error is ApiException ? error.message : 'Could not load sales.',
                onRetry: () => ref.read(salesProvider.notifier).refresh(),
              ),
              data: (_) {
                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No sales found', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      const _SalesHeaderRow(),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final sale = filtered[index];
                            return _SaleRow(
                              sale: sale,
                              onOpen: () => _openDetail(context, sale),
                              onPay: sale.canPay ? () => _pay(context, sale) : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, Sale sale) {
    showDialog(context: context, builder: (_) => SaleDetailDialog(sale: sale));
  }

  Future<void> _pay(BuildContext context, Sale sale) async {
    final updated = await showDialog<Sale>(
      context: context,
      builder: (_) => PaySaleDialog(sale: sale),
    );
    if (updated == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Receipt #${updated.receiptNumber} marked PAID.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class _StatusFilterChips extends StatelessWidget {
  final SaleStatusFilter value;
  final ValueChanged<SaleStatusFilter> onChanged;

  const _StatusFilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, SaleStatusFilter filter) {
      final selected = value == filter;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onChanged(filter),
          labelStyle: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
          selectedColor: AppColors.primary,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.border),
        ),
      );
    }

    return Row(
      children: [
        chip('All', SaleStatusFilter.all),
        chip('Paid', SaleStatusFilter.paid),
        chip('Not Paid', SaleStatusFilter.notPaid),
      ],
    );
  }
}

class _SalesHeaderRow extends StatelessWidget {
  const _SalesHeaderRow();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: const [
          Expanded(flex: 2, child: Text('RECEIPT', style: style)),
          Expanded(flex: 2, child: Text('DATE', style: style)),
          Expanded(flex: 1, child: Text('TIME', style: style)),
          Expanded(flex: 2, child: Text('CASHIER', style: style)),
          Expanded(flex: 2, child: Text('TOTAL', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
          SizedBox(width: 96),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  final Sale sale;
  final VoidCallback onOpen;
  final VoidCallback? onPay;

  const _SaleRow({required this.sale, required this.onOpen, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final local = sale.occurredAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(local.day)}/${two(local.month)}/${local.year}';
    final time = '${two(local.hour)}:${two(local.minute)}';

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text('#${sale.receiptNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(flex: 2, child: Text(date, style: const TextStyle(color: AppColors.textSecondary))),
            Expanded(flex: 1, child: Text(time, style: const TextStyle(color: AppColors.textSecondary))),
            Expanded(
              flex: 2,
              child: Text(
                sale.cashierName ?? '—',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                CurrencyFormatter.format(sale.total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(flex: 2, child: SaleStatusBadge(status: sale.status)),
            SizedBox(
              width: 96,
              child: onPay == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: onPay,
                        child: const Text('Pay', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
