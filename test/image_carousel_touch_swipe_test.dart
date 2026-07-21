import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/widgets/image_carousel.dart';

/// User-reported regression on the product-detail screen: on mobile
/// (Android / iOS) horizontal swipes across the image carousel did
/// nothing — the gallery was "stuck" on whichever image was first
/// shown, both for the default product gallery and for any
/// variant-specific gallery after an option was picked.
///
/// Root cause: [ImageCarousel] previously rendered two 48dp-wide
/// [CarouselNavButton]s as `Expanded` children on the left and
/// right halves of the carousel, with a `SizedBox.shrink()` (zero
/// width) middle gap. On desktop that's fine because the buttons
/// hide until the cursor hovers, but on touch platforms there is no
/// hover affordance — the buttons were always visible and always
/// catching pointers, leaving `PageView` no surface to detect a
/// horizontal drag on. The visible symptom was "swipes don't work".
///
/// This test pins the fix: when [defaultTargetPlatform] is iOS or
/// Android, the nav button row must NOT render at all, so
/// `PageView` keeps full ownership of horizontal swipes. We use
/// [debugDefaultTargetPlatformOverride] inside a `try/finally` to
/// put the test runner in the touch configuration regardless of
/// the host OS running the suite — and the framework asserts that
/// every `debugXxx` override is cleared at the end of the test, so
/// we have to reset it from the body, not from `tearDown`.
///
/// Why we don't simulate the drag itself: `PageView`'s snapping
/// thresholds + the test environment's gesture simulation make it
/// notoriously hard to drive a real page change with `dragFrom` /
/// `flingFrom`. The structural assertion below — "no nav-button
/// icons are in the tree on a touch platform" — is what guards the
/// actual bug. If those buttons aren't there, the underlying
/// `PageView` always owns the full carousel area and a real human
/// swipe will land.
void main() {
  testWidgets(
      'nav buttons do NOT render on iOS/Android so PageView keeps full swipe area',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ImageCarousel(
            imageUrls: ['a', 'b', 'c'],
            showNavigationButtons: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The fix: on a touch platform the nav-button row is
      // skipped entirely. The chevron_left / chevron_right icons
      // (which only ever appear inside [CarouselNavButton]) must
      // NOT be in the tree at all. If they were, they'd be sitting
      // on top of `PageView` and blocking horizontal swipes.
      expect(find.byIcon(Icons.chevron_left), findsNothing,
          reason:
              'left nav button must be absent on touch platforms — it would '
              'otherwise cover the left half of the carousel and block '
              'PageView\'s horizontal drag detector');
      expect(find.byIcon(Icons.chevron_right), findsNothing,
          reason:
              'right nav button must be absent on touch platforms for the '
              'same reason as the left one');

      // The underlying [PageView] must remain mounted so swipes
      // drive the carousel.
      expect(find.byType(PageView), findsOneWidget,
          reason:
              'PageView must remain mounted so swipes drive the carousel');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'nav buttons DO render on desktop so mouse hover keeps its affordance',
      (tester) async {
    // Desktop targets (macOS in this case — Linux/Windows would also
    // pass) keep the hover-driven behaviour. We assert the buttons
    // ARE present so a future refactor that accidentally drops them
    // on desktop breaks the test instead of regressing silently.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ImageCarousel(
            imageUrls: ['a', 'b', 'c'],
            showNavigationButtons: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // On desktop the nav buttons render but are hidden until
      // hover — the icons exist in the widget tree, just at
      // opacity 0. [find] still locates them. Only the "next"
      // button exists at index 0 (the "previous" one is hidden
      // because there's no image before the first one).
      expect(find.byIcon(Icons.chevron_right), findsOneWidget,
          reason:
              'desktop carousel must keep its nav buttons so mouse users '
              'have an explicit alternative to wheel/touchpad input');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'a carousel with a single image renders no nav buttons regardless of platform',
      (tester) async {
    // Single-image carousels never show nav buttons (there's
    // nothing to advance to) — make sure the platform gate doesn't
    // accidentally introduce a single-image touch bug.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ImageCarousel(
            imageUrls: ['only'],
            showNavigationButtons: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(PageView), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}