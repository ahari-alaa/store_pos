import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/product.dart';

/// Holds the current sale's line items.
///
/// Deliberately dumb/mechanical: no pricing math lives here (see
/// [CartTotals] below) and no persistence. When Phase 4 wires this to a
/// real "complete sale" use case, that use case will read this state,
/// build the sale/sale_items/payments payload, and only THEN call
/// [clear] on success — so a failed sale never silently empties the cart.
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(const []);

  void addProduct(Product product) {
    final index = state.indexWhere((item) => item.product.id == product.id);
    if (index == -1) {
      state = [...state, CartItem(product: product, quantity: 1)];
      return;
    }
    _setQuantity(index, state[index].quantity + 1);
  }

  void incrementQuantity(String productId) {
    final index = state.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;
    _setQuantity(index, state[index].quantity + 1);
  }

  void decrementQuantity(String productId) {
    final index = state.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;
    final newQty = state[index].quantity - 1;
    if (newQty <= 0) {
      removeProduct(productId);
      return;
    }
    _setQuantity(index, newQty);
  }

  void setQuantity(String productId, int quantity) {
    final index = state.indexWhere((item) => item.product.id == productId);
    if (index == -1) return;
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }
    _setQuantity(index, quantity);
  }

  void removeProduct(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void clear() {
    state = const [];
  }

  void _setQuantity(int index, int quantity) {
    final capped = quantity > state[index].product.stockQuantity
        ? state[index].product.stockQuantity
        : quantity;
    final next = [...state];
    next[index] = next[index].copyWith(quantity: capped < 1 ? 1 : capped);
    state = next;
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

/// Discount entered by the cashier, as a percentage (0-100) of the subtotal.
/// A percentage (rather than a fixed amount) is the more common register
/// workflow and matches the reference design ("Discount (10%)").
final discountPercentProvider = StateProvider<double>((ref) => 0);

/// Computed, read-only totals for the current cart + discount.
/// Tax is computed per line using each product's own [Product.taxRate],
/// proportionally reduced by the overall discount, then summed — so mixed
/// tax rates in one cart are still correct.
class CartTotals {
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final int itemCount;

  const CartTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.itemCount,
  });

  static const zero = CartTotals(
    subtotal: 0,
    discountAmount: 0,
    taxAmount: 0,
    total: 0,
    itemCount: 0,
  );
}

final cartTotalsProvider = Provider<CartTotals>((ref) {
  final items = ref.watch(cartProvider);
  final discountPercent = ref.watch(discountPercentProvider);

  if (items.isEmpty) return CartTotals.zero;

  final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineSubtotal);
  final discountAmount = subtotal * (discountPercent / 100);

  double taxAmount = 0;
  for (final item in items) {
    final lineShareOfDiscount =
        subtotal == 0 ? 0 : (item.lineSubtotal / subtotal) * discountAmount;
    final taxableBase = item.lineSubtotal - lineShareOfDiscount;
    taxAmount += taxableBase * item.product.taxRate;
  }

  final total = subtotal - discountAmount + taxAmount;
  final itemCount = items.fold<int>(0, (sum, item) => sum + item.quantity);

  return CartTotals(
    subtotal: subtotal,
    discountAmount: discountAmount,
    taxAmount: taxAmount,
    total: total,
    itemCount: itemCount,
  );
});
