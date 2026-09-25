import 'product.dart';

/// A single line in the current sale (cart).
///
/// Immutable by design: cart mutations always produce a new [CartItem] /
/// new list via [CartNotifier], never in-place mutation, so Riverpod state
/// changes are easy to reason about and to unit test.
class CartItem {
  final Product product;
  final int quantity;

  const CartItem({
    required this.product,
    required this.quantity,
  });

  double get lineSubtotal => product.price * quantity;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
    );
  }
}
