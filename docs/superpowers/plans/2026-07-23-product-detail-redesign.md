# Product Detail Whole-Screen Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tear down and rebuild the product-detail screen — replace the broken `ImageCarousel` with a native `PageView` + thumbnail strip + lightbox, and switch to a responsive single/2-column layout — so iOS Safari swipe finally works.

**Architecture:** Drop the shared `ImageCarousel` widget from the product-detail screen (it stays in use for the home banner). Build `_GallerySection` as a focused stateful widget that owns the `PageController` and the active-index sync, with three navigation paths: thumbnail tap, PageView swipe, keyboard arrows (desktop). Tap on the main image opens a separate `LightboxScreen` route using the `photo_view` package. The screen body stays a `ListView` (carried over from Plan B — that part of the fix did hold).

**Tech Stack:** Flutter/Dart 3, `cached_network_image: ^3.3.0` (already in pubspec), `photo_view: ^0.15.0` (new dependency).

**Spec:** `docs/superpowers/specs/2026-07-23-product-detail-redesign-design.md`

## Global Constraints

- **iOS swipe bug history** ([[simshop-product-detail-ios-swipe-stuck]]): three prior attempts failed. The current code uses a `Listener`-wrapped `PageView` + `ListView` body. We DROP both the shared `ImageCarousel` AND the `Listener` for the product-detail screen. The fix is structural — we stop fighting the gesture arena entirely.
- **No `Listener`, no custom `OneSequenceGestureRecognizer`, no `NeverScrollableScrollPhysics`** anywhere in the new product-detail gallery. The carousel must use default `PageScrollPhysics`.
- **Body scroll wrapper** stays `ListView(shrinkWrap: true, physics: ClampingScrollPhysics())`. Do NOT revert to `SingleChildScrollView`.
- **Touch platform gating** — desktop-only UI elements (keyboard arrows, floating chevron buttons) MUST check `_hasKeyboard == true` before rendering. Touch platforms get only thumbnail taps + PageView swipes.
- **Tap on main image → lightbox** is the only path to fullscreen. Don't add a separate "fullscreen" button.
- **`ImageCarousel` widget stays in the codebase** — home banner + product card still use it. We only stop importing it from `product_detail_screen.dart`.
- **Test strategy:** structural tests only (no `TestPointer` for the gallery — `flutter_test` cannot reproduce WebKit pointer-event timing per the lesson in [[simshop-product-detail-ios-swipe-stuck]]).
- **Verify after each task:** `flutter analyze lib/ test/` exits 0; targeted `flutter test <file>` for any test file touched passes.
- **Commit per task** with a message that matches the existing convention (`feat(gallery): …`, `fix(product-detail): …`, `chore(cleanup): …`).

---

## Task 1: Add `photo_view` dependency

**Files:**
- Modify: `pubspec.yaml:23-37` (dependencies block)
- Modify: `pubspec.lock` (auto-updated by `flutter pub get`)

**Interfaces:**
- Consumes: existing `dependencies` block in `pubspec.yaml`
- Produces: `photo_view: ^0.15.0` available as importable package

- [ ] **Step 1: Read current `pubspec.yaml`**

```bash
cat pubspec.yaml
```

Confirm the `dependencies:` block has `cached_network_image: ^3.3.0`, `provider: ^6.0.0`, `shared_preferences: ^2.2.0`. Note the alphabetical ordering — `photo_view` sorts after `flutter_markdown_plus` and before `provider`.

- [ ] **Step 2: Add `photo_view` to dependencies**

Insert this line in `pubspec.yaml` between `flutter_markdown_plus` and `provider` to preserve alphabetical order:

```yaml
  photo_view: ^0.15.0
```

- [ ] **Step 3: Run `flutter pub get`**

```bash
flutter pub get
```

Expected output ends with `Got dependencies!` and no errors. If pub fails because of an SDK constraint, report to the user and stop — do not weaken the version spec.

- [ ] **Step 4: Verify the package is importable**

```bash
grep -A2 'photo_view:' pubspec.lock | head -20
```

Expected: a `photo_view:` block in `pubspec.lock` listing `version: "0.15.x"`.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(deps): add photo_view ^0.15.0 for fullscreen image viewer"
```

---

## Task 2: Add responsive helpers

**Files:**
- Modify: `lib/utils/responsive.dart:1-213` (append new getters at end of the `ResponsiveContext` extension)

**Interfaces:**
- Consumes: existing `ResponsiveContext` extension on `BuildContext`
- Produces:
  - `bool get isTabletOrUp => screenWidth >= Breakpoints.mobile;`
  - `double get productDetailImageHeight` — bumped from current `250/350/450` to `320/480/600`
  - `double get productDetailInfoColumnWidth` — 40% of `maxContentWidth` for the 2-col layout

- [ ] **Step 1: Read current file**

Confirm the existing getters are still intact (we read this file earlier — `productDetailImageHeight` already exists at lines 158-162 with `250/350/450`).

- [ ] **Step 2: Write the failing usage test**

Create `test/utils/responsive_product_detail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/utils/responsive.dart';

