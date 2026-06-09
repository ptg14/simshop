import 'dart:async';

import 'package:flutter/material.dart';

/// A simple image carousel that automatically scrolls between images.
///
/// The carousel displays each image full‑width within its container and
/// automatically advances to the next image after a fixed interval. The
/// transition is animated using the default page animation.
class ImageCarousel extends StatefulWidget {
  const ImageCarousel({
    super.key,
    required this.imageUrls,
    this.height = 200,
    this.autoScrollDuration = const Duration(seconds: 3),
  });

  /// List of image URLs to display.
  final List<String> imageUrls;

  /// Height of the carousel widget.
  final double height;

  /// How long to wait before automatically scrolling to the next image.
  final Duration autoScrollDuration;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_pageListener);
    if (widget.imageUrls.length > 1) {
      _timer = Timer.periodic(widget.autoScrollDuration, _autoScroll);
    }
  }

  void _pageListener() {
    final int page = _pageController.page?.round() ?? 0;
    if (page != _currentPage) {
      setState(() {
        _currentPage = page;
      });
    }
  }

  void _autoScroll(Timer timer) {
    if (!mounted) return;
    final int nextPage = (_pageController.page?.round() ?? 0) + 1;
    final int targetPage = nextPage % widget.imageUrls.length;
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.removeListener(_pageListener);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            itemBuilder: (context, index) {
              final url = widget.imageUrls[index];
              return Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image, size: 48),
                ),
              );
            },
          ),
          // Indicator dots
          Positioned(
            bottom: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.imageUrls.length, (index) {
                final bool isActive = index == _currentPage;
                // Use MouseRegion to change cursor to a hand (click) on hover
                // and to fill the dot when hovered.
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => setState(() => _hoveredIndex = index),
                  onExit: (_) => setState(() => _hoveredIndex = null),
                  child: GestureDetector(
                    onTap: () => _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Fill the dot if it's the active page or hovered.
                        color: (isActive || index == _hoveredIndex)
                            ? Colors.white
                            : Colors.transparent,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
}
