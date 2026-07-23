import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/store_info.dart';
import '../utils/responsive.dart';
import '../widgets/site_info_footer.dart';
import 'product_detail_screen/_details_section.dart';
import 'product_detail_screen/_gallery_section.dart';
import 'product_detail_screen/_info_section.dart';

/// Build a Google Maps *directions* URL with [address] as the
/// destination. The `origin` parameter is omitted so Maps uses the
/// device's current location automatically.
String buildGoogleMapsDirectionsUrl(String address) =>
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}';

/// Prepend `https://` to [url] when it has no scheme.
String _ensureUrlScheme(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://$url';
}

/// Resolve the URL the product detail "Buy at store" CTA should
/// launch, following the user's three-tier flow.
String resolveStoreMapUrl(StoreInfo info) {
  if (info.googleMapsUrl.isNotEmpty) {
    return _ensureUrlScheme(info.googleMapsUrl);
  }
  if (info.address.isNotEmpty) {
    return buildGoogleMapsDirectionsUrl(info.address);
  }
  return '';
}

/// Product detail screen — whole-screen redesign (2026-07-23)
/// + orientation-based layout split.
///
/// Layout:
///   * Portrait (phones + iPad portrait): single column — gallery
///     on top (with the thumbnail strip rendered inside the
///     gallery column), info column below with categories →
///     options → name → price → stock card → description →
///     specs → Buy CTA in vertical order.
///   * Landscape (phones landscape + iPad landscape + PC / laptop):
///     2-column Row — gallery 60% on left, info column 40% on
///     right. The right column stops at the stock card. The
///     thumbnail strip + description + specs + Buy CTA flow below
///     the row at full content width.
///
/// The threshold is orientation-based, not width-based, because
/// iPhone landscape (~932 dp wide) falls under the previous 1024
/// dp width threshold but should still use the 2-column PC
/// layout — see [Breakpoints.productDetailTwoCol] and
/// `context.isProductDetailTwoCol`.
///
/// The gallery uses [GallerySection] (a native `PageView` with a
/// thumbnail strip, keyboard arrows on desktop, and tap-to-lightbox)
/// instead of the shared `ImageCarousel` widget. The shared widget is
/// still used by the home banner + product card; the iOS Safari
/// swipe-stuck bug was specific to the product-detail nesting
/// ([[simshop-product-detail-ios-swipe-stuck]]).
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product product;
  String? _selectedOptionId;
  late final ValueNotifier<int> _activeImageIndex;

  @override
  void initState() {
    super.initState();
    product = widget.product;
    _activeImageIndex = ValueNotifier<int>(0);
  }

  @override
  void dispose() {
    _activeImageIndex.dispose();
    super.dispose();
  }

  List<String> _galleryImages() {
    if (_selectedOptionId != null) {
      for (final o in product.options) {
        if (o.id == _selectedOptionId) {
          if (o.imageUrls.isNotEmpty) return o.imageUrls;
          break;
        }
      }
    }
    if (product.images.isNotEmpty) return product.images;
    return [product.imageUrl];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final galleryImages = _galleryImages();
    final isTwoCol = context.isProductDetailTwoCol;

    // The gallery widget itself (PageView + lightbox tap target).
    // On mobile / iPad portrait we wrap it with the thumbnail strip
    // below; on PC / laptop the strip is rendered below the row
    // instead, so the gallery widget stays a single child.
    final gallery = Container(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          GallerySection(
            key: ValueKey(
                'gallery-${product.id}-${_selectedOptionId ?? 'default'}'),
            images: galleryImages,
            height: context.productDetailImageHeight,
            scheme: scheme,
            activeIndex: _activeImageIndex,
          ),
          if (!isTwoCol && galleryImages.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ThumbnailStrip(
                images: galleryImages,
                activeIndex: _activeImageIndex,
                scheme: scheme,
              ),
            ),
        ],
      ),
    );

    // PC/laptop: the right column only carries the top half
    // (categories → options → name → price → stock card). The
    // bottom half lives in [DetailsSection] below the row.
    final infoTop = InfoSection(
      product: product,
      selectedOptionId: _selectedOptionId,
      onSelectOption: (id) => setState(() {
        _selectedOptionId = id;
        _activeImageIndex.value = 0; // reset gallery on option change
      }),
      scheme: scheme,
      compact: isTwoCol,
    );

    // Post-row block: thumbnail strip (PC only, ≥2 images) + the
    // full details (description + specs + Buy CTA). Skipped on
    // mobile / iPad portrait because [InfoSection(compact: false)]
    // already renders the details in-place inside the info column.
    final Widget postRowContent = isTwoCol
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (galleryImages.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ThumbnailStrip(
                    images: galleryImages,
                    activeIndex: _activeImageIndex,
                    scheme: scheme,
                  ),
                ),
              DetailsSection(product: product, scheme: scheme),
            ],
          )
        : infoTop;

    final Widget body = Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: context.maxContentWidth),
        child: isTwoCol
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: gallery),
                        Expanded(flex: 2, child: infoTop),
                      ],
                    ),
                  ),
                  postRowContent,
                  // SiteInfoFooter is mounted INSIDE the
                  // `maxContentWidth` Container so the footer
                  // banner card stays inside the page's centered
                  // column on PC / laptop. Previously the footer
                  // was a sibling of `body` at the ListView level,
                  // which let it stretch full-bleed (banner image
                  // has `width: double.infinity`) and looked
                  // detached from the rest of the content.
                  const SiteInfoFooter(),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  gallery,
                  infoTop, // compact: false → renders details in-place
                  const SiteInfoFooter(),
                ],
              ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        centerTitle: true,
      ),
      body: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: [body],
      ),
    );
  }
}
