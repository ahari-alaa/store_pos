import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../providers/cart_provider.dart';
import '../providers/payment_provider.dart';
import 'cash_amount_keypad_dialog.dart';

class PaymentSection extends ConsumerWidget {
  const PaymentSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref.watch(paymentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Payment method',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ModeButton(
                label: 'Cash',
                icon: Icons.payments_outlined,
                selected: payment.mode == PaymentMode.cash,
                onTap: () => ref.read(paymentProvider.notifier).setMode(PaymentMode.cash),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeButton(
                label: 'Card',
                icon: Icons.credit_card_rounded,
                selected: payment.mode == PaymentMode.card,
                onTap: () => ref.read(paymentProvider.notifier).setMode(PaymentMode.card),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (payment.mode == PaymentMode.cash) const _CashInput(),
        if (payment.mode == PaymentMode.card) const _CardConfirmRow(),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 18, color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cash payment input. "Amount received" is a tappable field (not a plain
/// [TextField]) that opens [CashAmountKeypadDialog] — a big on-screen
/// numeric keypad designed for a cashier at a register, so entering cash
/// never requires the computer keyboard.
class _CashInput extends ConsumerWidget {
  const _CashInput();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(cartTotalsProvider).total;
    final payment = ref.watch(paymentProvider);
    final change = payment.cashAmount - total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AmountReceivedField(
          amount: payment.cashAmount,
          onTap: () async {
            final result = await showDialog<double>(
              context: context,
              builder: (_) => CashAmountKeypadDialog(
                total: total,
                initialValue: payment.cashAmount,
              ),
            );
            if (result != null) {
              ref.read(paymentProvider.notifier).setCashAmount(result);
            }
          },
        ),
        const SizedBox(height: 10),
        _ChangeRow(change: change),
      ],
    );
  }
}

class _AmountReceivedField extends StatelessWidget {
  final double amount;
  final VoidCallback onTap;

  const _AmountReceivedField({required this.amount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.dialpad_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Amount received',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
              Text(
                amount > 0 ? CurrencyFormatter.format(amount) : 'Tap to enter',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: amount > 0 ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardConfirmRow extends ConsumerWidget {
  const _CardConfirmRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(cartTotalsProvider).total;
    // Card payments are assumed to be charged for the exact total via the
    // (future) card terminal integration — no change to compute.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(paymentProvider.notifier).setCardAmount(total);
    });
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.credit_card_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Charge ${CurrencyFormatter.format(total)} on card terminal',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final double change;
  const _ChangeRow({required this.change});

  @override
  Widget build(BuildContext context) {
    final isNegative = change < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isNegative ? const Color(0xFFFEF2F2) : AppColors.primarySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isNegative ? 'Remaining' : 'Change',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          Text(
            CurrencyFormatter.format(change.abs()),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isNegative ? AppColors.danger : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
