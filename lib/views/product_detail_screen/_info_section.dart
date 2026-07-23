import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive.dart';
import '_details_section.dart';

/// Right column (or below-gallery section on mobile) of the
/// product-detail screen. Extracted from the inline `Column` so
/// the 2-column layout on tablet/desktop can mount it as a
/// sibling of [GallerySection].
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.product,
    required this.selectedOptionId,
    required this.onSelectOption,
    required this.scheme,
    this.compact = false,
  });

  final Product product;
  final String? selectedOptionId;
  final ValueChanged<String?> onSelectOption;
  final ColorScheme scheme;

  /// When true, render ONLY the top half of the info column —
  /// categories → options → name → price → stock card. Description,
  /// specs and the Buy CTA are moved to [DetailsSection] so the
  /// PC/laptop 2-column layout can place them below the row in the
  /// main flow. Mobile / iPad portrait pass `compact: false` so
  /// this widget still owns the full info column (current behavior).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (context.isProductDetailTwoCol && product.isOnSale)
            _DiscountRibbon(product: product, scheme: scheme),

          if (product.categories.any((c) => c.trim().isNotEmpty)) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: product.categories
                  .where((c) => c.trim().isNotEmpty)
                  .map((cat) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                            fontSize: context.responsive<double>(
                              mobile: 12,
                              tablet: 13,
                              desktop: 14,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 16,
                desktop: 20,
              ),
            ),
          ],

          if (product.options.isNotEmpty) ...[
            Text(
              'Tuỳ chọn',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.responsive<double>(
                  mobile: 14,
                  tablet: 15,
                  desktop: 16,
                ),
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Mặc định'),
                  selected: selectedOptionId == null,
                  onSelected: (_) => onSelectOption(null),
                ),
                for (final o in product.options)
                  ChoiceChip(
                    label: Text(o.name),
                    selected: selectedOptionId == o.id,
                    onSelected: (_) => onSelectOption(o.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          Text(
            product.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 20,
                tablet: 24,
                desktop: 28,
              ),
              color: scheme.onSurface,
              height: 1.3,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          _PriceRow(product: product, scheme: scheme),
          SizedBox(
            height: context.responsive<double>(
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _StockCard(product: product, scheme: scheme),
          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
          // compact = true: end the right column here. Description,
          // specs and the Buy CTA are owned by [DetailsSection] and
          // mounted directly below the row by the screen (PC/laptop).
          // compact = false: render the bottom half inside this same
          // widget so the mobile / iPad-portrait path is unchanged
          // from before the layout split.
          if (!compact) DetailsSection(product: product, scheme: scheme),
        ],
      ),
    );
  }
}

class _DiscountRibbon extends StatelessWidget {
  const _DiscountRibbon({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          product.currentEvent != null
              ? 'GIÁ SỰ KIỆN: ${product.currentEvent!.formatDiscount()}'
                  '${product.currentEvent!.name.isEmpty ? '' : ' · ${product.currentEvent!.name}'}'
              : 'GIÁ CŨ: ${formatCurrency(product.originalPrice ?? 0)}',
          style: TextStyle(
            color: scheme.onError,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    // On PC/laptop the right column on the 2-col layout is
    // ~480 dp wide minus 96 dp horizontalPadding = 384 dp of
    // content. Price text + strikethrough + 20 dp gap + 20 dp gap
    // + discount chip at desktop font sizes overflows that. Wrap
    // in a [Wrap] so children flow to a second row when the
    // column is narrow instead of overflowing. Gap tokens mirror
    // the original [Row] layout — they become [Wrap.spacing] when
    // children fit on one line.
    return Wrap(
      spacing: context.responsive<double>(
        mobile: 12,
        tablet: 16,
        desktop: 20,
      ),
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          formatCurrency(product.effectivePayPrice),
          style: TextStyle(
            color: scheme.error,
            fontWeight: FontWeight.bold,
            fontSize: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
        ),
        if (product.isOnSale) ...[
          Text(
            formatCurrency(product.price),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              fontSize: context.responsive<double>(
                mobile: 16,
                tablet: 18,
                desktop: 20,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '-${product.discountPercentage}%',
              style: TextStyle(
                color: scheme.onError,
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
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.responsive<double>(
        mobile: 12,
        tablet: 14,
        desktop: 16,
      )),
      decoration: BoxDecoration(
        color: product.isOutOfStock
            ? scheme.errorContainer
            : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            product.isOutOfStock
                ? Icons.do_disturb_alt_outlined
                : Icons.inventory_2_outlined,
            color: product.isOutOfStock
                ? scheme.onErrorContainer
                : scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              () {
                if (product.isOutOfStock) return 'Hết hàng';
                if (product.stock == null) {
                  return 'Số lượng không xác định';
                }
                return 'Còn ${product.stock} sản phẩm';
              }(),
              style: TextStyle(
                color: product.isOutOfStock
                    ? scheme.onErrorContainer
                    : scheme.onTertiaryContainer,
                fontWeight: FontWeight.w600,
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
    );
  }
}
