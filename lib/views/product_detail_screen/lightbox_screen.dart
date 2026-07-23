import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Fullscreen photo viewer for the product-detail gallery.
///
/// Pushed as `MaterialPageRoute(fullscreenDialog: true)` when the
/// customer taps the inline gallery's main image. Uses
/// [PhotoViewGallery] from `package:photo_view` because it has its
/// own gesture detection (pinch-zoom, double-tap-zoom, swipe) and
/// does NOT participate in any gesture arena with the parent
/// scroll view — sidesteps the iOS Safari swipe-stuck bug that
/// bit the original `ImageCarousel` (see
/// [[simshop-product-detail-ios-swipe-stuck]]).
class LightboxScreen extends StatelessWidget {
  const LightboxScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  /// Image URLs to display, in order. The caller is expected to
  /// pass the *currently visible* gallery (product images or
  /// option images), not the full product image set.
  final List<String> images;

  /// Page index to show first. Set to the inline gallery's
  /// `_activeIndex` at the moment of the tap.
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoViewGallery.builder(
              itemCount: images.length,
              pageController: PageController(initialPage: initialIndex),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              builder: (context, i) => PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(images[i]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
              ),
            ),
          ),
          Positioned(
            top: padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
