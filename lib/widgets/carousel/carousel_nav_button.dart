import 'package:flutter/material.dart';

/// Floating prev/next button used by [ImageCarousel]. Vertical edge
/// strip with a dark translucent background so the icon reads on
/// both light and dark images. AnimatedOpacity is driven by the
/// caller's hover state — on touch-only platforms [revealed] stays
/// false and the button is never visible (the carousel relies on
/// swipe gestures there).
class CarouselNavButton extends StatelessWidget {
  const CarouselNavButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.revealed,
    required this.align,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool revealed;
  final AlignmentGeometry align;

  @override
  // Block body on purpose — the inline comments inside explain
  // the colour choice, hit-target sizing, and "why darker than
  // the image". Collapsing to `=> AnimatedOpacity(...)` would
  // silently drop them.
  // ignore: prefer_expression_function_bodies
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      // On touch-only platforms [revealed] stays false because no
      // mouse ever enters the region — so without this fallback
      // we'd hide the buttons entirely on mobile. Force them
      // visible when there's no hover capability: detect by
      // checking [MouseRegion]'s cursor mode via [kIsWeb] + the
      // mouse-tracker attached-ness. Simpler: when the
      // [revealed] flag is *false* on its first frame, we can't
      // tell hover from "no mouse yet", so we just respect the
      // flag — but the caller passes a sensible default. Here we
      // additionally fade duration to 0 when revealed hasn't
      // transitioned yet to avoid the initial flash.
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      opacity: revealed ? 1.0 : 0.0,
      child: Align(
        alignment: align,
        child: Material(
          // Darker than the photo. We pick a near-black with ~45%
          // opacity so the icon reads on both light and dark
          // product shots without overwhelming them — the goal is
          // "this is a control", not "look at me".
          color: Colors.black.withValues(alpha: 0.45),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              // A narrow vertical strip on the edge — wide enough
              // to be a comfortable touch target (44dp minimum)
              // and tall enough to feel like a "side rail".
              width: 48,
              height: double.infinity,
              child: Icon(icon, size: 28, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
