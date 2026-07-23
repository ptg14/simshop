import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lightbox_screen.dart';

/// Inline product gallery for the product-detail screen.
///
/// Replaces the shared `ImageCarousel` widget on this screen only
/// (the shared widget is still used by the home banner). Three
/// navigation paths feed the same `PageController`:
///
///   * Tap on a thumbnail (`onTap` → `animateToPage`)
///   * Swipe the main `PageView` (built-in horizontal drag)
///   * Keyboard `ArrowLeft` / `ArrowRight` (desktop only, via
///     `Focus.onKeyEvent`)
///
/// Tap on the main image pushes [LightboxScreen] for pinch-zoom +
/// full-screen swipe. We deliberately use [photo_view] for the
/// lightbox (not a nested PageView) because `photo_view` owns its
/// own gesture detection inside its own subtree, sidestepping the
/// iOS gesture-arena problem entirely — see
/// [[simshop-product-detail-ios-swipe-stuck]].
class GallerySection extends StatefulWidget {
  const GallerySection({
    super.key,
    required this.images,
    required this.height,
    required this.scheme,
    this.activeIndex,
  });

  final List<String> images;
  final double height;
  final ColorScheme scheme;

  /// Shared state with the [ThumbnailStrip]. When non-null, the
  /// gallery writes its current page to this notifier on every
  /// `onPageChanged`; the strip listens to update its highlight.
  final ValueNotifier<int>? activeIndex;

  @override
  State<GallerySection> createState() => _GallerySectionState();
}

class _GallerySectionState extends State<GallerySection> {
  late final PageController _pageController;
  int _activeIndex = 0;

  // The notifier we are currently subscribed to. Tracked so we can
  // detach the listener in dispose / didUpdateWidget when the
  // parent's notifier reference changes.
  ValueNotifier<int>? _subscribedNotifier;
  late final void Function() _notifierListener;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Stored as a tear-off so we can pass the same reference to
    // removeListener later.
    _notifierListener = _onNotifierChanged;
    _subscribeToNotifier(widget.activeIndex);
  }

  @override
  void didUpdateWidget(GallerySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.activeIndex, oldWidget.activeIndex)) {
      _subscribeToNotifier(widget.activeIndex);
    }
  }

  void _subscribeToNotifier(ValueNotifier<int>? notifier) {
    if (identical(_subscribedNotifier, notifier)) return;
    if (_subscribedNotifier != null) {
      _subscribedNotifier!.removeListener(_notifierListener);
    }
    _subscribedNotifier = notifier;
    _subscribedNotifier?.addListener(_notifierListener);
  }

  /// Reacts to external writes to [widget.activeIndex] — typically
  /// from [ThumbnailStrip] when the user taps a thumbnail. Writes
  /// from `_next` / `_previous` are filtered out (`notifier.value`
  /// already matches `_activeIndex`) so we never feed back into our
  /// own animation.
  void _onNotifierChanged() {
    final notifier = _subscribedNotifier;
    if (notifier == null) return;
    final target = notifier.value;
    if (target == _activeIndex) return; // we wrote this ourselves
    if (target < 0 || target >= widget.images.length) return;
    if (!_pageController.hasClients) return; // not attached yet
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    setState(() => _activeIndex = target);
  }

  @override
  void dispose() {
    _subscribedNotifier?.removeListener(_notifierListener);
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_activeIndex < widget.images.length - 1) {
      final next = _activeIndex + 1;
      // Update our own index FIRST so the listener (when we write
      // the notifier below) sees `target == _activeIndex` and skips
      // its own redundant `animateToPage`.
      setState(() => _activeIndex = next);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      // The notifier will also be updated by onPageChanged when the
      // animation settles — but writing here too gives an immediate
      // visual response (the thumbnail strip's highlight) to
      // keyboard arrows / chevron taps, without waiting 250 ms for
      // the animation.
      widget.activeIndex?.value = next;
    }
  }

  void _previous() {
    if (_activeIndex > 0) {
      final prev = _activeIndex - 1;
      setState(() => _activeIndex = prev);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      widget.activeIndex?.value = prev;
    }
  }

  /// Whether the current platform has a real keyboard. Mirrors the
  /// `_hasMousePointer` helper in `image_carousel.dart`. Touch
  /// platforms (iOS/Android) leave keyboard focus disabled so
  /// typing still goes into form fields elsewhere — and the
  /// floating chevron buttons are not rendered, so they don't
  /// steal swipe area from the [PageView].
  static bool get _hasKeyboard {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();
    final scheme = widget.scheme;

    return Focus(
      autofocus: _hasKeyboard,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _previous();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _next();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) {
                  setState(() => _activeIndex = i);
                  widget.activeIndex?.value = i;
                },
                itemCount: widget.images.length,
                itemBuilder: (context, i) => GestureDetector(
                  key: const Key('main-image-tap-target'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => LightboxScreen(
                      images: widget.images,
                      initialIndex: i,
                    ),
                  )),
                  child: CachedNetworkImage(
                    imageUrl: widget.images[i],
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(
                      color: scheme.surfaceContainerLowest,
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: scheme.surfaceContainerLowest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: scheme.onSurfaceVariant,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Dot indicators — visible on every platform with >1 image.
            if (widget.images.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.images.length, (i) {
                    final isActive = i == _activeIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isActive ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),

            // Desktop chevron buttons — touch platforms never see these.
            if (_hasKeyboard) ...[
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    onPressed: _activeIndex > 0 ? _previous : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    onPressed:
                        _activeIndex < widget.images.length - 1 ? _next : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Test-only accessor for the currently active page index.
  @visibleForTesting
  int get activeIndex => _activeIndex;
}

/// Thumbnail strip rendered below [GallerySection] when the
/// product has more than one image. Each thumbnail is a tap target
/// that drives the gallery's [PageController] via the shared
/// [ValueNotifier] (writing to the notifier from the strip also
/// animates the gallery's PageView via the [GallerySection] state).
class ThumbnailStrip extends StatelessWidget {
  const ThumbnailStrip({
    super.key,
    required this.images,
    required this.activeIndex,
    required this.scheme,
    this.onTap,
  });

  final List<String> images;
  final ValueNotifier<int> activeIndex;
  final ColorScheme scheme;

  /// Optional callback fired when the user taps a thumbnail. The
  /// gallery typically drives its own [PageController] from this tap
  /// (via the [activeIndex] notifier the gallery writes back to),
  /// but the caller can wire up side effects (analytics, etc.) here.
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ValueListenableBuilder<int>(
        valueListenable: activeIndex,
        builder: (context, current, _) {
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: images.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final isActive = i == current;
              return GestureDetector(
                onTap: () {
                  // Forward to the gallery by writing the same
                  // notifier — gallery listens and animates its
                  // PageController to the new index.
                  activeIndex.value = i;
                  onTap?.call(i);
                },
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isActive ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: images[i],
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: scheme.surfaceContainerLowest,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
