import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:simshop/views/product_detail_screen/lightbox_screen.dart';

void main() {
  testWidgets('LightboxScreen renders with PhotoViewGallery + close button',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LightboxScreen(
        images: ['https://a/1.jpg', 'https://a/2.jpg', 'https://a/3.jpg'],
        initialIndex: 1,
      ),
    ));
    await tester.pump();

    expect(find.byType(PhotoViewGallery), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('LightboxScreen: close button pops the route', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const LightboxScreen(
                images: ['https://a/1.jpg'],
                initialIndex: 0,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // Pump a few frames to let the route animation settle without
    // waiting for pumpAndSettle (PhotoView keeps an animation loop
    // running internally that never fully settles in the test env).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LightboxScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    // Pump longer to let the route pop animation complete even with
    // PhotoView's internal animation loop.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LightboxScreen), findsNothing);
  });

  testWidgets('LightboxScreen: gallery itemCount matches image count',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LightboxScreen(
        images: ['https://a/1.jpg', 'https://a/2.jpg'],
        initialIndex: 0,
      ),
    ));
    await tester.pump();

    // PhotoViewGallery.builder takes an itemCount — we verify by
    // inspecting the widget directly. Photos are lazy-rendered by
    // the PageView inside PhotoViewGallery, so we can't count
    // CachedNetworkImage widgets directly.
    final gallery = tester.widget<PhotoViewGallery>(find.byType(PhotoViewGallery));
    expect(gallery.itemCount, 2);
  });
}
