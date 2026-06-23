import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/currency_formatter.dart';
import '../utils/responsive.dart';

/// Widget displaying a product card.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onAddToCart,
  });
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Product image
              Stack(
                children: [
                  Container(
                    height: context.productCardImageHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Image.network(
                      product.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                  ),

                  /// Discount badge
                  if (product.isOnSale)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '-${product.discountPercentage}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: context.productCardPriceFontSize,
                          ),
                        ),
                      ),
                    ),

                  /// Stock status
                  if ((product.stock ?? 0) < 10)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Sắp hết',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.productCardPriceFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              /// Product info
              Expanded(
                child: Padding(
                  padding: context.productCardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// Product name
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: context.productCardNameFontSize,
                          height: 1.3,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Option mini-review: show small chips for option names
                      if (product.options.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: product.options
                                .take(4)
                                .map((o) => Chip(
                                      label: Text(
                                        o.name,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      backgroundColor: Colors.grey[100],
                                    ))
                                .toList(),
                          ),
                        ),

                      /// Category
                      Text(
                        product.category,
                        style: TextStyle(
                          fontSize: context.responsive<double>(
                            mobile: 11,
                            tablet: 12,
                            desktop: 13,
                          ),
                          color: Colors.grey[600],
                        ),
                      ),

                      const Spacer(),

                      const SizedBox(height: 6),

                      /// Price
                      Row(
                        children: [
                          Text(
                            formatCurrency(product.price),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: context.productCardPriceFontSize,
                              color: Colors.red,
                            ),
                          ),
                          if (product.isOnSale) ...[
                            const SizedBox(width: 6),
                            Text(
                              formatCurrency(product.originalPrice ?? 0),
                              style: TextStyle(
                                fontSize: context.responsive<double>(
                                  mobile: 11,
                                  tablet: 12,
                                  desktop: 13,
                                ),
                                color: Colors.grey[600],
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 8),

                      /// View details button
                      if (onAddToCart == null)
                        SizedBox(
                          width: double.infinity,
                          height: context.productCardButtonHeight,
                          child: ElevatedButton(
                            onPressed: onTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E88E5),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Xem chi tiết',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.responsive<double>(
                                  mobile: 12,
                                  tablet: 13,
                                  desktop: 14,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: context.productCardButtonHeight,
                          child: ElevatedButton(
                            onPressed: onAddToCart,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E88E5),
                              padding: EdgeInsets.zero,
                            ),
                            child: Text(
                              'Thêm vào giỏ',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.responsive<double>(
                                  mobile: 12,
                                  tablet: 13,
                                  desktop: 14,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
