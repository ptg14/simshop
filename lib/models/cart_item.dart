import 'product.dart';

/// Represents an item in the shopping cart.
class CartItem {
  final Product product;
  int quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });

  /// Calculate total price for this item.
  double get totalPrice => product.price * quantity;

  /// Copy with modified fields.
  CartItem copyWith({
    Product? product,
    int? quantity,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}
