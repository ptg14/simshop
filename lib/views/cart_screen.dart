import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/cart_viewmodel.dart';
import '../utils/currency_formatter.dart';

/// Shopping cart screen.
class CartScreen extends StatelessWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giỏ hàng'),
        centerTitle: true,
      ),
      body: Consumer<CartViewModel>(
        builder: (context, cartViewModel, _) {
          if (cartViewModel.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.shopping_cart_outlined,
                      size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Giỏ hàng trống',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tiếp tục mua sắm'),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              /// Cart items list
              Expanded(
                child: ListView.builder(
                  itemCount: cartViewModel.items.length,
                  itemBuilder: (context, index) {
                    final cartItem = cartViewModel.items[index];
                    final product = cartItem.product;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          /// Product image
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.network(
                              product.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          /// Product details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                /// Product name
                                Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                /// Price
                                Text(
                                  '${formatCurrency(product.price)}/cái',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),

                                const SizedBox(height: 12),

                                /// Quantity controls
                                Row(
                                  children: [
                                    /// Decrease button
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey[300]!),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.remove, size: 16),
                                        onPressed: () {
                                          if (cartItem.quantity > 1) {
                                            cartViewModel.updateQuantity(
                                              product.id,
                                              cartItem.quantity - 1,
                                            );
                                          }
                                        },
                                      ),
                                    ),

                                    /// Quantity display
                                    SizedBox(
                                      width: 40,
                                      child: Center(
                                        child: Text(
                                          '${cartItem.quantity}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                    /// Increase button
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey[300]!),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.add, size: 16),
                                        onPressed: () {
                                          if (cartItem.quantity < product.stock) {
                                            cartViewModel.updateQuantity(
                                              product.id,
                                              cartItem.quantity + 1,
                                            );
                                          }
                                        },
                                      ),
                                    ),

                                    const Spacer(),

                                    /// Remove button
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () {
                                        cartViewModel.removeFromCart(product.id);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${product.name} đã được xóa khỏi giỏ',
                                            ),
                                            action: SnackBarAction(
                                              label: 'Hoàn tác',
                                              onPressed: () {
                                                cartViewModel.addToCart(product,
                                                    quantity: cartItem.quantity);
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              /// Order summary
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    /// Subtotal
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tạm tính:'),
                        Text(formatCurrency(cartViewModel.subtotal)),
                      ],
                    ),

                    const SizedBox(height: 8),

                    /// Tax
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Thuế (10%):'),
                        Text(formatCurrency(cartViewModel.tax)),
                      ],
                    ),

                    const SizedBox(height: 8),

                    /// Shipping
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Vận chuyển:'),
                        Text(
                          cartViewModel.shippingFee == 0
                              ? 'Miễn phí'
                              : formatCurrency(cartViewModel.shippingFee),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    /// Total
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng cộng:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          formatCurrency(cartViewModel.finalTotal),
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    /// Checkout button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Chức năng thanh toán sẽ được cập nhật'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: const Text(
                          'Tiến hành thanh toán',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    /// Continue shopping button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Tiếp tục mua sắm'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
