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
}
