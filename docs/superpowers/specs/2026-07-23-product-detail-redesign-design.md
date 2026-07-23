# Product Detail Screen — Whole-Screen Redesign (Gallery + Layout)

**Date:** 2026-07-23
**Status:** Approved (in design phase)
**Author:** Claude + thangdv
**Related memory:** [[simshop-product-detail-ios-swipe-stuck]]

## Problem

The product-detail screen's image gallery has been broken on iOS Safari
across three separate attempts. The current Plan B (`SingleChildScrollView`
→ `ListView` swap + default `PageScrollPhysics`) was reported as "fixed"
after real-browser verification but the user came back on the same day
saying it is still not fixed. Plan B was a workaround, not a real fix.

Three iteration outcomes (from memory
[[simshop-product-detail-ios-swipe-stuck]]):

1. Raw `Listener` — failed silently (no arena participation).
2. Custom `OneSequenceGestureRecognizer` — passed `flutter_test`
   `TestPointer` but lost to WebKit real-browser pointer-event timing.
3. Plan B (ListView + default PageView physics) — looked fixed in
   Playwright synthetic touch verification, but the user reports it is
   still broken in real-world use.

The carousel is also structurally small (single image with dot
indicators). The product-detail screen has not been meaningfully
redesigned since the project started.

The user explicitly asked for a "đập đi xây lại" (tear-down + rebuild)
approach, including renewal of the image gallery section. They also
asked for the product-detail screen as a whole to be redesigned.

## Goals

- **Fix the iOS swipe bug once and for all** by using a third-party
  package (`photo_view`) that has been battle-tested on iOS WebKit,
  rather than relying on Flutter's gesture arena logic that has failed
  three times.
- **Refresh the product-detail UX** so it feels intentional, not just a
  stack of sections.
- **Keep the rest of the app working** — the existing `ImageCarousel`
  widget stays in use for the home banner and product card; the
  redesign is scoped to the product-detail screen only.
- **Keep the screen fully usable without a mouse** — mobile-first
  navigation via tap and swipe; desktop gets keyboard arrows as a
  bonus, not as the primary input.

## Non-goals

- No video player, no 360° viewer, no AR.
- No inline pinch-zoom (zoom is only available inside the lightbox).
- No theme change, no color palette revision.
- No admin-screen refactoring.
- No new analytics events.

## Approach

Replace the broken carousel+SCV scaffolding with a small set of
focused widgets:

1. **Inline gallery** — native `PageView` (default `PageScrollPhysics`),
   `CachedNetworkImage` for the per-slide image, no custom gesture
   recognizers, no `Listener`-based wheel/trackpad hack.
2. **Thumbnail strip** — horizontal `ListView.separated` of small
   thumbnails directly under the main image. Tap a thumbnail →
   `PageController.animateToPage(i)`. This is the *primary* navigation
   path and is what fixed UX looks like.
3. **Lightbox** — a separate fullscreen route built with `photo_view`'s
   `PhotoViewGallery`. Tap the main image to open it. Inside the
   lightbox the user can swipe between images and pinch-zoom; closing
   the lightbox returns to the inline gallery at the same index.
4. **Keyboard arrows on desktop** — a `Focus` + `onKeyEvent` on the
   gallery area listens for `ArrowLeft` / `ArrowRight` and calls
   `_previous()` / `_next()`. Mobile platforms never see the arrows.
5. **Responsive 2-column layout on tablet/desktop** — gallery on the
   left (60% width), info column on the right (40%). Single-column
   stack stays on mobile.

`ImageCarousel` (the existing shared widget) is **not used** in the
new product-detail screen. It is still used by the home banner and the
product-card hero — those don't have the iOS gesture-arena bug because
they're not nested inside a vertical scroll view.

## Architecture

### Components

```
lib/views/product_detail_screen.dart       (rewritten)
└── _ProductDetailScreenState
    ├── ListView (body, shrinkWrap: true, ClampingScrollPhysics)
    │   ├── Responsive layout switch
    │   │   ├── Mobile (<600dp): Column
    │   │   │   ├── _GallerySection (inline gallery + thumbnails + dots + desktop arrows)
    │   │   │   ├── _InfoSection   (categories, options, name, price, stock, description, specs, CTA)
    │   │   │   └── SiteInfoFooter
    │   │   └── Tablet/Desktop (≥600dp): Row
    │   │       ├── _GallerySection (60%)
    │   │       └── _InfoSection   (40%)
    │       └── SiteInfoFooter (full width)

lib/views/product_detail_screen/_gallery_section.dart    (new)
└── StatefulWidget with PageController
    ├── Focus (keyboard arrows on desktop)
    ├── PageView.builder (CachedNetworkImage, default physics)
    ├── Thumbnail strip (ListView.separated, horizontal)
    ├── Dot indicators (small horizontal row, only when n > 1)
    ├── Desktop floating chevron buttons (touch platform → not rendered)
    └── Tap main image → push LightboxScreen

lib/views/product_detail_screen/_info_section.dart       (new)
└── StatelessWidget: categories, options, name, price, stock, description, specs, CTA

lib/views/product_detail_screen/lightbox_screen.dart    (new)
└── StatelessWidget: PhotoViewGallery + close button + page indicator
```