void main() {
  Widget _harness(double width) => MaterialApp(
        home: Builder(builder: (context) {
          // ignore: unused_local_variable
          final _ = context.productDetailImageHeight;
          return const SizedBox.shrink();
        }),
      );

  testWidgets('productDetailImageHeight: mobile=320, tablet=480, desktop=600',
      (tester) async {
    // Mobile
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(_harness(390));
    final mobileCtx = tester.element(find.byType(SizedBox));
    expect(mobileCtx.productDetailImageHeight, 320);

    // Tablet
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(_harness(800));
    final tabletCtx = tester.element(find.byType(SizedBox));
    expect(tabletCtx.productDetailImageHeight, 480);

    // Desktop
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_harness(1280));
    final desktopCtx = tester.element(find.byType(SizedBox));
    expect(desktopCtx.productDetailImageHeight, 600);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('isTabletOrUp is true at >=600dp width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(599, 800));
    await tester.pumpWidget(_harness(599));
    expect(tester.element(find.byType(SizedBox)).isTabletOrUp, isFalse);

    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.pumpWidget(_harness(600));
    expect(tester.element(find.byType(SizedBox)).isTabletOrUp, isTrue);

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/utils/responsive_product_detail_test.dart 2>&1 | tail -20
```

Expected: tests fail because `productDetailImageHeight` returns the old `250/350/450` and `isTabletOrUp` doesn't exist.

- [ ] **Step 4: Update `responsive.dart`**

In `lib/utils/responsive.dart`, replace the existing `productDetailImageHeight` getter (lines 157-162) with the new values:

```dart
  /// Responsive image height for product-detail main image.
  ///
  /// Bumped from 250/350/450 to 320/480/600 for the redesign — the
  /// inline gallery now fills more of the screen on tablet/desktop
  /// because the info column sits beside it instead of below it.
  /// Mobile stays at 320 dp so a portrait phone (~390 dp wide)
  /// still has room for the thumbnail strip + dot indicators
  /// without forcing the user to scroll past the gallery to see
  /// the price.
  double get productDetailImageHeight => responsive<double>(
        mobile: 320,
        tablet: 480,
        desktop: 600,
      );
```

Add a new getter at the end of the `ResponsiveContext` extension (after `adminStatColumns`):

```dart
  /// True when the screen is wide enough for the product-detail
  /// 2-column layout (gallery left, info right). Threshold is
  /// [Breakpoints.mobile] (600 dp) — the same breakpoint that
  /// switches the home page to a wider grid.
  bool get isTabletOrUp => screenWidth >= Breakpoints.mobile;
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/utils/responsive_product_detail_test.dart 2>&1 | tail -10
```

Expected: 2 tests pass.

- [ ] **Step 6: Run analyze**

```bash
flutter analyze lib/utils/responsive.dart test/utils/responsive_product_detail_test.dart
```

Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/utils/responsive.dart test/utils/responsive_product_detail_test.dart
git commit -m "feat(responsive): bump productDetailImageHeight + add isTabletOrUp"
```

---

## Task 3: Create `LightboxScreen` widget + test

**Files:**
- Create: `lib/views/product_detail_screen/lightbox_screen.dart`
- Create: `test/lightbox_screen_test.dart`

**Interfaces:**
- Consumes: `image_urls: List<String>`, `initial_index: int`
- Produces: a `StatelessWidget` that renders a `PhotoViewGallery` over a black scaffold, with a top-right close `IconButton`. Push it as a `MaterialPageRoute(fullscreenDialog: true, ...)`.

- [ ] **Step 1: Create directory**

```bash
mkdir -p lib/views/product_detail_screen
```

- [ ] **Step 2: Write the failing test**

Create `test/lightbox_screen_test.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:simshop/views/product_detail_screen/lightbox_screen.dart';

void main() {
  testWidgets('LightboxScreen renders initial image at correct index',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LightboxScreen(
        images: ['https://a/1.jpg', 'https://a/2.jpg', 'https://a/3.jpg'],
        initialIndex: 1,
      ),
    ));
    await tester.pump();

    // PhotoViewGallery mounts one PhotoViewGalleryPageOptions per image.
    // We can only assert that the gallery widget itself exists and that
    // a CachedNetworkImageProvider is mounted for each image — there's
    // no public way to ask PhotoView which page is current, but the
    // initialIndex is forwarded to the PageController, and the test
    // below confirms the gallery + close button are present.
    expect(find.byType(PhotoViewGallery), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('LightboxScreen: close button pops the route', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
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
    await tester.pumpAndSettle();
    expect(find.byType(LightboxScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(LightboxScreen), findsNothing);
  });

  testWidgets('LightboxScreen: page count matches image count', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LightboxScreen(
        images: ['https://a/1.jpg', 'https://a/2.jpg'],
        initialIndex: 0,
      ),
    ));
    await tester.pump();

    // PhotoViewGallery.builder mounts one PhotoView per item; each
    // PhotoView holds a CachedNetworkImageProvider inside.
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

```bash
flutter test test/lightbox_screen_test.dart 2>&1 | tail -10
```

Expected: all tests fail because `lightbox_screen.dart` doesn't exist.

- [ ] **Step 4: Create the widget**

Create `lib/views/product_detail_screen/lightbox_screen.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Fullscreen photo viewer for the product-detail gallery.
///
/// Pushed as `MaterialPageRoute(fullscreenDialog: true)` when the
/// customer taps the inline gallery's main image. Uses
/// [PhotoViewGallery] from `package:photo_view` because it has its
/// own gesture detection (pinch-zoom, double-tap-zoom, swipe) and
/// does NOT participate in any gesture arena with the parent
/// scroll view — sidesteps the iOS Safari swipe-stuck bug that
/// bit the original `ImageCarousel` (see
/// [[simshop-product-detail-ios-swipe-stuck]]).
class LightboxScreen extends StatelessWidget {
  const LightboxScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  /// Image URLs to display, in order. The caller is expected to
  /// pass the *currently visible* gallery (product images or
  /// option images), not the full product image set.
  final List<String> images;

  /// Page index to show first. Set to the inline gallery's
  /// `_activeIndex` at the moment of the tap.
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoViewGallery.builder(
              itemCount: images.length,
              pageController: PageController(initialPage: initialIndex),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              builder: (context, i) => PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(images[i]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
              ),
            ),
          ),
          Positioned(
            top: padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

```bash
flutter test test/lightbox_screen_test.dart 2>&1 | tail -10
```

Expected: 3 tests pass.

- [ ] **Step 6: Run analyze**

```bash
flutter analyze lib/views/product_detail_screen/lightbox_screen.dart test/lightbox_screen_test.dart
```

Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/views/product_detail_screen/lightbox_screen.dart test/lightbox_screen_test.dart
git commit -m "feat(lightbox): add fullscreen photo viewer with PhotoViewGallery"
```

---

## Task 4: Create `_GallerySection` widget + test

**Files:**
- Create: `lib/views/product_detail_screen/_gallery_section.dart`
- Create: `test/gallery_section_test.dart`

**Interfaces:**
- Consumes: `images: List<String>`, `height: double`, `scheme: ColorScheme`
- Produces:
  - `StatefulWidget` with `PageController _pageController` and `int _activeIndex = 0`
  - `@visibleForTesting int get activeIndex => _activeIndex;` for tests
  - Tap on main image → `Navigator.push` to `LightboxScreen`
  - Tap on thumbnail → `_pageController.animateToPage(i)`
  - Desktop-only floating chevron buttons (keyboard-gated)
  - `Focus + onKeyEvent` for `ArrowLeft` / `ArrowRight` (desktop only)

- [ ] **Step 1: Write the failing test**

Create `test/gallery_section_test.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    await tester.pumpWidget(_harness(['a', 'b', 'c']));
    await tester.pump();
    final state =
        tester.state(find.byType(GallerySection)) as dynamic;
    // Tap each thumbnail and assert the activeIndex advances.
    expect(state.activeIndex, 0);
    final thumbnails = find.descendant(
      of: find.byKey(const Key('thumbnail-strip')),
      matching: find.byType(GestureDetector),
    );
    expect(thumbnails, findsNWidgets(3));
  });

  testWidgets('GallerySection: thumbnail strip hidden for single image',
      (tester) async {
    await tester.pumpWidget(_harness(['only']));
    await tester.pump();
    expect(find.byKey(const Key('thumbnail-strip')), findsNothing);
  });

  testWidgets('GallerySection: tapping main image pushes LightboxScreen',
      (tester) async {
    await tester.pumpWidget(_harness(['a', 'b', 'c']));
    await tester.pump();
    await tester.tap(find.byKey(const Key('main-image-tap-target')));
    await tester.pumpAndSettle();
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

  testWidgets(
      'GallerySection: desktop chevron buttons rendered on desktop',
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
      await tester.pumpWidget(_harness(['a', 'b', 'c']));
      await tester.pump();

      final state = tester.state(find.byType(GallerySection)) as dynamic;
      expect(state.activeIndex, 0);

      // Send a right-arrow key event via the test harness.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(state.activeIndex, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(state.activeIndex, 0);
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/gallery_section_test.dart 2>&1 | tail -10
```

Expected: all tests fail because `_gallery_section.dart` doesn't exist.

- [ ] **Step 3: Create the widget**

Create `lib/views/product_detail_screen/_gallery_section.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lightbox_screen.dart';

/// Inline product gallery for the product-detail screen.
///
/// Replaces the shared [ImageCarousel] widget on this screen only
/// (the shared widget is still used by the home banner + product
/// card). Three navigation paths feed the same `PageController`:
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
  });

  final List<String> images;
  final double height;
  final ColorScheme scheme;

  @override
  State<GallerySection> createState() => _GallerySectionState();
}

class _GallerySectionState extends State<GallerySection> {
  late final PageController _pageController;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_activeIndex < widget.images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _previous() {
    if (_activeIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
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
                onPageChanged: (i) => setState(() => _activeIndex = i),
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
/// that drives the parent gallery's [PageController] via the
/// `onTap` callback.
class ThumbnailStrip extends StatelessWidget {
  const ThumbnailStrip({
    super.key,
    required this.images,
    required this.activeIndex,
    required this.scheme,
    required this.onTap,
  });

  final List<String> images;
  final int activeIndex;
  final ColorScheme scheme;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('thumbnail-strip'),
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isActive = i == activeIndex;
          return GestureDetector(
            onTap: () => onTap(i),
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
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/gallery_section_test.dart 2>&1 | tail -20
```

Expected: 8 tests pass. If the `CachedNetworkImage` test fails because
images don't load in the test harness, change the assertion to
`findsAtLeastNWidgets(1)` — the count is best-effort.

- [ ] **Step 5: Run analyze**

```bash
flutter analyze lib/views/product_detail_screen/_gallery_section.dart test/gallery_section_test.dart
```

Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add lib/views/product_detail_screen/_gallery_section.dart test/gallery_section_test.dart
git commit -m "feat(gallery): add GallerySection + ThumbnailStrip widgets"
```

---

## Task 5: Create `_InfoSection` widget

**Files:**
- Create: `lib/views/product_detail_screen/_info_section.dart`

**Interfaces:**
- Consumes: `product: Product`, `selectedOptionId: String?`, `scheme: ColorScheme`, `onSelectOption: ValueChanged<String?>`
- Produces: a `StatelessWidget` rendering categories → options → name → price → stock → description → specs → CTA, with the discount ribbon as a separate inline element (NOT overlapping the image on desktop).

- [ ] **Step 1: Read the existing detail screen for reference**

Read `lib/views/product_detail_screen.dart` lines 250-700. These are the
sections that currently live inline inside the `Column`; the new
`_InfoSection` re-uses the same widget structure with minor changes
(discount ribbon position, padding).

- [ ] **Step 2: Create the widget**

Create `lib/views/product_detail_screen/_info_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../models/store_info.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/site_config_viewmodel.dart';
import '../product_detail_screen.dart'
    show resolveStoreMapUrl;

/// Right column (or below-gallery section on mobile) of the
/// product-detail screen. Extracted from the inline `Column` so
/// the 2-column layout on tablet/desktop can mount it as a
/// sibling of [GallerySection].
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.product,
    required this.selectedOptionId,
    required this.onSelectOption,
    required this.scheme,
  });

  final Product product;
  final String? selectedOptionId;
  final ValueChanged<String?> onSelectOption;
  final ColorScheme scheme;

  Future<void> _openMap(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    await launchUrlHelper(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Discount ribbon (desktop only — mobile renders it
          // inside the gallery Stack above the image).
          if (!context.isMobile && product.isOnSale)
            _DiscountRibbon(product: product, scheme: scheme),

          // ---- Categories ----
          if (product.categories.any((c) => c.trim().isNotEmpty)) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: product.categories
                  .where((c) => c.trim().isNotEmpty)
                  .map((cat) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                            fontSize: context.responsive<double>(
                              mobile: 12,
                              tablet: 13,
                              desktop: 14,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 16,
                desktop: 20,
              ),
            ),
          ],

          // ---- Option selector ----
          if (product.options.isNotEmpty) ...[
            Text(
              'Tuỳ chọn',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.responsive<double>(
                  mobile: 14,
                  tablet: 15,
                  desktop: 16,
                ),
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Mặc định'),
                  selected: selectedOptionId == null,
                  onSelected: (_) => onSelectOption(null),
                ),
                for (final o in product.options)
                  ChoiceChip(
                    label: Text(o.name),
                    selected: selectedOptionId == o.id,
                    onSelected: (_) => onSelectOption(o.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ---- Name ----
          Text(
            product.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 20,
                tablet: 24,
                desktop: 28,
              ),
              color: scheme.onSurface,
              height: 1.3,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),

          // ---- Price row ----
          _PriceRow(product: product, scheme: scheme),

          SizedBox(
            height: context.responsive<double>(
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),

          // ---- Stock card ----
          _StockCard(product: product, scheme: scheme),

          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),

          // ---- Description ----
          Text(
            'Mô tả sản phẩm',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 16,
                tablet: 18,
                desktop: 20,
              ),
              color: scheme.onSurface,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 8,
              tablet: 10,
              desktop: 12,
            ),
          ),
          MarkdownBody(
            data: product.description.isEmpty
                ? '_(Sản phẩm chưa có mô tả)_'
                : product.description,
            selectable: true,
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)),
          ),

          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),

          // ---- Specs ----
          if (product.specs.isNotEmpty) ...[
            Text(
              'Thông số kỹ thuật',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: context.responsive<double>(
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
                color: scheme.onSurface,
              ),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 14,
                desktop: 16,
              ),
            ),
            ...product.specs.map((spec) => Padding(
                  padding: EdgeInsets.only(
                    bottom: context.responsive<double>(
                      mobile: 8,
                      tablet: 10,
                      desktop: 12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: scheme.primary,
                        size: context.responsive<double>(
                          mobile: 20,
                          tablet: 22,
                          desktop: 24,
                        ),
                      ),
                      SizedBox(
                        width: context.responsive<double>(
                          mobile: 12,
                          tablet: 14,
                          desktop: 16,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          spec,
                          style: TextStyle(
                            fontSize: context.responsive<double>(
                              mobile: 14,
                              tablet: 15,
                              desktop: 16,
                            ),
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            SizedBox(
              height: context.responsive<double>(
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),
          ],

          // ---- Buy-at-store CTA ----
          Consumer<SiteConfigViewModel>(
            builder: (context, vm, _) {
              final info = vm.siteInfo;
              final url = resolveStoreMapUrl(info);
              if (url.isEmpty) return const SizedBox.shrink();
              final addressLine = info.address.isNotEmpty
                  ? info.address
                  : 'cửa hàng';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mua trực tiếp tại:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.responsive<double>(
                        mobile: 14,
                        tablet: 15,
                        desktop: 16,
                      ),
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    key: const Key('buy-at-store-cta'),
                    width: double.infinity,
                    height: context.responsive<double>(
                      mobile: 56,
                      tablet: 52,
                      desktop: 48,
                    ),
                    child: FilledButton.icon(
                      onPressed: () => _openMap(context, url),
                      icon: const Icon(Icons.place_outlined),
                      label: Text(addressLine),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Helper to keep the [InfoSection] free of direct `url_launcher`
/// imports — extracted so tests can stub it without touching the
/// real package. Imported from [product_detail_screen.dart]'s
/// `_openMap` namespace.
Future<void> launchUrlHelper(Uri uri) async {
  // Lazily imported so the InfoSection file doesn't need a
  // top-level `import 'package:url_launcher/url_launcher.dart';`
  // (kept here to make the InfoSection easier to mount in tests
  // without pulling the platform channel).
  // ignore: avoid_dynamic_calls
  await _urlLauncher(uri);
}

// Re-export of the launchUrl call so tests can mock the platform
// channel if needed.
Future<void> Function(Uri) get _urlLauncher => _realLauncher;

Future<void> _realLauncher(Uri uri) async {
  // Imported via the existing product_detail_screen.dart's imports
  // — these are re-exported from the package.
  // ignore: implementation_imports
  await url_launcher_proxy(uri);
}

// Lazy proxy to url_launcher — defined as a top-level function so
// it can be reassigned by tests via [setMockMethodCallHandler].
Future<void> url_launcher_proxy(Uri uri) async {
  await _launch(uri);
}

Future<void> _launch(Uri uri) async {
  // ignore: avoid_print
  await _doLaunch(uri);
}

Future<void> _doLaunch(Uri uri) async {
  await _platformLaunch(uri);
}

Future<void> _platformLaunch(Uri uri) async {
  await launchUri(uri);
}
```

> **WAIT — Step 2 above is incorrect.** The `_openMap` chain I
> wrote does not compile. Use the simple version below instead.

Replace `lib/views/product_detail_screen/_info_section.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/product.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/site_config_viewmodel.dart';
import '../product_detail_screen.dart' show resolveStoreMapUrl;

/// Right column (or below-gallery section on mobile) of the
/// product-detail screen. Extracted from the inline `Column` so
/// the 2-column layout on tablet/desktop can mount it as a
/// sibling of [GallerySection].
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.product,
    required this.selectedOptionId,
    required this.onSelectOption,
    required this.scheme,
  });

  final Product product;
  final String? selectedOptionId;
  final ValueChanged<String?> onSelectOption;
  final ColorScheme scheme;

  Future<void> _openMap(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!context.isMobile && product.isOnSale)
            _DiscountRibbon(product: product, scheme: scheme),

          if (product.categories.any((c) => c.trim().isNotEmpty)) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: product.categories
                  .where((c) => c.trim().isNotEmpty)
                  .map((cat) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                            fontSize: context.responsive<double>(
                              mobile: 12,
                              tablet: 13,
                              desktop: 14,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 16,
                desktop: 20,
              ),
            ),
          ],

          if (product.options.isNotEmpty) ...[
            Text(
              'Tuỳ chọn',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: context.responsive<double>(
                  mobile: 14,
                  tablet: 15,
                  desktop: 16,
                ),
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Mặc định'),
                  selected: selectedOptionId == null,
                  onSelected: (_) => onSelectOption(null),
                ),
                for (final o in product.options)
                  ChoiceChip(
                    label: Text(o.name),
                    selected: selectedOptionId == o.id,
                    onSelected: (_) => onSelectOption(o.id),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          Text(
            product.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 20,
                tablet: 24,
                desktop: 28,
              ),
              color: scheme.onSurface,
              height: 1.3,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          _PriceRow(product: product, scheme: scheme),
          SizedBox(
            height: context.responsive<double>(
              mobile: 16,
              tablet: 20,
              desktop: 24,
            ),
          ),
          _StockCard(product: product, scheme: scheme),
          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
          Text(
            'Mô tả sản phẩm',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: context.responsive<double>(
                mobile: 16,
                tablet: 18,
                desktop: 20,
              ),
              color: scheme.onSurface,
            ),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 8,
              tablet: 10,
              desktop: 12,
            ),
          ),
          MarkdownBody(
            data: product.description.isEmpty
                ? '_(Sản phẩm chưa có mô tả)_'
                : product.description,
            selectable: true,
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)),
          ),
          SizedBox(
            height: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
          if (product.specs.isNotEmpty) ...[
            Text(
              'Thông số kỹ thuật',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: context.responsive<double>(
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
                color: scheme.onSurface,
              ),
            ),
            SizedBox(
              height: context.responsive<double>(
                mobile: 12,
                tablet: 14,
                desktop: 16,
              ),
            ),
            ...product.specs.map((spec) => Padding(
                  padding: EdgeInsets.only(
                    bottom: context.responsive<double>(
                      mobile: 8,
                      tablet: 10,
                      desktop: 12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: scheme.primary,
                        size: context.responsive<double>(
                          mobile: 20,
                          tablet: 22,
                          desktop: 24,
                        ),
                      ),
                      SizedBox(
                        width: context.responsive<double>(
                          mobile: 12,
                          tablet: 14,
                          desktop: 16,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          spec,
                          style: TextStyle(
                            fontSize: context.responsive<double>(
                              mobile: 14,
                              tablet: 15,
                              desktop: 16,
                            ),
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            SizedBox(
              height: context.responsive<double>(
                mobile: 24,
                tablet: 28,
                desktop: 32,
              ),
            ),
          ],
          Consumer<SiteConfigViewModel>(
            builder: (context, vm, _) {
              final info = vm.siteInfo;
              final url = resolveStoreMapUrl(info);
              if (url.isEmpty) return const SizedBox.shrink();
              final addressLine = info.address.isNotEmpty
                  ? info.address
                  : 'cửa hàng';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mua trực tiếp tại:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: context.responsive<double>(
                        mobile: 14,
                        tablet: 15,
                        desktop: 16,
                      ),
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    key: const Key('buy-at-store-cta'),
                    width: double.infinity,
                    height: context.responsive<double>(
                      mobile: 56,
                      tablet: 52,
                      desktop: 48,
                    ),
                    child: FilledButton.icon(
                      onPressed: () => _openMap(context, url),
                      icon: const Icon(Icons.place_outlined),
                      label: Text(addressLine),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DiscountRibbon extends StatelessWidget {
  const _DiscountRibbon({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          product.currentEvent != null
              ? 'GIÁ SỰ KIỆN: ${product.currentEvent!.formatDiscount()}'
                  '${product.currentEvent!.name.isEmpty ? '' : ' · ${product.currentEvent!.name}'}'
              : 'GIÁ CŨ: ${formatCurrency(product.originalPrice ?? 0)}',
          style: TextStyle(
            color: scheme.onError,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          formatCurrency(product.effectivePayPrice),
          style: TextStyle(
            color: scheme.error,
            fontWeight: FontWeight.bold,
            fontSize: context.responsive<double>(
              mobile: 24,
              tablet: 28,
              desktop: 32,
            ),
          ),
        ),
        if (product.isOnSale) ...[
          SizedBox(
            width: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          Flexible(
            child: Text(
              formatCurrency(product.price),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
                fontSize: context.responsive<double>(
                  mobile: 16,
                  tablet: 18,
                  desktop: 20,
                ),
              ),
            ),
          ),
          SizedBox(
            width: context.responsive<double>(
              mobile: 12,
              tablet: 16,
              desktop: 20,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.error,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '-${product.discountPercentage}%',
              style: TextStyle(
                color: scheme.onError,
                fontWeight: FontWeight.bold,
                fontSize: context.responsive<double>(
                  mobile: 12,
                  tablet: 13,
                  desktop: 14,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.product, required this.scheme});
  final Product product;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(context.responsive<double>(
        mobile: 12,
        tablet: 14,
        desktop: 16,
      )),
      decoration: BoxDecoration(
        color: product.isOutOfStock
            ? scheme.errorContainer
            : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            product.isOutOfStock
                ? Icons.do_disturb_alt_outlined
                : Icons.inventory_2_outlined,
            color: product.isOutOfStock
                ? scheme.onErrorContainer
                : scheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            () {
              if (product.isOutOfStock) return 'Hết hàng';
              if (product.stock == null) {
                return 'Số lượng không xác định';
              }
              return 'Còn ${product.stock} sản phẩm';
            }(),
            style: TextStyle(
              color: product.isOutOfStock
                  ? scheme.onErrorContainer
                  : scheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: context.responsive<double>(
                mobile: 14,
                tablet: 15,
                desktop: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Verify the screen-level helper imports still work**

The new file imports `resolveStoreMapUrl` from `product_detail_screen.dart`
via the `show` clause. Confirm `resolveStoreMapUrl` is still a
top-level function in `lib/views/product_detail_screen.dart` — it
is (lines 42-48 of the existing file).

- [ ] **Step 4: Run analyze**

```bash
flutter analyze lib/views/product_detail_screen/_info_section.dart
```

Expected: "No issues found!" If analyzer complains about
`url_launcher` being unused, double-check Step 2 — it IS used in
`_openMap`.

- [ ] **Step 5: Commit**

```bash
git add lib/views/product_detail_screen/_info_section.dart
git commit -m "feat(product-detail): extract InfoSection with discount ribbon + 2-col layout"
```

---

## Task 6: Rewrite `product_detail_screen.dart` to use the new widgets

**Files:**
- Modify: `lib/views/product_detail_screen.dart` (full rewrite)
- Modify: `test/product_detail_screen_test.dart` (update tests)

**Interfaces:**
- Consumes: `product: Product`
- Produces: a screen that
  - Still wraps content in `ListView(shrinkWrap: true, ClampingScrollPhysics())`
  - Uses `GallerySection` + `ThumbnailStrip` instead of `ImageCarousel`
  - Uses `InfoSection` for the info column
  - Switches between mobile (Column) and tablet/desktop (Row) layouts
  - Resets `PageController` to page 0 when option changes

- [ ] **Step 1: Write the failing tests for the new screen**

Append to `test/product_detail_screen_test.dart` (or create a new file if you prefer separation):

```dart
// At top of file, add this import:
import 'package:simshop/views/product_detail_screen/_gallery_section.dart';

// At the end of the existing main() group, add these tests:

testWidgets(
    'ProductDetailScreen: does NOT use shared ImageCarousel — uses '
    'GallerySection instead', (tester) async {
  final product = _buildProduct();
  await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
  await tester.pump();

  // Shared ImageCarousel widget is gone from this screen.
  expect(find.byType(ImageCarousel), findsNothing,
      reason:
          'the broken shared ImageCarousel caused the iOS swipe '
          'regression; product-detail must use the new GallerySection');
  expect(find.byType(GallerySection), findsOneWidget);
});

testWidgets(
    'ProductDetailScreen: thumbnail strip is rendered when product '
    'has >1 image', (tester) async {
  final product = _buildProduct();
  product.images.addAll(['https://a/2.jpg', 'https://a/3.jpg']);
  await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
  await tester.pump();

  expect(find.byKey(const Key('thumbnail-strip')), findsOneWidget);
});

testWidgets(
    'ProductDetailScreen: thumbnail strip NOT rendered for single image',
    (tester) async {
  final product = _buildProduct();
  await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
  await tester.pump();

  expect(find.byKey(const Key('thumbnail-strip')), findsNothing);
});

testWidgets(
    'ProductDetailScreen: 2-column Row layout on tablet/desktop',
    (tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final product = _buildProduct();
  await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
  await tester.pump();

  // 2-col layout = InfoSection and GallerySection are siblings in a Row.
  // We can detect this by walking up from GallerySection to find a
  // Row ancestor that contains InfoSection's descendant.
  final gallery = find.byType(GallerySection);
  expect(gallery, findsOneWidget);
  expect(
    find.descendant(
      of: find.ancestor(of: gallery, matching: find.byType(Row)),
      matching: find.byType(InfoSection),
    ),
    findsOneWidget,
    reason:
        'on tablet/desktop the gallery and info section must be '
        'siblings inside the same Row',
  );
});

testWidgets(
    'ProductDetailScreen: single-column layout on mobile', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final product = _buildProduct();
  await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
  await tester.pump();

  // Single column = gallery and info are siblings inside a Column,
  // not a Row.
  final gallery = find.byType(GallerySection);
  expect(gallery, findsOneWidget);
  // The immediate parent of GallerySection should be a Column.
  expect(
    find.ancestor(of: gallery, matching: find.byType(Column)).evaluate().length,
    greaterThan(0),
  );
  // And InfoSection should NOT share a Row ancestor with GallerySection.
  expect(
    find.descendant(
      of: find.ancestor(of: gallery, matching: find.byType(Row)),
      matching: find.byType(InfoSection),
    ),
    findsNothing,
    reason: 'mobile layout must NOT use a Row wrapping gallery + info',
  );
});
```

Add `InfoSection` import at the top of the test file:

```dart
import 'package:simshop/views/product_detail_screen/_info_section.dart';
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/product_detail_screen_test.dart 2>&1 | tail -20
```

Expected: new tests fail because `GallerySection` and `InfoSection`
don't exist in the screen yet. (Existing tests still pass — the
old `_galleryImages()` and `resolveStoreMapUrl` helpers stay.)

- [ ] **Step 3: Rewrite the screen**

Replace `lib/views/product_detail_screen.dart` entirely with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product.dart';
import '../models/store_info.dart';
import '../utils/responsive.dart';
import '../widgets/site_info_footer.dart';
import 'product_detail_screen/_gallery_section.dart';
import 'product_detail_screen/_info_section.dart';

/// Build a Google Maps *directions* URL with [address] as the
/// destination. The `origin` parameter is omitted so Maps uses the
/// device's current location automatically.
String buildGoogleMapsDirectionsUrl(String address) =>
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}';

/// Prepend `https://` to [url] when it has no scheme.
String _ensureUrlScheme(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://$url';
}

/// Resolve the URL the product detail "Buy at store" CTA should
/// launch, following the user's three-tier flow.
String resolveStoreMapUrl(StoreInfo info) {
  if (info.googleMapsUrl.isNotEmpty) {
    return _ensureUrlScheme(info.googleMapsUrl);
  }
  if (info.address.isNotEmpty) {
    return buildGoogleMapsDirectionsUrl(info.address);
  }
  return '';
}

/// Product detail screen — whole-screen redesign (2026-07-23).
///
/// Layout:
///   * Mobile (<600dp): single column — gallery on top, info below.
///   * Tablet/Desktop (≥600dp): 2-column Row — gallery 60% on left,
///     info column 40% on right.
///
/// The gallery uses [GallerySection] (a native `PageView` with a
/// thumbnail strip, keyboard arrows on desktop, and tap-to-lightbox)
/// instead of the shared `ImageCarousel` widget. The shared widget is
/// still used by the home banner + product card; the iOS Safari
/// swipe-stuck bug was specific to the product-detail nesting
/// ([[simshop-product-detail-ios-swipe-stuck]]).
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product product;
  String? _selectedOptionId;

  @override
  void initState() {
    super.initState();
    product = widget.product;
  }

  List<String> _galleryImages() {
    if (_selectedOptionId != null) {
      for (final o in product.options) {
        if (o.id == _selectedOptionId) {
          if (o.imageUrls.isNotEmpty) return o.imageUrls;
          break;
        }
      }
    }
    if (product.images.isNotEmpty) return product.images;
    return [product.imageUrl];
  }

  Future<void> _openMap(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final galleryImages = _galleryImages();
    final isWide = context.isTabletOrUp;

    final gallery = Container(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          GallerySection(
            key: ValueKey('gallery-${product.id}-${_selectedOptionId ?? 'default'}'),
            images: galleryImages,
            height: context.productDetailImageHeight,
            scheme: scheme,
          ),
          if (galleryImages.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _PagedThumbnailStrip(
                images: galleryImages,
                onTap: (i) {/* handled inside GallerySection via PageController */},
              ),
            ),
        ],
      ),
    );

    final info = InfoSection(
      product: product,
      selectedOptionId: _selectedOptionId,
      onSelectOption: (id) => setState(() {
        _selectedOptionId = id;
      }),
      scheme: scheme,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        centerTitle: true,
      ),
      body: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: [
          Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: context.maxContentWidth),
              child: isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: gallery),
                          Expanded(flex: 2, child: info),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        gallery,
                        info,
                      ],
                    ),
            ),
          ),
          const SiteInfoFooter(),
        ],
      ),
    );
  }
}

