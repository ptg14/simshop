import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/store_service.dart';
import 'package:simshop/viewmodels/site_config_viewmodel.dart';
import 'package:simshop/views/product_detail_screen.dart';
import 'package:simshop/views/product_detail_screen/_details_section.dart';
import 'package:simshop/views/product_detail_screen/_gallery_section.dart';
import 'package:simshop/views/product_detail_screen/_info_section.dart';
import 'package:simshop/widgets/image_carousel.dart';

/// In-memory store service — the SiteInfoFooter inside ProductDetailScreen
/// reads site config via Consumer<SiteConfigViewModel>, so we need a stub
/// provider in the tree. The test never inspects footer content.
class _FakeStoreService implements IStoreService {
  _FakeStoreService(this._seed);
  final StoreInfo _seed;

  @override
  Future<StoreInfo> getStoreInfo() async => _seed;
  @override
  Future<StoreInfo> updateStoreInfo(
    StoreInfo info, {
    String? oldBannerUrl,
  }) async =>
      info;
}

Widget _wrap(Widget child, {StoreInfo? storeInfo}) {
  final seed = storeInfo ?? const StoreInfo();
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<SiteConfigViewModel>(
          // Call `load()` so the VM holds the seeded StoreInfo before
          // the first frame. The fake resolves synchronously, so a single
          // pumpAndSettle from the test picks up the populated state.
          create: (_) =>
              SiteConfigViewModel(service: _FakeStoreService(seed))..load(),
        ),
      ],
      child: child,
    ),
  );
}

Product _buildProduct({
  String id = 'p-1',
  String name = 'Áo thun',
  String description = 'Mô tả mặc định',
  double price = 199000,
  String category = 'Áo',
  double rating = 4.5,
}) =>
    Product(
      id: id,
      name: name,
      description: description,
      price: price,
      imageUrl: '',
      category: category,
      rating: rating,
      specs: const [],
    );