### State

In `_ProductDetailScreenState`:

```dart
Product product;             // immutable
String? _selectedOptionId;   // null = default; otherwise the option id
```

In `_GallerySectionState`:

```dart
late PageController _pageController;
int _activeIndex = 0;        // synced with PageView.onPageChanged
```

`_GallerySection` is `StatefulWidget` because it owns the
`PageController` and the active-index state. The parent screen stays
`StatefulWidget` only for the option-picker state — a `ValueNotifier`
or callback for the active index is unnecessary because the thumbnail
strip + PageView are siblings inside `_GallerySection`, not scattered
across the screen.

### Data flow

```
product.images ──┐
                 ├── _galleryImages() ──┬── PageView builder
product.options  │                       ├── Thumbnail strip items
selectedOption ──┘                       └── Lightbox initialIndex
                                          (via _activeIndex)

tap thumbnail ──> PageController.animateToPage(i)
              ──> onPageChanged ──> setState(_activeIndex)

PageView swipe ──> onPageChanged ──> setState(_activeIndex)
                              ──> thumbnail highlight updates

ArrowLeft (desktop) ──> _pageController.previousPage()
ArrowRight (desktop) ──> _pageController.nextPage()

tap main image ──> Navigator.push(LightboxScreen(images, initialIndex: _activeIndex))
```

### Layout

**Mobile (width < 600dp):**

```
┌─────────────────────────┐
│  AppBar                 │
├─────────────────────────┤
│ ╔═══════════════════╗   │  ← 320dp tall
│ ║                   ║   │
│ ║   Main Image      ║   │  BoxFit.contain
│ ║                   ║   │  tap → lightbox
│ ╚═══════════════════╝   │  swipe ← / →
│   ●  ○  ○  ○            │  dot indicators
│  [thumb][thumb][thumb]  │  64dp strip
├─────────────────────────┤
│ [category pills]        │
│ [option chips]          │
│ Product Name            │
│ 199.000đ  -20%          │
│ [stock card]            │
│ Description (markdown)  │
│ Specs                   │
│ [Buy at store CTA]      │
│ SiteInfoFooter          │
└─────────────────────────┘
```

Discount ribbon (mobile): positioned top-right inside the image
container, overlapping the main image (kept from the current screen).

**Tablet/Desktop (width ≥ 600dp):**

```
┌──────────────────────────────────────────────┐
│  AppBar                                     │
├────────────────────────────┬─────────────────┤
│ ╔══════════════════════╗   │ [cat pills]     │
│ ║                      ║   │ [opt chips]     │
│ ║     Main Image       ║   │ Product Name    │
│ ║                      ║   │ 199.000đ  -20%  │
│ ╚══════════════════════╝   │ [stock card]    │
│   ●  ○  ○  ○              │ Description     │
│  [thumb][thumb][thumb]    │ Specs           │
│  ‹                      › │ [Buy CTA]       │
│  (desktop chevrons only)  │ Discount ribbon │
│                            │ (in info col)   │
├────────────────────────────┴─────────────────┤
│ SiteInfoFooter                               │
└──────────────────────────────────────────────┘
```

Discount ribbon (desktop): moved into the info column, rendered as a
card right under the price row instead of overlapping the image. This
matches the column layout — no overlap, no clipping.

### Thumbnail strip

```
ListView.separated(
  scrollDirection: Axis.horizontal,
  padding: EdgeInsets.symmetric(horizontal: 8),
  itemCount: galleryImages.length,
  separatorBuilder: (_, __) => SizedBox(width: 8),
  itemBuilder: (context, i) => GestureDetector(
    onTap: () => _pageController.animateToPage(
      i,
      duration: Duration(milliseconds: 250),
      curve: Curves.easeOut,
    ),
    child: Container(
      width: 64, height: 64,
      decoration: BoxDecoration(
        border: Border.all(
          color: i == _activeIndex ? scheme.primary : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: galleryImages[i],
          fit: BoxFit.cover,
        ),
      ),
    ),
  ),
)
```

The strip only renders when `galleryImages.length > 1`. A single-image
product would show a bare thumbnail of itself, which is noise.

### Lightbox

