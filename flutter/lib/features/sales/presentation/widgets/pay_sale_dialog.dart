import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../pos/domain/entities/payment_method.dart';
import '../../../pos/presentation/widgets/cash_amount_keypad_dialog.dart';
import '../../domain/entities/sale.dart';
import '../providers/sales_provider.dart';

/// "Pay" flow for an existing NOT PAID (or PARTIALLY PAID) sale — Sales
/// spec §6/§7/§17. Reuses [CashAmountKeypadDialog], the SAME amount-
/// received keypad the POS screen itself uses, rather than building a new
/// one. On success, returns the updated [Sale] via [Navigator.pop] so the
/// caller (the detail dialog) can refresh immediately.
class PaySaleDialog extends ConsumerStatefulWidget {
  final Sale sale;

  const PaySaleDialog({super.key, required this.sale});

  @override
  ConsumerState<PaySaleDialog> createState() => _PaySaleDialogState();
}

class _PaySaleDialogState extends ConsumerState<PaySaleDialog> {
  PaymentMethod _method = PaymentMethod.cash;
  double _amount = 0;
  bool _submitting = false;

  double get _remaining => widget.sale.remaining;

  /// Confirm stays disabled until enough money is entered (spec §17) —
  /// the sale must never be marked paid for less than it's owed.
  bool get _sufficient => _amount + 0.001 >= _remaining;

  @override
  void initState() {
    super.initState();
    // Card is assumed charged for the exact remaining balance, same
    // convention as the POS screen's own card flow (payment_section.dart).
    if (_method == PaymentMethod.card) _amount = _remaining;
  }

  Future<void> _openCashKeypad() async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => CashAmountKeypadDialog(total: _remaining, initialValue: _amount),
    );
    if (result != null) {
      setState(() => _amount = result);
    }
  }

  Future<void> _confirm() async {
    if (!_sufficient || _submitting) return;
    setState(() => _submitting = true);
    try {
      final updated = await ref.read(salePaymentControllerProvider).pay(
            saleId: widget.sale.id,
            amount: _amount,
            paymentMethod: _method.name.toUpperCase(),
          );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not record the payment. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final change = _amount - _remaining;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pay receipt #${widget.sale.receiptNumber}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Total ${CurrencyFormatter.format(widget.sale.total)} • Remaining ${CurrencyFormatter.format(_remaining)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MethodButton(
                      label: 'Cash',
                      icon: Icons.payments_outlined,
                      selected: _method == PaymentMethod.cash,
                      onTap: () => setState(() {
                        _method = PaymentMethod.cash;
                        _amount = 0;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MethodButton(
                      label: 'Card',
                      icon: Icons.credit_card_rounded,
                      selected: _method == PaymentMethod.card,
                      onTap: () => setState(() {
                        _method = PaymentMethod.card;
                        _amount = _remaining;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_method == PaymentMethod.cash) ...[
                Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openCashKeypad,
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
                            _amount > 0 ? CurrencyFormatter.format(_amount) : 'Tap to enter',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: _amount > 0 ? AppColors.textPrimary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                Container(
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
                          'Charge ${CurrencyFormatter.format(_remaining)} on card terminal',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: !_sufficient ? const Color(0xFFFEF2F2) : AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _sufficient ? 'Change' : 'Remaining',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    Text(
                      CurrencyFormatter.format((_sufficient ? change : _remaining - _amount).abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: _sufficient ? AppColors.primary : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (_sufficient && !_submitting) ? _confirm : null,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Confirm Payment', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodButton({
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
