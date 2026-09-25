/// Matches the `payments.method` values planned in the DB design
/// (CASH / CARD / TRANSFER). `transfer` isn't offered as a POS payment
/// mode yet (see payment_provider.dart's `PaymentMode`), but is kept here
/// since the backend/DB design already accounts for it.
enum PaymentMethod { cash, card, transfer }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.transfer:
        return 'Transfer';
    }
  }
}