```dart
class LightboxScreen extends StatelessWidget {
  const LightboxScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  final List<String> images;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            itemCount: images.length,
            pageController: PageController(initialPage: initialIndex),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            builder: (context, i) => PhotoViewGalleryPageOptions(
              imageProvider: CachedNetworkImageProvider(images[i]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
```

Pinch-zoom and double-tap-zoom are provided by `photo_view` out of the
box. The lightbox handles its own pointer events — they do NOT
participate in any gesture arena with the inline gallery.

### Keyboard arrows

```dart
Focus(
  autofocus: _hasKeyboard,
  onKeyEvent: (node, event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _previousImage();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _nextImage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },
  child: ...,
)
```

`_hasKeyboard` is a static getter that mirrors the existing
`_hasMousePointer` helper in `image_carousel.dart`:

```dart
static bool get _hasKeyboard {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return true;
    default:
      return false;
  }
}
```

`autofocus: true` only on desktop means the gallery grabs keyboard
focus on first build. Mobile platforms leave focus where it was —
typing still goes into form fields elsewhere.

### Inline gallery PageView

```dart
PageView.builder(
  controller: _pageController,
  onPageChanged: (i) => setState(() => _activeIndex = i),
  itemCount: galleryImages.length,
  itemBuilder: (context, i) => GestureDetector(
    onTap: () => Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LightboxScreen(
        images: galleryImages,
        initialIndex: i,
      ),
    )),
    child: CachedNetworkImage(
      imageUrl: galleryImages[i],
      fit: BoxFit.contain,
      placeholder: (_, __) => Container(
        color: scheme.surfaceContainerLowest,
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (_, __, ___) => Container(
        color: scheme.surfaceContainerLowest,
        child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
      ),
    ),
  ),
)
```

No `Listener`, no custom recognizer, no `NeverScrollableScrollPhysics`,
no manual wheel/trackpad handler. `PageView` handles touch swipes
itself; desktop wheel/trackpad is a bonus that comes for free with
`PageView`'s built-in scroll handling when the PageView is the focused
widget.

### Desktop chevron buttons

Rendered only when `_hasKeyboard == true`. Two floating `IconButton`s,
one on each side, with `Icons.chevron_left` / `Icons.chevron_right`.
Hidden on touch platforms because they would cover the swipe area —
same lesson from
[[simshop-product-detail-ios-swipe-stuck]].

```dart
if (_hasKeyboard)
  Positioned(
    left: 8, top: 0, bottom: 0,
    child: Center(child: IconButton.filled(
      icon: const Icon(Icons.chevron_left),
      onPressed: _activeIndex > 0 ? _previousImage : null,
    )),
  ),
```

The button is disabled (not hidden) when there is no previous / next
slide — this matches the existing `CarouselNavButton` pattern in
`image_carousel.dart`.

## Files changed / added

| File | Action | Reason |
|---|---|---|
| `pubspec.yaml` | Edit | Add `photo_view: ^0.15.0` |
| `lib/views/product_detail_screen.dart` | Rewrite | Whole-screen redesign |
| `lib/views/product_detail_screen/_gallery_section.dart` | New | Inline gallery + thumbnails + dots + desktop arrows |
| `lib/views/product_detail_screen/_info_section.dart` | New | Categories, options, price, stock, description, specs, CTA |
| `lib/views/product_detail_screen/lightbox_screen.dart` | New | `PhotoViewGallery` fullscreen route |
| `lib/utils/responsive.dart` | Edit | Add `productDetailImageHeight`, `isTabletOrUp` |
| `test/product_detail_screen_test.dart` | Update | Pin: ListView parent, no `ImageCarousel`, thumbnail strip, layout switch |
| `test/lightbox_screen_test.dart` | New | Pin: initialIndex, close button pops route |

`test/image_carousel_touch_swipe_test.dart` stays unchanged — the
`ImageCarousel` widget is still used by the home banner; the bug was
specifically in the product-detail screen.

## Dependencies

Add to `pubspec.yaml`:

```yaml
dependencies:
  photo_view: ^0.15.0
```

`photo_view` is maintained by the Flutter team (formerly `photo_view`
on pub.dev) and is the de-facto choice for pinch-zoom image viewers.
It handles its own gesture detection inside its own subtree, which
sidesteps the iOS gesture-arena problem entirely.

`cached_network_image: ^3.3.0` is already in `pubspec.yaml` — used for
both thumbnails and main images in the redesign.

## Error handling

- **Empty `imageUrls`:** `_galleryImages()` falls back to
  `[product.imageUrl]` (current behavior preserved).
- **Image load failure:** `CachedNetworkImage.errorWidget` renders an
  outlined `broken_image` icon over the letterbox background.
