import 'package:flutter/foundation.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

/// ViewModel for managing shopping cart.
class CartViewModel extends ChangeNotifier {
  final List<CartItem> _items = [];

  // Getters
  List<CartItem> get items => _items;

  int get itemCount => _items.length;

  double get totalPrice => _items.fold(0, (sum, item) => sum + item.totalPrice);

  /// Check if a product is in the cart.
  bool isProductInCart(Product product) {
    return _items.any((item) => item.product.id == product.id);
  }

  /// Add a product to the cart.
  void addToCart(Product product, {int quantity = 1}) {
    final existingItemIndex =
        _items.indexWhere((item) => item.product.id == product.id);

    if (existingItemIndex >= 0) {
      _items[existingItemIndex].quantity += quantity;
    } else {
      _items.add(CartItem(product: product, quantity: quantity));
    }

    notifyListeners();
  }

  /// Remove a product from the cart.
  void removeFromCart(String productId) {
    _items.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  /// Update quantity of a cart item.
  void updateQuantity(String productId, int quantity) {
    final itemIndex = _items.indexWhere((item) => item.product.id == productId);

    if (itemIndex >= 0) {
      if (quantity <= 0) {
        _items.removeAt(itemIndex);
      } else {
        _items[itemIndex].quantity = quantity;
      }
      notifyListeners();
    }
  }

  /// Clear the entire cart.
  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  /// Get a cart item by product ID.
  CartItem? getCartItem(String productId) {
    try {
      return _items.firstWhere((item) => item.product.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// Calculate subtotal.
  double get subtotal => totalPrice;

  /// Calculate estimated tax (10%).
  double get tax => subtotal * 0.1;

  /// Calculate shipping fee.
  double get shippingFee => subtotal > 5000000 ? 0 : 500000;

  /// Calculate final total with tax and shipping.
  double get finalTotal => subtotal + tax + shippingFee;
}
