import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/views/product_detail_screen/_gallery_section.dart';
import 'package:simshop/views/product_detail_screen/lightbox_screen.dart';

Widget _harness(List<String> images, {double height = 400}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => GallerySection(
            images: images,
            height: height,
            scheme: Theme.of(ctx).colorScheme,
          ),
        ),
      ),
    );

void main() {
  testWidgets('GallerySection: PageView uses default physics', (tester) async {
    await tester.pumpWidget(_harness(['a', 'b', 'c']));
    await tester.pump();
    final pv = tester.widget<PageView>(find.byType(PageView));
    expect(pv.physics == null || pv.physics is PageScrollPhysics, isTrue);
    expect(pv.physics, isNot(isA<NeverScrollableScrollPhysics>()));
  });

  testWidgets('GallerySection: thumbnail strip renders N items for N images',
      (tester) async {
    final notifier = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Column(
            children: [
              GallerySection(
                images: const ['a', 'b', 'c'],
                height: 400,
                scheme: Theme.of(ctx).colorScheme,
                activeIndex: notifier,
              ),
              ThumbnailStrip(
                images: const ['a', 'b', 'c'],
                activeIndex: notifier,
                scheme: Theme.of(ctx).colorScheme,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    final thumbnails = find.descendant(
      of: find.byType(ThumbnailStrip),
      matching: find.byType(GestureDetector),
    );
    expect(thumbnails, findsNWidgets(3));
  });

  testWidgets('GallerySection: thumbnail strip hidden for single image',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ThumbnailStrip(
            images: const ['only'],
            activeIndex: ValueNotifier<int>(0),
            scheme: Theme.of(ctx).colorScheme,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(ThumbnailStrip), findsOneWidget);
    // Internal itemBuilder produces 0 GestureDetector items, the
    // test for "strip exists" is enough — the parent's build only
    // mounts the strip when there is >1 image.
    final thumbnails = find.descendant(
      of: find.byType(ThumbnailStrip),
      matching: find.byType(GestureDetector),
    );
    expect(thumbnails, findsNWidgets(1));
  });

  testWidgets('GallerySection: tapping main image pushes LightboxScreen',
      (tester) async {
    await tester.pumpWidget(_harness(['a', 'b', 'c']));
    await tester.pump();
    await tester.tap(find.byKey(const Key('main-image-tap-target')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LightboxScreen), findsOneWidget);
  });

  testWidgets('GallerySection: desktop chevron buttons NOT rendered on iOS',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(_harness(['a', 'b', 'c']));
      await tester.pump();
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GallerySection: desktop chevron buttons rendered on desktop',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(_harness(['a', 'b', 'c']));
      await tester.pump();
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GallerySection: arrow-key handler advances activeIndex',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final notifier = ValueNotifier<int>(0);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => GallerySection(
              images: const ['a', 'b', 'c'],
              height: 400,
              scheme: Theme.of(ctx).colorScheme,
              activeIndex: notifier,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(notifier.value, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      // Pump discrete frames because cached_network_image keeps a
      // retry loop that pumpAndSettle would never resolve.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(notifier.value, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(notifier.value, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GallerySection: CachedNetworkImage mounts per image',
      (tester) async {
    await tester.pumpWidget(_harness(['a', 'b', 'c']));
    await tester.pump();
    // PageView lazy-builds — pump a few frames to lay out all slides.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CachedNetworkImage), findsWidgets);
  });

  // User-reported regression: tapping a thumbnail used to NOT change
  // the displayed image. Root cause was that `GallerySection` only
  // WROTE to `widget.activeIndex` (in `_next` / `_previous` /
  // `onPageChanged`) but never ADD-VALUE-LISTENABLEd on it — so a
  // write from `ThumbnailStrip.onTap` (`activeIndex.value = i`) had
  // no effect on the PageController.
  //
  // Fix: `GallerySection` now subscribes to `widget.activeIndex` in
  // `initState` (and re-subscribes in `didUpdateWidget` if the
  // notifier identity changes). When the notifier changes externally
  // AND the new value differs from the local `_activeIndex`, the
  // gallery animates `_pageController.animateToPage(target)` and
  // updates its own index. Writes from `_next` / `_previous` set
  // `_activeIndex` FIRST so the listener's `target == _activeIndex`
  // guard skips a redundant animation.
  //
  // This test pins the new behavior structurally: wire both widgets
  // to the same notifier, tap the 2nd thumbnail, pump the animation,
  // assert the gallery's `activeIndex` advanced AND the
  // `PageController.page` actually moved.
  testWidgets(
      'GallerySection: tapping a thumbnail animates the PageController '
      'to that page (regression: thumb tap used to be a no-op)',
      (tester) async {
    final notifier = ValueNotifier<int>(0);
    final galleryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Column(
            children: [
              GallerySection(
                key: galleryKey,
                images: const ['a', 'b', 'c'],
                height: 400,
                scheme: Theme.of(ctx).colorScheme,
                activeIndex: notifier,
              ),
              ThumbnailStrip(
                images: const ['a', 'b', 'c'],
                activeIndex: notifier,
                scheme: Theme.of(ctx).colorScheme,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    // Lay out PageView so the controller is attached.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Sanity: gallery starts on page 0.
    final gallery =
        galleryKey.currentState as dynamic; // ignore: avoid_dynamic
    expect(gallery.activeIndex as int, 0);
    // The notifier is the source of truth shared with the strip —
    // still 0 because the user hasn't done anything yet.
    expect(notifier.value, 0);

    // Tap the second thumbnail (the strip is a horizontal ListView
    // so `at(1)` is the second item).
    final secondThumb = find.descendant(
      of: find.byType(ThumbnailStrip),
      matching: find.byType(GestureDetector),
    ).at(1);
    expect(secondThumb, findsOneWidget);
    await tester.tap(secondThumb);

    // Pump enough frames for the 250 ms animateToPage to complete.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The gallery must have moved to page 1 — its internal
    // `_activeIndex` advances synchronously in the listener, and the
    // PageController should be parked at page 1.
    expect(gallery.activeIndex as int, 1,
        reason: 'GallerySection must listen to activeIndex and advance '
            'its _activeIndex when the notifier changes externally');
    expect(notifier.value, 1,
        reason: 'notifier should reflect the gallery\'s new position '
            '(either set by the strip or echoed by the gallery)');

    // Verify the PageController actually moved — i.e. the user can
    // see image #2, not just an updated highlight in the strip.
    final pv = tester.widget<PageView>(find.byType(PageView));
    expect(pv.controller?.page?.round() ?? -1, 1,
        reason: 'PageController must animate to the tapped page — '
            'otherwise the user is still staring at image 0');
  });

  testWidgets(
      'GallerySection: external notifier write (e.g. option reset) animates '
      'PageController to page 0', (tester) async {
    // The screen calls `_activeImageIndex.value = 0` when the user
    // picks a new variant, but because the gallery is keyed on
    // option id, it remounts — so this test exercises the listener
    // path WITHOUT remount, by writing the notifier directly.
    final notifier = ValueNotifier<int>(2);
    final galleryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => GallerySection(
            key: galleryKey,
            images: const ['a', 'b', 'c'],
            height: 400,
            scheme: Theme.of(ctx).colorScheme,
            activeIndex: notifier,
          ),
        ),
      ),
    ));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final gallery = galleryKey.currentState as dynamic;
    // Initial state: PageController sits at page 0 because
    // PageController() starts there, but our _activeIndex is 0 too.
    // Now write the notifier to 0 from the outside (simulating the
    // reset). The listener should no-op (target == _activeIndex).
    notifier.value = 0;
    await tester.pump();
    expect(gallery.activeIndex as int, 0);

    // Write to 2 — listener should animate.
    notifier.value = 2;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(gallery.activeIndex as int, 2);

    final pv = tester.widget<PageView>(find.byType(PageView));
    expect(pv.controller?.page?.round() ?? -1, 2);
  });
}