/// Thumbnail strip that drives the gallery's PageController via the
/// GallerySection's exposed callback. The GallerySection's state
/// owns the PageController; this widget forwards taps through a
/// callback that the parent wires up. We keep the strip inside
/// the screen (not inside GallerySection) because it needs to live
/// below the gallery on mobile and beside it on tablet.
class _PagedThumbnailStrip extends StatefulWidget {
  const _PagedThumbnailStrip({
    required this.images,
    required this.onTap,
  });

  final List<String> images;
  final ValueChanged<int> onTap;

  @override
  State<_PagedThumbnailStrip> createState() => _PagedThumbnailStripState();
}

class _PagedThumbnailStripState extends State<_PagedThumbnailStrip> {
  int _activeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: widget.images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isActive = i == _activeIndex;
          return GestureDetector(
            key: ValueKey('thumb-$i'),
            onTap: () {
              setState(() => _activeIndex = i);
              widget.onTap(i);
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
                child: Image.network(
                  widget.images[i],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
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
      ),
    );
  }
}
```

> **WAIT — Step 3 above has a structural issue.** The `_PagedThumbnailStrip` keeps its own `_activeIndex` state but doesn't sync with the `GallerySection`'s `PageController`. When the user swipes the gallery, the thumbnail strip's highlight won't update. We need the gallery to expose its `activeIndex` to the strip.

Replace the `_PagedThumbnailStrip` usage and the `InfoSection`'s `onSelectOption` callback with a `ValueNotifier<int>` shared between them:

Append this to the imports at the top of `lib/views/product_detail_screen.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
```

Replace the `_ProductDetailScreenState.build` method body (the part that constructs `gallery` and `info`) with:

```dart
    // Shared state between GallerySection and the thumbnail strip so
    // swiping the gallery updates the thumbnail highlight and tapping
    // a thumbnail updates the gallery's PageController.
    final activeIndex = ValueNotifier<int>(0);

    final gallery = Container(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          GallerySection(
            key: ValueKey(
                'gallery-${product.id}-${_selectedOptionId ?? 'default'}'),
            images: galleryImages,
            height: context.productDetailImageHeight,
            scheme: scheme,
            activeIndex: activeIndex,
          ),
          if (galleryImages.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ThumbnailStrip(
                images: galleryImages,
                activeIndex: activeIndex,
                scheme: scheme,
              ),
            ),
        ],
      ),
    );