- **Single image:** Thumbnail strip is not rendered; dot indicators are
  not rendered; keyboard arrows / desktop chevrons are still rendered
  but disabled.
- **Option switch:** `_pageController.jumpToPage(0)` resets to the
  first image of the new variant's gallery.
- **Lightbox dismissal:** Standard `Navigator.pop` returns the user to
  the inline gallery at the same index (we don't try to sync back).

## Testing

All tests are **structural**, not gesture-based. The lesson from
[[simshop-product-detail-ios-swipe-stuck]] is that `flutter_test`'s
`TestPointer` does not reproduce WebKit's pointer-event timing, so any
gesture-based test in this area is unreliable.

### `test/product_detail_screen_test.dart` updates

Existing tests are preserved (description rendering, fallback, CTA
labels, `buildGoogleMapsDirectionsUrl`, `resolveStoreMapUrl`).

New / updated structural tests:

1. **Body wraps content in a `ListView`, not a `SingleChildScrollView`.**
   `expect(find.byType(SingleChildScrollView), findsNothing)` +
   `expect(find.byType(ListView), findsWidgets)`. (Carried over from
   Plan B.)

2. **Inline gallery does NOT use the shared `ImageCarousel` widget.**
   `expect(find.byType(ImageCarousel), findsNothing)` in the product
   detail body. Pins the architectural decision to stop using the
   shared widget here.

3. **Inline gallery PageView uses default `PageScrollPhysics`.**
   `expect(pageView.physics, isNot(isA<NeverScrollableScrollPhysics>()))`.
   (Carried over from Plan B.)

4. **Thumbnail strip renders N items when there are N images.**
   `find.descendant(of: find.byKey(Key('thumbnail-strip')), matching: find.byType(GestureDetector))`
   returns N widgets.

5. **Thumbnail strip is not rendered when there is a single image.**
   `expect(find.byKey(Key('thumbnail-strip')), findsNothing)`.

6. **Two-column layout on tablet/desktop, single-column on mobile.**
   Render the screen at `Size(800, 600)` and assert that
   `find.byType(Row)` is present. Render at `Size(390, 844)` and assert
   that the gallery and info are siblings inside a `Column` instead.

7. **Tap on a thumbnail triggers `_pageController.animateToPage(i)`.**
   Verify by tapping the second thumbnail and asserting
   `_activeIndex == 1` via a `@visibleForTesting` accessor on
   `_GallerySectionState`.

8. **Tap on the main image pushes a `LightboxScreen` route.**
   `expect(find.byType(LightboxScreen), findsOneWidget)` after
   `tester.tap(find.byKey(Key('main-image-tap-target')))`.

### `test/lightbox_screen_test.dart` (new)

1. **Renders the correct initial image.**
   Build `LightboxScreen(images: [a, b, c], initialIndex: 1)` and
   assert the second `CachedNetworkImageProvider` is mounted.

2. **Close button pops the route.**
   `tester.tap(find.byIcon(Icons.close))` →
   `expect(find.byType(LightboxScreen), findsNothing)`.

3. **Page count matches image count.**
   `find.byType(PhotoViewGalleryPageOptions)` returns `images.length`.

### `test/image_carousel_touch_swipe_test.dart`

Unchanged. The shared `ImageCarousel` widget still exists; we only
stopped using it on the product-detail screen.

## Verification flow

1. `flutter pub get` — installs `photo_view`.
2. `flutter analyze lib/views/product_detail_screen.dart
   lib/views/product_detail_screen/ lib/utils/responsive.dart
   test/product_detail_screen_test.dart test/lightbox_screen_test.dart`
   → "No issues found!".
3. `flutter test test/product_detail_screen_test.dart
   test/lightbox_screen_test.dart test/image_carousel_touch_swipe_test.dart`
   → all pass.
4. **Real-browser verification** (Playwright on
   `http://localhost:3300/`, iPhone 14 Pro Max viewport 390×844):
   - Tap the second thumbnail → main image updates.
   - Swipe horizontally on the main image → main image updates,
     thumbnail highlight follows.
   - Tap the main image → lightbox opens with the correct image.
   - Inside the lightbox, swipe → next image; pinch zoom → image
     zooms; tap close → return to inline gallery.
5. **Desktop verification** (`flutter run -d chrome`, 1280×800):
   - Gallery grabs keyboard focus on first build.
   - ArrowLeft / ArrowRight advance the page.
   - Floating chevron buttons advance the page.
   - Tap thumbnail advances the page.

## Open questions

None — all clarified during brainstorming.

## Future work (out of scope for this spec)

- Shared-element Hero animation from home grid into the product-detail
  gallery.
- Loading skeleton for the gallery (currently a `CircularProgressIndicator`
  per slide).
- Analytics events on swipe / option-pick / lightbox-open.
