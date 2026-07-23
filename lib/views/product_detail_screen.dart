import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/store_info.dart';
import '../utils/responsive.dart';
import '../widgets/site_info_footer.dart';
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

/// Product detail screen — whole-screen redesign (2026-07-23).
///
/// Layout:
///   * Mobile (<600dp): single column — gallery on top, info below.
///   * Tablet/Desktop (≥600dp): 2-column Row — gallery 60% on left,
///     info column 40% on right.
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
    final isWide = context.isTabletOrUp;

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
          if (galleryImages.length > 1)
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

    final info = InfoSection(
      product: product,
      selectedOptionId: _selectedOptionId,
      onSelectOption: (id) => setState(() {
        _selectedOptionId = id;
        _activeImageIndex.value = 0; // reset gallery on option change
      }),
      scheme: scheme,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        centerTitle: true,
      ),
      body: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: [
          Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: context.maxContentWidth),
              child: isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: gallery),
                          Expanded(flex: 2, child: info),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        gallery,
                        info,
                      ],
                    ),
            ),
          ),
          const SiteInfoFooter(),
        ],
      ),
    );
  }
}
