import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product.dart';
import '../utils/currency_formatter.dart';
import '../utils/responsive.dart';
import '../viewmodels/site_config_viewmodel.dart';
import '../widgets/network_image.dart';
import '../widgets/site_info_footer.dart';

/// Build a Google Maps "search" URL for [address]. The query parameter
/// is URL-encoded so Vietnamese diacritics and commas round-trip
/// safely through the browser's intent dispatch on Android and
/// `openURL:` on iOS.
String buildGoogleMapsSearchUrl(String address) =>
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}';

/// Product detail screen.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product product;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    product = widget.product;
  }

  Future<void> _openMap(String address) async {
    final uri = Uri.parse(buildGoogleMapsSearchUrl(address));
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isFavorite ? 'Đã thêm vào yêu thích' : 'Đã bỏ yêu thích'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heroTag = 'product-image-${product.id}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _isFavorite ? 'Bỏ yêu thích' : 'Yêu thích',
            onPressed: _toggleFavorite,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(_isFavorite),
                color: _isFavorite ? scheme.error : null,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// Product image with Hero animation.
                SizedBox(
                  height: context.productDetailImageHeight,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Hero(
                          tag: heroTag,
                          child: AppNetworkImage(
                            url: product.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

                      /// Discount ribbon
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
                              color: scheme.error,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'GIÁ CŨ: ${formatCurrency(product.originalPrice ?? 0)}',
                              style: TextStyle(
                                color: scheme.onError,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
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
                      /// Category pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          product.category,
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
                          color: scheme.onSurface,
                          height: 1.3,
                        ),
                      ),

                      SizedBox(
                          height: context.responsive<double>(
                        mobile: 12,
                        tablet: 16,
                        desktop: 20,
                      )),

                      /// Price row
                      Row(
                        children: [
                          Text(
                            formatCurrency(product.price),
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
                            SizedBox(
                                width: context.responsive<double>(
                              mobile: 12,
                              tablet: 16,
                              desktop: 20,
                            )),
                            Flexible(
                              child: Text(
                                formatCurrency(product.originalPrice ?? 0),
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
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                color: scheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              'Còn ${product.stock ?? 0} sản phẩm',
                              style: TextStyle(
                                color: scheme.onTertiaryContainer,
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
                          color: scheme.onSurface,
                        ),
                      ),

                      SizedBox(
                          height: context.responsive<double>(
                        mobile: 8,
                        tablet: 10,
                        desktop: 12,
                      )),

                      MarkdownBody(
                        data: product.description.isEmpty
                            ? '_(Sản phẩm chưa có mô tả)_'
                            : product.description,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(
                            Theme.of(context)),
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
                            color: scheme.onSurface,
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
                                      color: scheme.primary,
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
                                        color: scheme.onSurface,
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

                      /// Buy at store CTA: opens Google Maps and searches
                      /// for the store address. Hidden entirely when
                      /// the address is empty so end users on an
                      /// unconfigured install don't see a dead button.
                      Consumer<SiteConfigViewModel>(
                        builder: (context, vm, _) {
                          final address = vm.siteInfo.address;
                          if (address.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return SizedBox(
                            key: const Key('buy-at-store-cta'),
                            width: double.infinity,
                            height: context.responsive<double>(
                              mobile: 56,
                              tablet: 52,
                              desktop: 48,
                            ),
                            child: FilledButton.icon(
                              onPressed: () => _openMap(address),
                              icon: const Icon(Icons.place_outlined),
                              label: Text(address),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
                const SiteInfoFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