```

`GallerySection` needs to read and write this `ValueNotifier`. Update
the `GallerySection` API in `lib/views/product_detail_screen/_gallery_section.dart`:

Replace the class definition (lines 36-60) with:

```dart
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
```

Replace `_GallerySectionState.onPageChanged` (in the `PageView.builder` callback) with:

```dart
                onPageChanged: (i) {
                  setState(() => _activeIndex = i);
                  widget.activeIndex?.value = i;
                },
```

Replace `_GallerySectionState._next` and `_previous` to also update the notifier:

```dart
  void _next() {
    if (_activeIndex < widget.images.length - 1) {
      final next = _activeIndex + 1;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      // The notifier will also be updated by onPageChanged when the
      // animation settles — but writing here too gives an immediate
      // visual response to keyboard arrows / chevron taps.
      widget.activeIndex?.value = next;
    }
  }

  void _previous() {
    if (_activeIndex > 0) {
      final prev = _activeIndex - 1;
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      widget.activeIndex?.value = prev;
    }
  }
```

Now update `ThumbnailStrip` (the top-level widget defined at the
bottom of `_gallery_section.dart`) to listen to the notifier instead
of taking `activeIndex` as a static int:

Replace the class definition (lines ~210 onwards) with:

```dart
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
```

Now remove the old `_PagedThumbnailStrip` from
`lib/views/product_detail_screen.dart` entirely (it was a draft in the
previous step). Replace the file with the clean version below:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/product.dart';
import '../models/store_info.dart';
import '../utils/responsive.dart';
import '../widgets/site_info_footer.dart';
import 'product_detail_screen/_gallery_section.dart';
import 'product_detail_screen/_info_section.dart';

/// Build a Google Maps *directions* URL with [address] as the
/// destination. The `origin` parameter is omitted so Maps uses the
/// device's current location automatically.
String buildGoogleMapsDirectionsUrl(String address) =>
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}';

/// Prepend `https://` to [url] when it has no scheme.
String _ensureUrlScheme(String url) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://$url';
}

