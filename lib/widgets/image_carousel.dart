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
    this.onTap,
    this.fit = BoxFit.cover,
    this.heroTag,
  });

  final List<String> imageUrls;
  final double? height;
  final Duration autoScrollDuration;

  /// Called when the user taps a slide. Receives the slide index.
  /// When null (default), the carousel is non-interactive.
  final void Function(int index)? onTap;

  /// How each image fills its frame. Default [BoxFit.cover] keeps
  /// the existing banner + product-card behaviour (image fills the
  /// frame, edges get cropped). Product detail uses
  /// [BoxFit.contain] so the customer sees the full photo with
  /// letterboxing instead of having the product zoomed in and
  /// cropped.
  final BoxFit fit;

  /// When non-null, wraps the *first* slide in a [Hero] with this
  /// exact tag — matching the [Hero] tag used by the product card
  /// on the home grid (e.g. `'product-image-<product.id>'`). The
  /// fly-in animation from the home card then transitions smoothly
  /// into the carousel. Only the first slide is wrapped because the
  /// home grid only shows one image; subsequent slides are revealed
  /// via the carousel's own PageView motion.
  final Object? heroTag;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel>
    with WidgetsBindingObserver {
  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoScroll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Pause when the tab/window is hidden — keeps the page change from
    // firing while the user isn't watching and avoids background
    // PageView animations that compete with the active frame. Resuming
    // picks up the existing `_current` so the carousel doesn't jump.
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        _timer?.cancel();
        _timer = null;
        break;
      case AppLifecycleState.resumed:
        if (_timer == null && widget.imageUrls.length >= 2) {
          _startAutoScroll();
        }
        break;
      case AppLifecycleState.detached:
        _timer?.cancel();
        _timer = null;
        break;
    }
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
                itemBuilder: (context, index) {
                  Widget child = AppNetworkImage(
                    url: widget.imageUrls[index],
                    fit: widget.fit,
                    // Explicit dimensions let the browser decode at
                    // the actual display size instead of first
                    // downloading the full-resolution image and
                    // resizing it in CSS — meaningful for first-paint
                    // when banners are large product shots.
                    height: widget.height ?? context.carouselHeight,
                    width: double.infinity,
                  );
                  if (widget.onTap != null) {
                    child = InkWell(
                      onTap: () => widget.onTap!(index),
                      child: child,
                    );
                  }
                  // Wrap only the first slide in a Hero. The home
                  // grid (ProductCard) uses a tag shaped like
                  // `'product-image-<id>'`; the detail screen
                  // passes the same tag in via [heroTag] so the
                  // fly-in animation matches. The shuttle builder
                  // renders the destination widget during flight
                  // so we don't briefly show the source's
                  // cover-fit image (with cropped edges) on its
                  // way to a contain-fit frame — the user would
                  // see a visible snap at the start of the
                  // animation.
                  if (widget.heroTag != null && index == 0) {
                    child = Hero(
                      tag: widget.heroTag!,
                      flightShuttleBuilder: (
                        flightContext,
                        animation,
                        flightDirection,
                        fromHeroContext,
                        toHeroContext,
                      ) =>
                          toHeroContext.widget,
                      child: child,
                    );
                  }
                  return child;
                },
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