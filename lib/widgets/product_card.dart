import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/currency_formatter.dart';
import '../utils/responsive.dart';
import 'animated_press.dart';
import 'network_image.dart';

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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heroTag = 'product-image-${product.id}';

    return AnimatedPress(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area with stacked badges.
            Stack(
              children: [
                SizedBox(
                  height: context.productCardImageHeight,
                  width: double.infinity,
                  child: Hero(
                    tag: heroTag,
                    child: AppNetworkImage(
                      url: product.imageUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // Discount badge — pill with offer icon.
                if (product.isOnSale)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_offer,
                              size: 14, color: scheme.onError),
                          const SizedBox(width: 4),
                          Text(
                            '-${product.discountPercentage}%',
                            style: TextStyle(
                              color: scheme.onError,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Stock badge — pill, tertiary container.
                if ((product.stock ?? 0) < 10)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 14, color: scheme.onTertiaryContainer),
                          const SizedBox(width: 4),
                          Text(
                            'Sắp hết',
                            style: TextStyle(
                              color: scheme.onTertiaryContainer,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // Info block.
            Expanded(
              child: Padding(
                padding: context.productCardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: context.productCardNameFontSize,
                        height: 1.3,
                        color: scheme.onSurface,
                      ),
                    ),

                    if (product.options.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: product.options
                            .take(4)
                            .map((o) => _OptionPill(label: o.name))
                            .toList(),
                      ),
                    ],

                    Text(
                      product.category,
                      style: TextStyle(
                        fontSize: context.responsive<double>(
                          mobile: 11,
                          tablet: 12,
                          desktop: 13,
                        ),
                        color: scheme.onSurfaceVariant,
                      ),
                    ),

                    const Spacer(),

                    Row(
                      children: [
                        Text(
                          formatCurrency(product.effectivePayPrice),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: context.productCardPriceFontSize,
                            color: scheme.error,
                          ),
                        ),
                        if (product.isOnSale) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              formatCurrency(product.price),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: context.responsive<double>(
                                  mobile: 11,
                                  tablet: 12,
                                  desktop: 13,
                                ),
                                color: scheme.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      height: context.productCardButtonHeight,
                      child: FilledButton(
                        onPressed: onAddToCart ?? onTap,
                        child: Text(
                          onAddToCart == null
                              ? 'Xem chi tiết'
                              : 'Thêm vào giỏ',
                          style: TextStyle(
                            fontSize: context.responsive<double>(
                              mobile: 12,
                              tablet: 13,
                              desktop: 14,
                            ),
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
}

class _OptionPill extends StatelessWidget {
  const _OptionPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}