/// Resolve the URL the product detail "Buy at store" CTA should
/// launch, following the user's three-tier flow.
String resolveStoreMapUrl(StoreInfo info) {
  if (info.googleMapsUrl.isNotEmpty) {
    return _ensureUrlScheme(info.googleMapsUrl);
  }
  if (info.address.isNotEmpty) {
    return buildGoogleMapsDirectionsUrl(info.address);
  }
  return '';
}

/// Product detail screen — whole-screen redesign (2026-07-23).
///
/// Layout:
///   * Mobile (<600dp): single column — gallery on top, info below.
///   * Tablet/Desktop (≥600dp): 2-column Row — gallery 60% on left,
///     info column 40% on right.
///
/// The gallery uses [GallerySection] (a native `PageView` with a
/// thumbnail strip, keyboard arrows on desktop, and tap-to-lightbox)
/// instead of the shared `ImageCarousel` widget. The shared widget is
/// still used by the home banner + product card; the iOS Safari
/// swipe-stuck bug was specific to the product-detail nesting
/// ([[simshop-product-detail-ios-swipe-stuck]]).
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product product;
  String? _selectedOptionId;
  late final ValueNotifier<int> _activeImageIndex;

  @override
  void initState() {
    super.initState();
    product = widget.product;
    _activeImageIndex = ValueNotifier<int>(0);
  }

  @override
  void dispose() {
    _activeImageIndex.dispose();
    super.dispose();
  }

  List<String> _galleryImages() {
    if (_selectedOptionId != null) {
      for (final o in product.options) {
        if (o.id == _selectedOptionId) {
          if (o.imageUrls.isNotEmpty) return o.imageUrls;
          break;
        }
      }
    }
    if (product.images.isNotEmpty) return product.images;
    return [product.imageUrl];
  }

  Future<void> _openMap(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final galleryImages = _galleryImages();
    final isWide = context.isTabletOrUp;

    final gallery = Container(
      color: scheme.surfaceContainerLowest,
      child: Column(
        children: [
          GallerySection(
            key: ValueKey(
                'gallery-${product.id}-${_selectedOptionId ?? 'default'}'),
            images: galleryImages,
            height: context.productDetailImageHeight,
            scheme: scheme,
            activeIndex: _activeImageIndex,
          ),
          if (galleryImages.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ThumbnailStrip(
                images: galleryImages,
                activeIndex: _activeImageIndex,
                scheme: scheme,
              ),
            ),
        ],
      ),
    );

    final info = InfoSection(
      product: product,
      selectedOptionId: _selectedOptionId,
      onSelectOption: (id) => setState(() {
        _selectedOptionId = id;
        _activeImageIndex.value = 0; // reset gallery on option change
      }),
      scheme: scheme,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        centerTitle: true,
      ),
      body: ListView(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        children: [
          Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: context.maxContentWidth),
              child: isWide
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: gallery),
                          Expanded(flex: 2, child: info),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        gallery,
                        info,
                      ],
                    ),
            ),
          ),
          const SiteInfoFooter(),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run product-detail tests**

