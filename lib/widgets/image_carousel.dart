import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'carousel/carousel_nav_button.dart';
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
    this.showNavigationButtons = false,
    this.useHorizontalPadding = true,
  });

  final List<String> imageUrls;
  final double? height;
  final Duration autoScrollDuration;

  /// Called when the user taps a slide. Receives the slide index.
  /// When null (default), the carousel is non-interactive.
  final void Function(int index)? onTap;

  /// When true, the carousel renders circular prev/next buttons
  /// floating over the left and right edges. The product-detail
  /// screen opts in (manual navigation, no auto-scroll); the home
  /// banner carousel leaves it off because the auto-advance + dot
  /// indicator is enough and the buttons would compete with the
  /// customer's first instinct to scroll the page. The buttons
  /// are only rendered when there is more than one image — a
  /// single-image carousel has nothing to advance to.
  final bool showNavigationButtons;

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

  /// Whether to wrap the carousel in [EdgeInsets.symmetric] using
  /// `context.horizontalPadding` (12 / 24 / 48 dp on mobile / tablet /
  /// desktop). Defaults to `true` so the home banner and product
  /// card carousels keep their responsive gutter.
  ///
  /// Set to `false` when the caller has already placed the carousel
  /// inside a full-width container with its own background — most
  /// commonly the product detail screen, which puts the carousel
  /// inside a `Container(width: double.infinity, color: surface)`
  /// that doubles as the letterbox background for `BoxFit.contain`.
  /// Adding a second horizontal padding on top of that container
  /// leaves the caller's letterbox background visible as a white
  /// stripe down both sides — the image looks "framed" instead of
  /// filling the screen.
  final bool useHorizontalPadding;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel>
    with WidgetsBindingObserver {
  final PageController _controller = PageController();
  int _current = 0;
  Timer? _timer;

  /// Track ongoing manual drag. When the user starts a horizontal
  /// drag on the carousel we disable the [PageView]'s built-in
  /// horizontal drag detector (via [PageView.physics] -> never
  /// scrollable) and instead drive the [PageController] ourselves
  /// from the surrounding [GestureDetector]. This bypasses the
  /// gesture arena entirely: the carousel always wins the
  /// horizontal swipe, even when it's nested inside a vertical
  /// [SingleChildScrollView] whose content is short enough to be
  /// sitting at the top of its scroll bounds (which is exactly
  /// when a vanilla [PageView] appears "stuck" on mobile).
  ///
  /// `_dragStartControllerOffset` is captured at the start of each
  /// drag so the delta we feed the controller is always measured
  /// from the same origin — using `controller.offset` directly is
  /// racy because the controller may have been auto-scrolled since
  /// the last frame.
  double? _dragStartControllerOffset;
  double _dragTotal = 0;

  /// True while the pointer (mouse / trackpad) is hovering over
  /// the carousel. The nav buttons fade in on hover and out when
  /// the cursor leaves, so the photos stay clean by default and
  /// controls only appear when the customer has actually pointed
  /// at the image.
  ///
  /// Always `false` initially: the nav-button row is gated on
  /// [_hasMousePointer] further down, so this state is only ever
  /// meaningful on desktop. The flag is final because the
  /// desktop-only toggle in [_MouseRegion]'s callbacks never needs
  /// to mutate the storage location, only the field's value.
  bool _isHovered = false;

  /// Whether the current platform exposes a real pointer (mouse /
  /// trackpad). When false the carousel drops the nav buttons
  /// entirely so [PageView] keeps full ownership of horizontal
  /// swipes — touch platforms have no hover affordance and no
  /// use for the buttons, and rendering them silently breaks
  /// manual navigation. See [_isHovered] for the full story.
  static bool get _hasMousePointer {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
    }
  }

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
        // Only resume if auto-scroll was actually enabled (i.e. the
        // caller passed a positive duration). We track this via
        // [_timer] being non-null when active — see [_startAutoScroll].
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
    // A zero/negative duration means "the caller disabled auto-scroll"
    // (e.g. the product detail screen, where auto-advance fought the
    // customer's manual swipes inside the vertical
    // SingleChildScrollView). Bail out before scheduling a timer —
    // `Timer.periodic(Duration.zero, ...)` fires every microtask and
    // calls `animateToPage` on every frame, which is what made the
    // carousel feel sluggish and unresponsive to user input.
    if (widget.autoScrollDuration <= Duration.zero) return;
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

  /// Advance one page forward. Used by the right-side nav button
  /// and could be reused by future programmatic controls. No-op
  /// when the carousel isn't attached (e.g. mid-build) or has a
  /// single image.
  void _next() {
    if (!mounted || !_controller.hasClients) return;
    if (widget.imageUrls.length < 2) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Go one page back. See [_next] for the matching forward call.
  void _previous() {
    if (!mounted || !_controller.hasClients) return;
    if (widget.imageUrls.length < 2) return;
    _controller.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: widget.useHorizontalPadding
          ? EdgeInsets.symmetric(horizontal: context.horizontalPadding)
          : EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              height: widget.height ?? context.carouselHeight,
              child: GestureDetector(
                // Drive the [PageController] manually from this
                // GestureDetector instead of letting [PageView]'s
                // built-in horizontal drag detector compete for
                // the gesture arena.
                //
                // Why: when this carousel sits inside a vertical
                // [SingleChildScrollView] (the product detail
                // page), the parent and the [PageView] both want
                // pan gestures, and on mobile the parent often
                // wins — every horizontal swipe gets mis-classified
                // as a vertical drag and the carousel appears
                // stuck. By wrapping the [PageView] in a
                // [GestureDetector] that explicitly handles
                // `onHorizontalDragUpdate`, the carousel claims
                // the horizontal gesture immediately, before the
                // parent gets a chance to. The [PageView] is given
                // [NeverScrollableScrollPhysics] so its own drag
                // detector stays out of the way; we manually call
                // `controller.jumpTo` while the finger is down
                // and `controller.animateToPage` when it lifts.
                //
                // `behavior: opaque` is required so the
                // GestureDetector's hit-test doesn't fall through
                // to widgets behind it (the discount ribbon
                // overlay, the page background, etc.) when the
                // carousel sits inside a [Stack].
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) {
                  if (widget.imageUrls.length < 2) return;
                  if (!_controller.hasClients) return;
                  _dragStartControllerOffset = _controller.offset;
                  _dragTotal = 0;
                  // Cancel any in-flight auto-scroll animation
                  // triggered by [Timer.periodic] so the user's
                  // drag is the only thing driving the carousel.
                  _controller.jumpTo(_controller.offset);
                },
                onHorizontalDragUpdate: (details) {
                  if (widget.imageUrls.length < 2) return;
                  if (_dragStartControllerOffset == null) return;
                  if (!_controller.hasClients) return;
                  // Finger moved right (positive deltaX) →
                  // carousel should reveal the page on the LEFT
                  // (i.e. previous page), so we DECREASE the
                  // controller's offset. This matches the natural
                  // mapping of touch → scroll: drag right ⇒ see
                  // what was on the left.
                  _dragTotal += details.primaryDelta ?? 0;
                  final newOffset =
                      _dragStartControllerOffset! - _dragTotal;
                  // Clamp to the valid scroll range so the user
                  // can't drag the carousel past the first/last
                  // page; without this a fast flick can briefly
                  // set the offset outside [_controller.position.min
                  // ..max] and the [PageView] throws.
                  final pos = _controller.position;
                  final clamped = newOffset
                      .clamp(pos.minScrollExtent, pos.maxScrollExtent)
                      .toDouble();
                  _controller.jumpTo(clamped);
                },
                onHorizontalDragEnd: (details) {
                  if (widget.imageUrls.length < 2) return;
                  if (_dragStartControllerOffset == null) return;
                  if (!_controller.hasClients) return;
                  // Snap to the nearest page based on (a) the
                  // current fractional page and (b) the flick
                  // velocity. Both PageView's standard behaviour
                  // and a hard cutoff at half a page width.
                  final pageSize =
                      _controller.position.viewportDimension;
                  final currentPage = _controller.page ?? _current.toDouble();
                  // Flick in either direction: if the user
                  // released with enough horizontal velocity,
                  // jump one page in that direction regardless
                  // of the current offset; otherwise snap to the
                  // nearest whole page.
                  final velocity = details.primaryVelocity ?? 0;
                  double targetPage;
                  if (velocity.abs() > 300) {
                    // Flick threshold (px/s). Matches the
                    // PageView default of 1 logical pixel per
                    // millisecond.
                    targetPage = velocity > 0
                        ? currentPage.floorToDouble()
                        : currentPage.ceilToDouble();
                  } else {
                    targetPage = currentPage.roundToDouble();
                  }
                  targetPage = targetPage
                      .clamp(0, (widget.imageUrls.length - 1).toDouble())
                      .toDouble();
                  // pageSize > 0 guard: when the carousel hasn't
                  // laid out yet, animateToPage would divide by
                  // zero. Bail out and let the next frame handle
                  // it.
                  if (pageSize > 0) {
                    _controller.animateToPage(
                      targetPage.toInt(),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                  _dragStartControllerOffset = null;
                  _dragTotal = 0;
                },
                child: Listener(
                  // Wheel/trackpad input still flows through here
                  // (PointerScrollEvent). Touch drags are handled
                  // by the surrounding [GestureDetector] above, so
                  // there's no overlap.
                  onPointerSignal: (signal) {
                    if (signal is! PointerScrollEvent) return;
                    if (widget.imageUrls.length < 2) return;
                    if (!mounted || !_controller.hasClients) return;
                    final dx = signal.scrollDelta.dx;
                    final dy = signal.scrollDelta.dy;
                    final primary = dx.abs() > dy.abs() ? dx : dy;
                    if (primary.abs() < 1) return;
                    if (primary > 0) {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    } else {
                      _controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: PageView.builder(
                    // `NeverScrollableScrollPhysics` disables the
                    // PageView's own horizontal drag detector so
                    // the surrounding [GestureDetector] can drive
                    // the controller without competition. Wheel
                    // events (handled by the inner [Listener])
                    // call [PageController.nextPage] / .previousPage
                    // directly and don't go through physics, so
                    // they're unaffected.
                    physics: const NeverScrollableScrollPhysics(),
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
            ),
          ),
            if (widget.imageUrls.length > 1) ...[
              // The nav-button row is desktop-only. On touch
              // platforms the two Expanded 48dp-wide pill buttons
              // fill the left and right halves of the carousel and
              // physically block [PageView]'s horizontal drag
              // detector — there is no hover affordance on mobile,
              // so we can't make them disappear on demand. Instead
              // we don't render them at all; touch users get the
              // native swipe gesture, which is what they expect
              // from every other gallery UI on the platform.
              if (widget.showNavigationButtons && _hasMousePointer)
                // A single MouseRegion wraps the whole carousel so
                // hovering *anywhere* over the image reveals the
                // buttons — much friendlier than forcing the user
                // to aim at the narrow button strip itself.
                //
                // The Row below lays out two pill buttons at the
                // edges with an empty middle so the photo shows
                // through between them. We wrap it in
                // [IgnorePointer] when not hovered so the
                // underlying [PageView] keeps catching horizontal
                // drags — without that, the buttons would steal
                // every mouse hit on the carousel even before the
                // user hovers them.
                Positioned.fill(
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isHovered = true),
                    onExit: (_) => setState(() => _isHovered = false),
                    child: IgnorePointer(
                      ignoring: !_isHovered,
                      child: Row(
                        children: [
                          // Left pill. Hidden at index 0 because
                          // there's no image "before" the first one
                          // (this carousel does not wrap).
                          if (_current > 0)
                            Expanded(
                              child: CarouselNavButton(
                                icon: Icons.chevron_left,
                                onTap: _previous,
                                revealed: _isHovered,
                                align: Alignment.centerLeft,
                              ),
                            )
                          else
                            const Expanded(child: SizedBox.shrink()),
                          // Empty middle slot — the photo shows
                          // through here. SizedBox.shrink() takes
                          // zero space; the two Expandeds split
                          // the rest evenly.
                          const SizedBox.shrink(),
                          if (_current < widget.imageUrls.length - 1)
                            Expanded(
                              child: CarouselNavButton(
                                icon: Icons.chevron_right,
                                onTap: _next,
                                revealed: _isHovered,
                                align: Alignment.centerRight,
                              ),
                            )
                          else
                            const Expanded(child: SizedBox.shrink()),
                        ],
                      ),
                    ),
                  ),
                ),
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
          ],
        ),
      ),
    );
  }
}
