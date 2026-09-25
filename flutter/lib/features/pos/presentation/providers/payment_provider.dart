import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/payment_method.dart';

/// UI-level selection of how the current sale is being paid.
enum PaymentMode { cash, card }

/// One entry in a (potentially split) payment — mirrors a future
/// `payments` row (method + amount). For `cash`, [amount] is what the
/// customer handed over (change is derived, not stored here).
class PaymentEntry {
  final PaymentMethod method;
  final double amount;

  const PaymentEntry({required this.method, required this.amount});
}

/// Holds the in-progress payment split for the sale currently being
/// finalized. Reset via [PaymentState.reset] whenever the cart total
/// changes or a sale completes, so stale amounts never carry over.
class PaymentState {
  final PaymentMode mode;
  final double cashAmount;
  final double cardAmount;

  const PaymentState({
    this.mode = PaymentMode.cash,
    this.cashAmount = 0,
    this.cardAmount = 0,
  });

  double get amountEntered => switch (mode) {
        PaymentMode.cash => cashAmount,
        PaymentMode.card => cardAmount,
      };

  PaymentState copyWith({
    PaymentMode? mode,
    double? cashAmount,
    double? cardAmount,
  }) {
    return PaymentState(
      mode: mode ?? this.mode,
      cashAmount: cashAmount ?? this.cashAmount,
      cardAmount: cardAmount ?? this.cardAmount,
    );
  }

  /// Builds the list of payment rows to persist once the sale is confirmed.
  List<PaymentEntry> toEntries() {
    switch (mode) {
      case PaymentMode.cash:
        return [PaymentEntry(method: PaymentMethod.cash, amount: cashAmount)];
      case PaymentMode.card:
        return [PaymentEntry(method: PaymentMethod.card, amount: cardAmount)];
    }
  }
}

class PaymentNotifier extends StateNotifier<PaymentState> {
  PaymentNotifier() : super(const PaymentState());

  void setMode(PaymentMode mode) {
    // Switching mode clears amounts so partially-typed values from a
    // previous mode never leak into a different payment split.
    state = PaymentState(mode: mode);
  }

  void setCashAmount(double amount) {
    state = state.copyWith(cashAmount: amount);
  }

  void setCardAmount(double amount) {
    state = state.copyWith(cardAmount: amount);
  }

  void reset() {
    state = const PaymentState();
  }
}

final paymentProvider = StateNotifierProvider<PaymentNotifier, PaymentState>((ref) {
  return PaymentNotifier();
});