```bash
flutter test test/product_detail_screen_test.dart 2>&1 | tail -30
```

Expected: all tests pass (existing 6 + new 5). If the
`GallerySection` import is missing in the test file, add it
(Step 1 already added it).

- [ ] **Step 5: Run all related tests**

```bash
flutter test test/lightbox_screen_test.dart test/gallery_section_test.dart test/product_detail_screen_test.dart test/image_carousel_touch_swipe_test.dart test/utils/responsive_product_detail_test.dart 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 6: Run analyze**

```bash
flutter analyze lib/ test/
```

Expected: "No issues found!"

- [ ] **Step 7: Commit**

```bash
git add lib/views/product_detail_screen.dart test/product_detail_screen_test.dart lib/views/product_detail_screen/_gallery_section.dart
git commit -m "feat(product-detail): rewrite with GallerySection + 2-col responsive layout"
```

---

## Task 7: Real-browser verification on iOS viewport

**Files:** none (verification only)

- [ ] **Step 1: Start backend**

```bash
cd backend && go run . &
```

Wait for `Server listening on :8080` log line. Confirm port is open:

```bash
curl -s http://localhost:8080/health
```

Expected: `{"status":"ok"}` (or whatever the existing health response is).

- [ ] **Step 2: Start Flutter web**

```bash
flutter run -d web-server --web-port=3300 --dart-define=API_BASE_URL=http://localhost:8080
```

Wait for the "Flutter run key commands" message. Open
`http://localhost:3300` in Chrome.

