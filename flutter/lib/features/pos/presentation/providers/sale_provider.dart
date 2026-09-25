import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/network/providers.dart';
import '../../../ingredients/presentation/providers/ingredients_provider.dart';
import '../../data/datasources/sales_api.dart';
import 'cart_provider.dart';
import 'payment_provider.dart';
import 'pos_providers.dart';

/// A sale-completion problem that isn't a server error (e.g. an empty
/// cart) — distinct from [ApiException], which comes from the backend.
class SaleSubmissionException implements Exception {
  final String message;
  const SaleSubmissionException(this.message);
}

final salesApiProvider = Provider<SalesApi>((ref) {
  return SalesApi(ref.watch(apiClientProvider));
});

/// True while a "Complete Sale" request is in flight, so the button can
/// show a spinner and can't be double-tapped into two sales.
final isSubmittingSaleProvider = StateProvider<bool>((ref) => false);

final saleControllerProvider = Provider<SaleController>((ref) => SaleController(ref));

class SaleController {
  final Ref _ref;
  const SaleController(this._ref);

  static const _uuid = Uuid();

  /// Builds the payload from the current cart/payment state and posts it
  /// to POST /api/sales. On success, invalidates [productsProvider] so the
  /// grid reflects the stock the backend just deducted.
  Future<Map<String, dynamic>> completeSale() async {
    final totals = _ref.read(cartTotalsProvider);
    final entries = _ref.read(paymentProvider).toEntries();
    if (entries.isEmpty || entries.every((e) => e.amount <= 0)) {
      throw const SaleSubmissionException('Add a payment amount before completing the sale.');
    }

    return _submitSale(
      payments: entries
          .where((entry) => entry.amount > 0)
          .map((entry) => {
                'amount': entry.amount,
                'payment_method': entry.method.name.toUpperCase(),
              })
          .toList(),
      discountTotal: totals.discountAmount,
      taxTotal: totals.taxAmount,
    );
  }

  /// "Give receipt without paying" (Sales spec §2/§3/§12): creates the
  /// SAME kind of real sale as [completeSale] — same items, same stock
  /// deduction — but with NO payment rows at all, which the backend
  /// (see saleService.createSale) records with `payment_status = PENDING`
  /// ("NOT PAID") instead of requiring the total to be covered up front.
  ///
  /// Deliberately reuses [_submitSale] rather than duplicating the
  /// item-mapping/API-call logic: the only difference between a paid and
  /// an unpaid sale is which `payments` list gets sent.
  Future<Map<String, dynamic>> createUnpaidSale() async {
    final totals = _ref.read(cartTotalsProvider);
    return _submitSale(
      payments: const [],
      discountTotal: totals.discountAmount,
      taxTotal: totals.taxAmount,
    );
  }

  Future<Map<String, dynamic>> _submitSale({
    required List<Map<String, dynamic>> payments,
    required double discountTotal,
    required double taxTotal,
  }) async {
    final items = _ref.read(cartProvider);
    if (items.isEmpty) {
      throw const SaleSubmissionException('Cart is empty.');
    }

    final api = _ref.read(salesApiProvider);
    final data = await api.createSale(
      clientOperationId: _uuid.v4(),
      items: items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
                'unit_price': item.product.price,
              })
          .toList(),
      payments: payments,
      discountTotal: discountTotal,
      taxTotal: taxTotal,
    );

    _ref.invalidate(productsProvider);
    // A completed sale (paid or "give receipt without paying" — both go
    // through this same method) may have auto-consumed recipe supplies
    // (see saleService.createSale -> ingredientService.consumeForSale on
    // the backend). ingredientsProvider is a plain StateNotifierProvider
    // that only re-fetches on refresh()/invalidation, never on its own —
    // without this, the Supplies screen (spec §12) would keep showing
    // pre-sale stock until something else happened to refresh it.
    _ref.invalidate(ingredientsProvider);
    return data;
  }
}