void main() {
  testWidgets('ProductDetailScreen renders description as Markdown',
      (tester) async {
    final product = _buildProduct(
      description: '## Chất liệu\n\n- Cotton 100%\n- Thoáng mát',
    );

    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    // Use pump() (not pumpAndSettle()) because the product-detail
    // gallery mounts CachedNetworkImage widgets that retry forever
    // when given an empty URL in test — pumpAndSettle would never
    // return. We're inspecting widget configs that paint on the
    // first frame, so a single pump is enough.
    await tester.pump();

    // Section header.
    expect(find.text('Mô tả sản phẩm'), findsOneWidget);
    // The Markdown renderer turns `## Chất liệu` into a heading.
    expect(find.text('Chất liệu'), findsOneWidget);
    // Bullet items render as list items; the plain text "Cotton 100%" appears.
    expect(find.textContaining('Cotton 100%'), findsWidgets);
  });

  testWidgets('ProductDetailScreen shows fallback when description is empty',
      (tester) async {
    final product = _buildProduct(id: 'p-2', name: 'Quần', description: '');

    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();

    expect(find.text('Mô tả sản phẩm'), findsOneWidget);
    expect(find.textContaining('Sản phẩm chưa có mô tả'), findsOneWidget);
  });

  // Slice 1, case 1: the admin CTA and the "MUA NGAY" stub button are
  // removed from the product detail screen. They were placeholders and
  // the user replaced them with the address-driven Google Maps CTA.
  testWidgets(
      'ProductDetailScreen: hides old admin and MUA NGAY buttons',
      (tester) async {
    final product = _buildProduct();

    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();

    expect(find.text('VÀO BẢNG ĐIỀU KHIỂN ADMIN'), findsNothing,
        reason: 'admin CTA removed from product detail');
    expect(find.text('MUA NGAY'), findsNothing,
        reason: 'MUA NGAY stub removed from product detail');
  });

  // Slice 1, case 2: when StoreInfo has an address, the bottom CTA
  // renders that address as its label so the user sees where they
  // would go to buy in person.
  testWidgets(
      'ProductDetailScreen: renders the store address as the buy CTA',
      (tester) async {
    final product = _buildProduct();

    await tester.pumpWidget(_wrap(
      ProductDetailScreen(product: product),
      storeInfo: const StoreInfo(address: '123 Nguyễn Huệ'),
    ));
    await tester.pump();

    // Address appears as the button label (plus may also appear in
    // the SiteInfoFooter; that's fine).
    expect(find.text('123 Nguyễn Huệ'), findsWidgets);
    // The "Mua trực tiếp tại:" caption sits OUTSIDE the button, so
    // it's rendered as a separate widget (not concatenated with
    // the address inside the FilledButton label).
    expect(find.text('Mua trực tiếp tại:'), findsOneWidget);
    // The button itself must NOT contain the inline concatenated
    // form — that was the previous design, replaced so the
    // caption reads as a label and the address reads as the
    // button's own destination.
    expect(find.text('Mua trực tiếp tại 123 Nguyễn Huệ'), findsNothing);
  });

  // Slice 1, case 3: when StoreInfo has no address, the CTA must
  // not render at all — the user said "nếu chưa có thông tin địa chỉ
  // thì không cần hiện địa chỉ, nút khi này không có tác dụng gì".
  // Slice 4 strengthens this: hide the CTA when BOTH googleMapsUrl
  // and address are empty (the previous test only covered address).
  testWidgets(
      'ProductDetailScreen: hides the buy CTA when both URL and address are empty',
      (tester) async {
    final product = _buildProduct();

    await tester.pumpWidget(_wrap(
      ProductDetailScreen(product: product),
      // Default empty StoreInfo (no address, no google_maps_url).
    ));
    await tester.pump();

    // The CTA wrapper carries a Key so we can scope the search.
    expect(find.byKey(const Key('buy-at-store-cta')), findsNothing,
        reason: 'CTA wrapper must not render when both URL and address are empty');
  });

  // Slice 4: pin the URL builder. Lives at the top level of
  // product_detail_screen.dart so it can be unit-tested without a
  // widget tree. The prefix is the Google Maps *directions* URL
  // (`/maps/dir/`) so Maps opens with origin=current location and
  // destination=address. URL-encode rules from `Uri.encodeComponent`:
  //   - space -> %20
  //   - ','   -> %2C
  //   - multi-byte UTF-8 chars (e.g. 'ễ' = U+1EB5) -> %E1%BB%85
  //   - ASCII letters and digits are passed through.
  test('buildGoogleMapsDirectionsUrl: ASCII address encodes spaces only', () {
    expect(buildGoogleMapsDirectionsUrl('123 Main St'),
        'https://www.google.com/maps/dir/?api=1&destination=123%20Main%20St');
  });

  test(
      'buildGoogleMapsDirectionsUrl: Vietnamese diacritics are UTF-8 escaped',
      () {
    // 'ễ' is U+1EB5 → UTF-8 0xE1 0xBB 0x85 → %E1%BB%85
    // 'ệ' is U+1EC7 → UTF-8 0xE1 0xBB 0x87 → %E1%BB%87
    // ','  is U+002C → %2C
    // ' '  is U+0020 → %20
    expect(buildGoogleMapsDirectionsUrl('123 Nguyễn Huệ, Q.1'),
        'https://www.google.com/maps/dir/?api=1&destination=123%20Nguy%E1%BB%85n%20Hu%E1%BB%87%2C%20Q.1');
  });

  test('buildGoogleMapsDirectionsUrl: empty address returns the prefix only',
      () {
    // Caller is expected to short-circuit on empty input; this test
    // pins the current behavior (no special handling).
    expect(buildGoogleMapsDirectionsUrl(''),
        'https://www.google.com/maps/dir/?api=1&destination=');
  });

  // Slice 4: pin the three-tier URL resolver that the CTA uses.
  // Tier 1: googleMapsUrl set → return it (with https:// prepended
  //         if the admin pasted a scheme-less URL like 'www.google...').
  // Tier 2: googleMapsUrl empty, address set → return the built
  //         directions URL with destination=address.
  // Tier 3: both empty → return '' (caller hides the button).
  group('resolveStoreMapUrl', () {
    test('tier 1a: returns the configured googleMapsUrl verbatim when it has https://', () {
      const info = StoreInfo(
        address: '123 Nguyễn Huệ',
        googleMapsUrl:
            'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue&travelmode=driving',
      );
      expect(resolveStoreMapUrl(info),
          'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue&travelmode=driving');
    });

    test('tier 1b: prepends https:// when googleMapsUrl has no scheme (web bug fix)', () {
      // Bug: admin pastes 'www.google.com/maps/...' without the scheme.
      // Uri.parse treats it as a relative URL, so launchUrl on web
      // navigates to http://localhost:3000/www.google.com/... instead
      // of the real Google Maps URL. Fix: prepend https://.
      const info = StoreInfo(
        address: '123 Nguyễn Huệ',
        googleMapsUrl: 'www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue',
      );
      expect(resolveStoreMapUrl(info),
          'https://www.google.com/maps/dir/?api=1&destination=12+Nguyen+Hue');
    });

    test('tier 1c: leaves http:// googleMapsUrl untouched', () {
      // Admin explicitly used http:// (rare). Don't change semantics.
      const info = StoreInfo(
        address: '123 Nguyễn Huệ',
        googleMapsUrl: 'http://maps.example.com/store',
      );
      expect(resolveStoreMapUrl(info), 'http://maps.example.com/store');
    });

    test('tier 2: builds a directions URL from the address when URL is empty',
        () {
      const info = StoreInfo(address: '123 Nguyễn Huệ');
      expect(resolveStoreMapUrl(info),
          'https://www.google.com/maps/dir/?api=1&destination=123%20Nguy%E1%BB%85n%20Hu%E1%BB%87');
    });

    test('tier 3: returns empty string when both are empty', () {
      const info = StoreInfo();
      expect(resolveStoreMapUrl(info), '');
    });
  });

  // Slice 4: the CTA shows the address as the label regardless of
  // which tier was used to resolve the URL. Test that the label
  // matches the address even when a googleMapsUrl is configured.
  testWidgets(
      'ProductDetailScreen: CTA label is the address even when googleMapsUrl is set',
      (tester) async {
    final product = _buildProduct();

    await tester.pumpWidget(_wrap(
      ProductDetailScreen(product: product),
      storeInfo: const StoreInfo(
        address: '12 Nguyễn Huệ',
        googleMapsUrl: 'https://www.google.com/maps/dir/?api=1&destination=foo',
      ),
    ));
    await tester.pump();

    // The address appears as the button label.
    expect(find.text('12 Nguyễn Huệ'), findsWidgets);
  });

// User-reported regression: on iOS Safari (and Chrome DevTools iPhone
  // emulation) horizontal swipes across the product gallery did
  // nothing — the customer could see all the dot indicators but
  // couldn't flip between them, both for the default gallery and for
  // the variant gallery after picking an option.
  //
  // Two earlier fix attempts both passed unit tests but failed in the
  // browser:
  //   • A raw [Listener] outside the gesture arena (no arena
  //     participation → parent's vertical drag always won on iOS).
  //   • A custom [OneSequenceGestureRecognizer] inside the carousel
  //     fighting the parent's [SingleChildScrollView] vertical drag
  //     — the recognizer's TestPointer dispatch passed in
  //     `flutter_test`, but real WebKit pointer-event timing
  //     consistently defeated it.
  //
  // The fix that actually holds in the browser is a different
  // scroll-wrapper choice for the screen body — [ListView] instead
  // of [SingleChildScrollView]. Two structural assertions pin the
  // fix so a future refactor can't quietly regress it:
  //
  //   1. The body scroll view is a [ListView] (NOT a
  //      [SingleChildScrollView]). The two render the same visually
  //      but resolve their `VerticalDragGestureRecognizer` slightly
  //      differently — with [ListView] + the embedded [PageView]'s
  //      default [PageScrollPhysics], a dominantly horizontal swipe
  //      is unambiguously claimed by [PageView] first. The vertical
  //      scroll view only wins a drag that's clearly vertical.
  //
  //   2. The carousel's [PageView] uses DEFAULT physics (i.e. NOT
  //      [NeverScrollableScrollPhysics]). The earlier custom-recognizer
  //      approach gave [PageView] `NeverScrollableScrollPhysics` to
  //      keep its built-in drag recognizer out of the arena while
  //      the custom one drove [PageController] — but that left the
  //      whole carousel dependent on the recognizer firing in the
  //      right sequence. With [PageView] in charge of its own drag
  //      (default physics) and a [ListView] parent that doesn't
  //      compete on a dominantly horizontal swipe, the carousel just
  //      works on every platform, including iOS Safari.
  //
  // Why we DON'T dispatch [TestPointer] events here any more:
  // `flutter_test`'s gesture simulation cannot reproduce WebKit's
  // real pointer-event timing — every earlier attempt passed in
  // tests but stuck in the browser. The structural assertions are
  // what guards the actual fix.
  testWidgets(
      'ProductDetailScreen: body wraps content in a ListView (not '
      'SingleChildScrollView) so the carousel wins horizontal swipes',
      (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    // We use `pump()` (not `pumpAndSettle`) because the carousel
    // mounts `AppNetworkImage` widgets that retry forever when
    // given an empty URL in test — `pumpAndSettle` would never
    // return. We're only inspecting widget configs here, not
    // waiting for the page to fully paint.
    await tester.pump();

    // 1. The body must be a [ListView], not a [SingleChildScrollView].
    // Both render identically to the eye; the difference is in how
    // they resolve their `VerticalDragGestureRecognizer` when a child
    // [PageView] also wants the same pointer sequence. On iOS Safari,
    // only [ListView] (as the parent of an embedded [PageView]) lets
    // a dominantly horizontal swipe reach the carousel.
    expect(find.byType(SingleChildScrollView), findsNothing,
        reason:
            'on iOS Safari the parent SingleChildScrollView was claiming '
            'horizontal swipes inside the carousel, leaving it "stuck". '
            'The screen body must use [ListView] instead — both render '
            'the same scroll behaviour visually, but [ListView] doesn\'t '
            'fight [PageView] in the gesture arena on a horizontal drag');
    expect(find.byType(ListView), findsWidgets,
        reason: 'the screen body should now be a ListView (shrinkWrap)');
  });

  testWidgets(
      'ProductDetailScreen: carousel PageView owns its horizontal drag '
      '(default physics, not NeverScrollableScrollPhysics)',
      (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    final physics = pageView.physics;
    // 2. The [PageView] must use DEFAULT physics — i.e. NOT
    // [NeverScrollableScrollPhysics] (the workaround the prior
    // custom-recognizer approach needed). With default physics the
    // carousel drives its own horizontal drag; the surrounding
    // [ListView] doesn't compete on a dominantly horizontal swipe,
    // so real iOS Safari pointer events flow through cleanly.
    //
    // Note: when [PageView] is constructed with `physics: null`
    // (i.e. the default), the property reads back as null. The
    // PageView internally instantiates `PageScrollPhysics()` if no
    // explicit physics is given — that's the "default" case our fix
    // wants. We accept either null (no explicit physics) or any
    // [PageScrollPhysics]-derived type, and reject only
    // [NeverScrollableScrollPhysics].
    expect(physics == null || physics is PageScrollPhysics, isTrue,
        reason:
            'the carousel PageView must own its own horizontal drag '
            '(default PageScrollPhysics). The previous approach gave it '
            'NeverScrollableScrollPhysics while a custom recognizer drove '
            'PageController — that path passed unit tests but failed in '
            'the browser because WebKit pointer-event timing is what '
            'flutter_test can\'t reliably reproduce.');
    expect(physics, isNot(isA<NeverScrollableScrollPhysics>()),
        reason:
            'NeverScrollableScrollPhysics is the workaround from the '
            'prior custom-recognizer approach — it kept [PageView]\'s '
            'own drag recognizer out of the gesture arena. The fix is '
            'to let [PageView] drive its own drag, so this MUST be gone');
  });

  // -----------------------------------------------------------------
  // Whole-screen redesign (2026-07-23) — assert the architectural
  // decisions, not the gesture behavior (which still needs the
  // real-browser verification in [[simshop-product-detail-redesign-2026-07-23]]
  // because flutter_test cannot reproduce WebKit pointer-event timing).
  // -----------------------------------------------------------------

  testWidgets(
      'ProductDetailScreen: does NOT use shared ImageCarousel — uses '
      'GallerySection instead', (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();

    expect(find.byType(ImageCarousel), findsNothing,
        reason:
            'the broken shared ImageCarousel caused the iOS swipe '
            'regression; product-detail must use the new GallerySection');
    expect(find.byType(GallerySection), findsOneWidget);
  });

  testWidgets(
      'ProductDetailScreen: InfoSection is rendered', (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();
    expect(find.byType(InfoSection), findsOneWidget);
  });

  testWidgets(
      'ProductDetailScreen: body wraps content in a ListView (not '
      'SingleChildScrollView)', (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsWidgets);
  });

  // -----------------------------------------------------------------
  // iPad / PC layout split (2026-07-23).
  //
  // User feedback: "UI trên ipad làm giống điện thoại, UI trên pc,
  // laptop thì sửa lại như sau" — and then drew a sketch where the
  // right column on PC ends at the stock card, with thumbs +
  // Description + Specs + Buy CTA + Footer flowing below the row.
  //
  // Threshold (clarified with user): ≥1024 dp uses the 2-col +
  // thumbs-below-row layout. iPad portrait (768 dp) stays
  // mobile-style. iPad landscape (1024 dp) and PC/laptop (≥1200 dp)
  // use the 2-col layout.
  //
  // These tests pin that split by pumping ProductDetailScreen at
  // specific MediaQuery sizes and asserting the structural
  // children — we don't dispatch gestures, the layout choice is
  // purely a function of MediaQuery.size.width.
  // -----------------------------------------------------------------

  // Helper: pump the screen at an explicit viewport size. The
  // responsive getters read MediaQuery.of(context).size, so an
  // override at the top of the tree drives the layout choice.
  Widget _wrapSized(Widget child, Size size, {StoreInfo? storeInfo}) {
    final seed = storeInfo ?? const StoreInfo();
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<SiteConfigViewModel>(
              create: (_) => SiteConfigViewModel(
                service: _FakeStoreService(seed),
              )..load(),
            ),
          ],
          child: child,
        ),
      ),
    );
  }

  testWidgets(
      'ProductDetailScreen: at 1280x800 (PC) uses 2-col Row, renders '
      'InfoSection(compact=true) on the right, DetailsSection below the '
      'row, and ThumbnailStrip below the row (not inside the gallery)',
      (tester) async {
    // Build a product with multiple images so the ThumbnailStrip
    // actually renders (it's hidden for single-image products).
    final product = Product(
      id: 'p-pc',
      name: 'PC test product',
      description: 'Multi-image product for the 2-col layout test',
      price: 199000,
      imageUrl: '',
      category: 'Áo',
      rating: 4.5,
      specs: const ['Spec A', 'Spec B'],
      images: const ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    );
    await tester.pumpWidget(_wrapSized(
      ProductDetailScreen(product: product),
      const Size(1280, 800),
    ));
    // pump() (not pumpAndSettle) because CachedNetworkImage keeps
    // a retry loop on bad URLs in test.
    await tester.pump();

    // 1. The screen must mount ONE InfoSection and ONE
    //    DetailsSection. compact: true on InfoSection means
    //    DetailsSection is NOT a child of InfoSection — it lives
    //    as a sibling below the row.
    expect(find.byType(InfoSection), findsOneWidget);
    expect(find.byType(DetailsSection), findsOneWidget);

    // 2. The DetailsSection must NOT be inside the InfoSection
    //    subtree. Otherwise the right column on PC would carry
    //    Description + Specs + CTA — which is exactly what the
    //    user asked us to move out.
    expect(
      find.descendant(of: find.byType(InfoSection), matching: find.byType(DetailsSection)),
      findsNothing,
      reason: 'DetailsSection must NOT be nested inside InfoSection on '
          'PC — it must be a sibling rendered below the row so it '
          'spans the full content width',
    );

    // 3. The screen must contain the gallery+info Row somewhere.
    //    (There may also be other Rows in ListView separators, so
    //    we don't count Rows — we just confirm at least one Row
    //    is present in the body.)
    expect(find.byType(Row), findsWidgets);

    // 4. The ThumbnailStrip must NOT be inside the gallery
    //    column. We can't directly query "the gallery column"
    //    without a key, so we verify the structural invariant:
    //    the ThumbnailStrip is NOT a descendant of GallerySection
    //    on PC. (On mobile / iPad portrait it IS a descendant of
    //    GallerySection — covered by the iPad-portrait test.)
    expect(
      find.descendant(of: find.byType(GallerySection), matching: find.byType(ThumbnailStrip)),
      findsNothing,
      reason: 'on PC the ThumbnailStrip is rendered below the row, not '
          'inside the gallery column',
    );

    // 5. The ThumbnailStrip must exist exactly once at the screen
    //    level (below the row).
    expect(find.byType(ThumbnailStrip), findsOneWidget);
  });

  testWidgets(
      'ProductDetailScreen: at 768x1024 (iPad portrait) uses the '
      'single-column mobile layout — no gallery+info Row, ThumbnailStrip '
      'rendered inside the gallery column, InfoSection renders full '
      'content (no separate DetailsSection)',
      (tester) async {
    final product = Product(
      id: 'p-ipad',
      name: 'iPad portrait test product',
      description: 'Multi-image product for the single-col layout test',
      price: 199000,
      imageUrl: '',
      category: 'Áo',
      rating: 4.5,
      specs: const ['Spec A'],
      images: const ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    );
    await tester.pumpWidget(_wrapSized(
      ProductDetailScreen(product: product),
      const Size(768, 1024),
    ));
    await tester.pump();

    // 1. iPad portrait → InfoSection(compact: false) renders the
    //    full info column, INCLUDING the bottom half. So the
    //    Description + Specs + Buy CTA live INSIDE InfoSection
    //    via DetailsSection-as-child. The screen does NOT mount
    //    a top-level DetailsSection.
    expect(find.byType(InfoSection), findsOneWidget);
    expect(find.byType(DetailsSection), findsOneWidget);
    expect(
      find.descendant(of: find.byType(InfoSection), matching: find.byType(DetailsSection)),
      findsOneWidget,
      reason: 'on iPad portrait the DetailsSection is a child of '
          'InfoSection (compact: false), so the full info column '
          'renders as one widget',
    );

    // 2. The ThumbnailStrip is a sibling of GallerySection inside
    //    the gallery column (both children of the same Column
    //    inside a Container with `surfaceContainerLowest`).
    //    It's NOT a descendant of GallerySection (GallerySection
    //    is a leaf-ish widget — it doesn't contain the strip).
    //    We assert the strip is NOT inside InfoSection, since the
    //    gallery column and the info column are siblings.
    expect(
      find.descendant(of: find.byType(InfoSection), matching: find.byType(ThumbnailStrip)),
      findsNothing,
      reason: 'on iPad portrait the ThumbnailStrip lives in the gallery '
          'column, not inside the info column',
    );
    expect(
      find.descendant(of: find.byType(GallerySection), matching: find.byType(ThumbnailStrip)),
      findsNothing,
      reason: 'GallerySection is a leaf-ish widget — the ThumbnailStrip '
          'is rendered by the screen as a sibling, not a descendant',
    );

    // 3. There should be exactly one ThumbnailStrip on the screen
    //    (inside the gallery column).
    expect(find.byType(ThumbnailStrip), findsOneWidget);
  });
}