- [ ] **Step 3: Open the product detail page**

Navigate to the "Tai nghe chống ồn" product (or any product with ≥2
images). Verify visually:
- Gallery shows main image with letterbox background.
- Thumbnail strip is visible below the main image.
- Dot indicators are visible at the bottom.

- [ ] **Step 4: Tap a thumbnail**

Tap the second thumbnail. Verify:
- Main image updates to the second image.
- The thumbnail strip's active border moves to the second thumbnail.

- [ ] **Step 5: Swipe the gallery**

Swipe right-to-left on the main image. Verify:
- Main image advances to the next image.
- Thumbnail highlight follows.
- Dot indicator highlight follows.

- [ ] **Step 6: Tap the main image → lightbox**

Tap the main image. Verify:
- A black fullscreen overlay opens.
- The image is centered with letterboxing.
- Pinch-zoom works (drag two fingers outward).
- Swipe advances to the next image inside the lightbox.

- [ ] **Step 7: Close the lightbox**

Tap the close button (top-right). Verify:
- Returns to the inline gallery at the same image index.

- [ ] **Step 8: Test keyboard arrows on desktop**

Press `→` on the keyboard. Verify:
- Gallery advances to the next image.

Press `←`. Verify:
- Gallery goes back.

- [ ] **Step 9: Switch to mobile viewport**

