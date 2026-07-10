import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/currency_formatter.dart';
import '../utils/responsive.dart';
import 'animated_press.dart';
import 'network_image.dart';
import 'product_card_pills.dart';

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
    // Pre-compute non-empty category list so we can decide whether
    // to render the pill row OR fall back to the placeholder. If we
    // left this inline in the `children:` list Flutter would reject
    // it (statements aren't allowed inside a list literal). The
    // filter also drops stray empty strings: an admin who clears
    // every category but whose backend still echoes back one ghost
    // entry (a `""` element) used to render as a coloured pill with
    // no label — which looked like a stray pink oval.
    final nonEmptyCategories = product.categories
        .where((c) => c.isNotEmpty)
        .toList(growable: false);

    return AnimatedPress(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        // Intrinsic height: the Column collapses to (image + info
        // content). The grid's [childAspectRatio] is tuned so the
        // cell is exactly that height for the worst-case product —
        // so no blank strip appears above or below the card, and
        // every card in a row sits flush against its cell borders.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image area with stacked badges. The image uses [BoxFit.contain]
            // (instead of cover) so the customer sees the full product
            // rather than a centre-cropped square — covers tend to
            // chop off product labels, logos, or key features at the
            // top/bottom. The Card's surface colour shows through the
            // letterboxing, which is fine for product photography on
            // a near-white background.
            Stack(
              children: [
                SizedBox(
                  height: context.productCardImageHeight,
                  width: double.infinity,
                  child: Hero(
                    tag: heroTag,
                    child: ColoredBox(
                      color: scheme.surface,
                      child: AppNetworkImage(
                        url: product.imageUrl,
                        fit: BoxFit.contain,
                      ),
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
                //
                // Two distinct states the badge must NOT confuse:
                //   stock == 0 → out of stock (red "Hết hàng" badge
                //                 on the bottom-left corner; the
                //                 detail screen also surfaces this)
                //   0 < stock < 10 → "Sắp hết" (amber pill, top-left)
                //
                // The previous `(stock ?? 0) < 10` lumped both states
                // together and showed "Sắp hết" on a product with 0
                // units, which is misleading.
                if ((product.stock ?? 0) > 0 && (product.stock ?? 0) < 10)
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

                // Out-of-stock badge — bottom-left, errorContainer
                // so it reads as a hard "not available" rather than
                // the warning-amber "Sắp hết" above. Renders on top
                // of the discount badge if both apply, which is the
                // right hierarchy: stock availability > price.
                if (product.isOutOfStock)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.do_disturb_alt_outlined,
                              size: 14, color: scheme.onErrorContainer),
                          const SizedBox(width: 4),
                          Text(
                            'Hết hàng',
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // Info block. Intrinsic height — Column collapses to its
            // content (name → options/categories → price → button)
            // with no [Spacer] or [Expanded], so no blank strip
            // appears between the name and the option pills, and
            // no blank strip appears below the "Xem chi tiết"
            // button.
            //
            // The grid's [childAspectRatio] is tuned so the cell
            // is exactly the height of the worst-case product
            // card (all rows populated). When options or
            // categories are missing, a placeholder [SizedBox] of
            // the same height as the real pill row keeps the
            // price+button baseline aligned with cards that have
            // all fields — so every card in a row has the same
            // content layout, and no card looks "thinner" than
            // another.
            //
            // [ClipRect] is a defensive guard against the rare
            // case where the 2-line name renders taller than
            // expected on a very narrow phone — the clip prevents
            // a RenderFlex overflow stripe instead of crashing.
            ClipRect(
              child: Padding(
                padding: context.productCardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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

                    // Options row. If the product has no options,
                    // render a placeholder [SizedBox] of the same
                    // height (pill row ~22dp) so the categories row
                    // underneath sits at the same y-coordinate on
                    // every card.
                    if (product.options.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: buildPillRow(
                          items: product.options.map((o) => o.name).toList(),
                          pillBuilder: (label) => OptionPill(label: label),
                          // Cap at 2 chips; tail collapses into "+N"
                          // so the card width is bounded (mobile card
                          // has ~285dp of horizontal room).
                          maxVisible: 2,
                        ),
                      ),
                    ] else
                      const SizedBox(height: 28),

                    // Categories row. Render only when the product has at least one
// category. Crucially we don't fall back to the legacy
// [Product.category] string when [Product.categories] is an
// explicit empty list — that would re-attach a category the admin
// had just removed (admin removes all categories, the request body
// sends `categories: []`, but the backend still echoes back the
// old singular `category` string). Pill row skipped entirely →
                    // placeholder SizedBox keeps the price baseline
                    // aligned with cards that have categories.
                    // `.where((c) => c.isNotEmpty)` (applied in `build` above via
                    // [nonEmptyCategories]) drops stray empty
                    // strings — admin cleared the field but the
                    // list still carried a ghost entry that would
                    // render as a coloured pill with no label. With
                    // the filter the row degrades to the placeholder
                    // SizedBox so no pill shows up when every
                    // category is empty.
                    if (nonEmptyCategories.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: buildPillRow(
                          items: nonEmptyCategories,
                          pillBuilder: (label) => CategoryPill(label: label),
                          maxVisible: 2,
                        ),
                      ),
                    ] else
                      const SizedBox(height: 28),

                    // Price row. Immediately below the categories
                    // row (or its placeholder), no extra gap.
                    const SizedBox(height: 8),
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

