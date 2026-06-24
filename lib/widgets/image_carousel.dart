import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'network_image.dart';

/// Auto-scrolling image carousel with rounded corners and animated indicator.
class ImageCarousel extends StatefulWidget {
  const ImageCarousel({
    super.key,
    required this.imageUrls,
    this.height,
    this.autoScrollDuration = const Duration(seconds: 3),
  });

  final List<String> imageUrls;
  final double? height;
  final Duration autoScrollDuration;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    if (widget.imageUrls.length < 2) return;
    _timer = Timer.periodic(widget.autoScrollDuration, (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_current + 1) % widget.imageUrls.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              height: widget.height ?? context.carouselHeight,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _current = i),
                itemCount: widget.imageUrls.length,
                itemBuilder: (context, index) => AppNetworkImage(
                  url: widget.imageUrls[index],
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.imageUrls.length, (i) {
                    final isActive = i == _current;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}