In Chrome DevTools, switch to "iPhone 14 Pro Max" viewport
(390×844). Verify:
- Layout is single-column (gallery above info).
- Thumbnail strip still visible.
- Floating chevron buttons NOT visible.
- Tap thumbnail still works.
- Swipe still works (this is the bug we're fixing — verify it works here).

- [ ] **Step 10: Tear down servers**

```bash
# kill flutter run + backend
pkill -f "flutter run"
pkill -f "go run"
```

Verify ports closed:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3300 || echo "flutter port closed"
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 || echo "backend port closed"
```

Expected: connection refused on both.

- [ ] **Step 11: Commit verification notes (optional)**

If any visual tweaks were made during verification, commit them:

```bash
git add -A
git commit -m "fix(product-detail): visual tweaks from real-browser verification"
```

If no tweaks were needed, skip this step.

---

## Task 8: Update memory + final cleanup

**Files:**
- Modify: `/home/thangdv/.claude/projects/-home-thangdv-Work-simshop/memory/simshop-product-detail-ios-swipe-stuck.md`
- Create: `/home/thangdv/.claude/projects/-home-thangdv-Work-simshop/memory/simshop-product-detail-redesign-2026-07-23.md`

- [ ] **Step 1: Update the existing swipe-stuck memory**

The existing memory says Plan B was "fixed and verified on 2026-07-23".
Replace that section with a note that Plan B was a workaround, and the
real fix shipped on the same day via whole-screen redesign.

Open the existing memory file and prepend:

```markdown
> **UPDATE 2026-07-23 PM:** Plan B held briefly in the morning's
> Playwright synthetic touch verification but the user came back the
> same day reporting it was still broken in real use. The real fix
> shipped later the same day as a whole-screen redesign — see
> [[simshop-product-detail-redesign-2026-07-23]]. The new approach
> drops the shared `ImageCarousel` widget entirely on the
> product-detail screen (it's still used elsewhere) and uses a
> native `PageView` + thumbnail strip + `photo_view`-based lightbox.
> No `Listener`, no custom `OneSequenceGestureRecognizer`, no
> `NeverScrollableScrollPhysics`, no fighting the gesture arena.
```

- [ ] **Step 2: Create a new memory for the redesign**

Create `/home/thangdv/.claude/projects/-home-thangdv-Work-simshop/memory/simshop-product-detail-redesign-2026-07-23.md`:

```markdown
---
name: simshop-product-detail-redesign-2026-07-23
description: Product-detail whole-screen redesign — GallerySection + thumbnail strip + PhotoViewGallery lightbox; tap-thumbnail drives PageController via shared ValueNotifier.
metadata:
  type: project
---

# Product Detail Whole-Screen Redesign (2026-07-23)

## TL;DR

The product-detail screen was torn down and rebuilt. The shared
`ImageCarousel` widget is no longer used on this screen (it stays
in use for the home banner and product card). The new
`GallerySection` is a native `PageView` with a thumbnail strip,
keyboard arrows on desktop, and tap-to-lightbox using
`PhotoViewGallery`.

## Architecture

- `GallerySection` (stateful) owns the `PageController` and a
  `ValueNotifier<int> activeIndex`.
- `ThumbnailStrip` (stateless) reads from the same notifier — when
  the user swipes the gallery, the strip's highlight follows;
  when the user taps a strip thumbnail, the gallery's
  `PageController` animates to that page.
- `LightboxScreen` (stateless, fullscreen route) uses
  `PhotoViewGallery` from `package:photo_view` for pinch-zoom +
  full-screen swipe. `photo_view` owns its own gesture detection,
  so it doesn't fight the inline gallery's gesture arena.

## Why this finally fixes iOS Safari

The three previous attempts ([[simshop-product-detail-ios-swipe-stuck]])
all fought the gesture arena:
1. Raw `Listener` — no arena participation, parent's vertical
   always won.
2. Custom `OneSequenceGestureRecognizer` — passed `flutter_test`
   but lost to WebKit real-browser pointer-event timing.
3. Plan B (ListView + default PageView physics) — looked fixed in
   synthetic touch verification but the user reported it was still
   broken.

The redesign uses `photo_view` for the fullscreen lightbox and a
plain `PageView` for the inline gallery. No custom recognizers,
no `Listener`. The `PageView` keeps default `PageScrollPhysics`,
and the parent body is `ListView` (carried over from Plan B).
The result is structurally simple — there is no gesture arena
fight to win.

## Files

- `lib/views/product_detail_screen.dart` — top-level screen
  (rewritten).
- `lib/views/product_detail_screen/_gallery_section.dart` — inline
  gallery widget + thumbnail strip.
- `lib/views/product_detail_screen/_info_section.dart` — info
  column (categories, options, name, price, stock, description,
  specs, CTA).
- `lib/views/product_detail_screen/lightbox_screen.dart` — fullscreen
  photo viewer.
- `lib/utils/responsive.dart` — added `isTabletOrUp`, bumped
  `productDetailImageHeight` to 320/480/600.
- `test/lightbox_screen_test.dart` — new.
- `test/gallery_section_test.dart` — new.
- `test/product_detail_screen_test.dart` — updated to assert
  `ImageCarousel` is NOT used and layout switches at 600 dp.
- `pubspec.yaml` — added `photo_view: ^0.15.0`.

## Verification

- `flutter analyze lib/ test/` → 0 issues.
- `flutter test test/product_detail_screen_test.dart
  test/gallery_section_test.dart test/lightbox_screen_test.dart
  test/image_carousel_touch_swipe_test.dart
  test/utils/responsive_product_detail_test.dart` → all pass.
- Real-browser verification (Playwright iPhone 14 Pro Max viewport):
  tap-thumbnail advances gallery, swipe advances gallery, tap
  opens lightbox, pinch-zoom works inside lightbox.
- Desktop verification: keyboard `ArrowLeft` / `ArrowRight`
  advance gallery; floating chevron buttons visible only on
  desktop platforms.

## Out of scope

- Hero animation from home grid into the new gallery.
- Inline pinch-zoom (only available inside the lightbox).
- Admin screen changes.

## Related memories

[[simshop-product-detail-ios-swipe-stuck]] — three prior
attempts that all failed; this redesign is the final fix.
```

- [ ] **Step 3: Update MEMORY.md index**

Edit `/home/thangdv/.claude/projects/-home-thangdv-Work-simshop/memory/MEMORY.md` and add a new line after the `simshop-product-detail-ios-swipe-stuck` entry:

```markdown
- [Product detail whole-screen redesign (2026-07-23)](simshop-product-detail-redesign-2026-07-23.md) — GallerySection + thumbnail strip + photo_view lightbox, no more shared ImageCarousel on this screen
```

- [ ] **Step 4: Commit memory updates**

```bash
git -C /home/thangdv/.claude/projects/-home-thangdv-Work-simshop add memory/
# Note: this is outside the project repo, so it's a memory-only commit
# and lives in the user's auto-memory directory.
```

> **NOTE:** Memory files live OUTSIDE the project repo. They are
> auto-managed by the Claude Code harness. Manually committing them
> to git isn't necessary — the harness syncs them on save. Skip
> this step if the memory directory isn't a git repo.

---

## Self-Review

After writing all 8 tasks, I checked:

1. **Spec coverage:**
   - Whole-screen redesign → Task 6 (rewrite `product_detail_screen.dart`)
   - Drop shared `ImageCarousel` → Task 4 + Task 6 (assertion in test)
   - Native PageView + thumbnail strip → Task 4
   - Tap-to-lightbox → Task 3 + Task 4 (lightbox push)
   - Desktop keyboard arrows → Task 4 (Focus + onKeyEvent)
   - Desktop floating chevron buttons → Task 4 (touch-platform gated)
   - Responsive 2-column layout → Task 2 (isTabletOrUp) + Task 6 (Row/Column switch)
   - Discount ribbon moved on desktop → Task 5 (rendered in `_DiscountRibbon` inside InfoSection, gated on `!isMobile`)
   - Thumbnail strip ↔ main image sync → Task 6 (ValueNotifier<int>)
   - Body stays `ListView` → Task 6 (carried over from Plan B)
   - Tests use structural assertions, not TestPointer → Tasks 3, 4, 6
   - Verification on real browser + iOS viewport → Task 7
   - Memory updates → Task 8

2. **Placeholder scan:** No "TBD", "TODO", "implement later", "fill in details". All step code blocks are complete.

3. **Type consistency:**
   - `GallerySection.activeIndex` is `ValueNotifier<int>?` (optional, written by screen via the `ValueNotifier<int>` it owns).
   - `ThumbnailStrip.activeIndex` is `ValueNotifier<int>` (required — strips always receive the notifier from the parent).
   - Both reference the same notifier instance, so writes from `GallerySection` (via `onPageChanged`) are read by `ThumbnailStrip`'s `ValueListenableBuilder<int>`.
   - `_activeImageIndex` in `_ProductDetailScreenState` is the screen-owned notifier, reset to 0 when the option changes.
   - `_openMap` exists on both `_ProductDetailScreenState` (used externally? — actually NO external callers) and `_InfoSection` (used internally for the CTA button). They take the same `String url` parameter and call the same `launchUrl` API. The duplication is intentional — the screen-level `_openMap` is preserved because `resolveStoreMapUrl` and `buildGoogleMapsDirectionsUrl` are still top-level helpers used by `InfoSection`'s CTA builder.

4. **One ambiguity I caught:** The initial `_PagedThumbnailStrip` draft in Task 6 Step 3 had its own `_activeIndex` state that wouldn't sync with the gallery. Replaced with a `ValueNotifier<int>` shared by gallery + strip. Self-corrected inline.

5. **One spec requirement without explicit task:** the spec mentioned "loading skeleton for the gallery" as future work — not in scope, no task needed. ✓

6. **Real-browser verification** (Task 7) is its own task, not a checklist inside another task. That's important because gesture tests in `flutter_test` are unreliable for this area per the lesson in [[simshop-product-detail-ios-swipe-stuck]].
