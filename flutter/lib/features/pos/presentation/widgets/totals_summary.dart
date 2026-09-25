import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/cart_provider.dart';

class TotalsSummary extends ConsumerWidget {
  const TotalsSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(cartTotalsProvider);
    final discountPercent = ref.watch(discountPercentProvider);

    return Column(
      children: [
        _Row(label: 'Subtotal', value: CurrencyFormatter.format(totals.subtotal)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Text('Discount', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
            _DiscountInput(
              value: discountPercent,
              onChanged: (value) => ref.read(discountPercentProvider.notifier).state = value,
            ),
            const SizedBox(width: 10),
            Text(
              '- ${CurrencyFormatter.format(totals.discountAmount)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.danger),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Row(label: 'Tax', value: CurrencyFormatter.format(totals.taxAmount)),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(
              CurrencyFormatter.format(totals.total),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }
}

/// Small inline % input. Kept intentionally simple (a text field parsed on
/// change) rather than a slider — cashiers expect to type an exact
/// percentage discount authorized for that sale.
class _DiscountInput extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _DiscountInput({required this.value, required this.onChanged});

  @override
  State<_DiscountInput> createState() => _DiscountInputState();
}

class _DiscountInputState extends State<_DiscountInput> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value == 0 ? '' : widget.value.toStringAsFixed(0));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 30,
      child: TextField(
        controller: _controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          suffixText: '%',
          suffixStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (text) {
          final parsed = double.tryParse(text) ?? 0;
          widget.onChanged(parsed.clamp(0, 100));
        },
      ),
    );
  }
}
