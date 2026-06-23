import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/currency_formatter.dart';
import '../utils/responsive.dart';

/// Product detail screen.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product product;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    product = ModalRoute.of(context)?.settings.arguments as Product? ??
        Product(
          id: '1',
          name: 'Product Name',
          description: 'Description',
          price: 1000000,
          imageUrl: '',
          category: 'Category',
          rating: 0,
          reviews: 0,
          stock: 0,
          specs: [],
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Chi tiết sản phẩm'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Product image
              Container(
                height: context.productDetailImageHeight,
                width: double.infinity,
                color: Colors.grey[200],
                child: Stack(
                  children: [
                    Center(
                      child: Image.network(
                        product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.image_not_supported, size: 80),
                          ),
                        ),
                      ),
                    ),

                    /// Discount badge
                    if (product.isOnSale)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'GIÁ CŨ: ${formatCurrency(product.originalPrice ?? 0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),

                    /// Back button
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              /// Product details
              Padding(
                padding: EdgeInsets.all(context.horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Category
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        product.category,
                        style: TextStyle(
                          color: Colors.blue[800],
                          fontWeight: FontWeight.w500,
                          fontSize: context.responsive<double>(
                            mobile: 12,
                            tablet: 13,
                            desktop: 14,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 12,
                      tablet: 16,
                      desktop: 20,
                    )),

                    /// Product name
                    Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.responsive<double>(
                          mobile: 20,
                          tablet: 24,
                          desktop: 28,
                        ),
                        height: 1.3,
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 12,
                      tablet: 16,
                      desktop: 20,
                    )),

                    /// Price
                    Row(
                      children: [
                        Text(
                          formatCurrency(product.price),
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: context.responsive<double>(
                              mobile: 24,
                              tablet: 28,
                              desktop: 32,
                            ),
                          ),
                        ),
                        if (product.isOnSale) ...[
                          SizedBox(
                              width: context.responsive<double>(
                            mobile: 12,
                            tablet: 16,
                            desktop: 20,
                          )),
                          Text(
                            formatCurrency(product.originalPrice ?? 0),
                            style: TextStyle(
                              color: Colors.grey[600],
                              decoration: TextDecoration.lineThrough,
                              fontSize: context.responsive<double>(
                                mobile: 16,
                                tablet: 18,
                                desktop: 20,
                              ),
                            ),
                          ),
                          SizedBox(
                              width: context.responsive<double>(
                            mobile: 12,
                            tablet: 16,
                            desktop: 20,
                          )),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Giảm ${product.discountPercentage}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: context.responsive<double>(
                                  mobile: 12,
                                  tablet: 13,
                                  desktop: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 16,
                      tablet: 20,
                      desktop: 24,
                    )),

                    /// Stock info
                    Container(
                      padding: EdgeInsets.all(context.responsive<double>(
                        mobile: 12,
                        tablet: 14,
                        desktop: 16,
                      )),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        border: Border.all(color: Colors.amber[200]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              color: Colors.amber),
                          const SizedBox(width: 8),
                          Text(
                            'Còn ${product.stock ?? 0} sản phẩm',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: context.responsive<double>(
                                mobile: 14,
                                tablet: 15,
                                desktop: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 24,
                      tablet: 28,
                      desktop: 32,
                    )),

                    /// Description
                    Text(
                      'Mô tả sản phẩm',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: context.responsive<double>(
                          mobile: 16,
                          tablet: 18,
                          desktop: 20,
                        ),
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 8,
                      tablet: 10,
                      desktop: 12,
                    )),

                    Text(
                      product.description,
                      style: TextStyle(
                        color: Colors.grey[700],
                        height: 1.5,
                        fontSize: context.responsive<double>(
                          mobile: 14,
                          tablet: 15,
                          desktop: 16,
                        ),
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 24,
                      tablet: 28,
                      desktop: 32,
                    )),

                    /// Specifications
                    if (product.specs.isNotEmpty) ...[
                      Text(
                        'Thông số kỹ thuật',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: context.responsive<double>(
                            mobile: 16,
                            tablet: 18,
                            desktop: 20,
                          ),
                        ),
                      ),
                      SizedBox(
                          height: context.responsive<double>(
                        mobile: 12,
                        tablet: 14,
                        desktop: 16,
                      )),
                      ...product.specs.map((spec) => Padding(
                            padding: EdgeInsets.only(
                              bottom: context.responsive<double>(
                                mobile: 8,
                                tablet: 10,
                                desktop: 12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.green,
                                    size: context.responsive<double>(
                                      mobile: 20,
                                      tablet: 22,
                                      desktop: 24,
                                    )),
                                SizedBox(
                                    width: context.responsive<double>(
                                  mobile: 12,
                                  tablet: 14,
                                  desktop: 16,
                                )),
                                Expanded(
                                  child: Text(
                                    spec,
                                    style: TextStyle(
                                      fontSize: context.responsive<double>(
                                        mobile: 14,
                                        tablet: 15,
                                        desktop: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                      SizedBox(
                          height: context.responsive<double>(
                        mobile: 24,
                        tablet: 28,
                        desktop: 32,
                      )),
                    ],

                    /// Button to go to admin dashboard
                    SizedBox(
                      width: double.infinity,
                      height: context.responsive<double>(
                        mobile: 56,
                        tablet: 52,
                        desktop: 48,
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushNamed(context, '/admin'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        child: Text(
                          'VÀO BẢNG ĐIỀU KHIỂN ADMIN',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: context.responsive<double>(
                              mobile: 16,
                              tablet: 15,
                              desktop: 14,
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                        height: context.responsive<double>(
                      mobile: 12,
                      tablet: 14,
                      desktop: 16,
                    )),

                    /// Buy now button
                    SizedBox(
                      width: double.infinity,
                      height: context.responsive<double>(
                        mobile: 56,
                        tablet: 52,
                        desktop: 48,
                      ),
                      child: OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Chức năng mua ngay sẽ được cập nhật'),
                            ),
                          );
                        },
                        child: Text(
                          'MUA NGAY',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: context.responsive<double>(
                              mobile: 16,
                              tablet: 15,
                              desktop: 14,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
