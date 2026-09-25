/// Formats amounts the same way everywhere in the app (POS cart, receipts,
/// dashboard, reports) so we never get "12.5 DH" in one place and
/// "12.50DH" in another.
///
/// Currency is hardcoded to Moroccan Dirham (DH) for now, matching the
/// reference design. When multi-store/multi-currency support is added
/// (see project goal: "ready for multiple stores"), this becomes
/// store-configurable and should read from store settings instead.
class CurrencyFormatter {
  CurrencyFormatter._();

  static String format(double amount) {
    return '${amount.toStringAsFixed(2)} DH';
  }
}
