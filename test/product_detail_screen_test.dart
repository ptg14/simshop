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
import 'package:simshop/widgets/site_info_footer.dart';

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

  // -----------------------------------------------------------------
  // Whole-screen redesign (2026-07-23) — the screen no longer uses the
  // shared [ImageCarousel] at all (the iOS swipe-stuck bug was specific
  // to that widget's [SingleChildScrollView] nesting). It now uses
  // [GallerySection] which has its own PageView — see
  // `test/gallery_section_test.dart` for the gallery-level physics and
  // gesture coverage.
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

    expect(find.byType(SingleChildScrollView), findsNothing,
        reason:
            'SingleChildScrollView is what caused the iOS swipe-stuck '
            'regression on the old shared ImageCarousel; even though the '
            'screen now uses GallerySection, the body must remain a '
            'ListView so the redesign stays consistent with the fix.');
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
  // Refined later (same conversation): "thêm cả điện thoại nằm
  // ngang cũng dùng layout giống máy tính" — phone landscape
  // (~932×430) should ALSO use the 2-col PC layout. Rule is now
  // orientation-based: anything in landscape → 2-col; anything in
  // portrait → single column.
  //
  // These tests pin that split by pumping ProductDetailScreen at
  // specific MediaQuery sizes and asserting the structural
  // children — we don't dispatch gestures, the layout choice is
  // purely a function of MediaQuery.orientation (which Flutter
  // derives from size: width > height → landscape).
  // -----------------------------------------------------------------

  // Helper: pump the screen at an explicit viewport size. The
  // orientation-based rule (see [isProductDetailTwoCol]) reads
  // MediaQuery.orientation, which Flutter derives from size:
// width > height → landscape, else portrait. Tests pass a Size
// whose width-vs-height relationship matches the device class
// they want to simulate (phone landscape = width > height).
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
      'ProductDetailScreen: in landscape (1280x800, PC) uses 2-col Row, '
      'renders InfoSection(compact=true) on the right, DetailsSection '
      'below the row, and ThumbnailStrip below the row (not inside '
      'the gallery)',
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
      'ProductDetailScreen: in portrait (768x1024, iPad portrait) uses '
      'the single-column mobile layout — no gallery+info Row, '
      'ThumbnailStrip rendered inside the gallery column, InfoSection '
      'renders full content (no separate DetailsSection)',
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

  // Phone landscape (~932×430) — the rule added in this turn.
  //
  // User said: "thêm cả điện thoại nằm ngang cũng dùng layout giống
  // máy tính" — phone landscape should use the same 2-col PC layout
  // as iPad landscape / PC. Under the previous width-based rule
  // (≥1024 dp), iPhone landscape fell under the threshold because
  // its width is only ~932 dp. The rule is now orientation-based:
  // landscape → 2-col, portrait → single col.
  //
  // This test pumps the screen at 932×430 (iPhone 14 Pro Max
  // landscape logical pixels) and asserts the PC layout — same
  // shape as the 1280×800 PC test above. The Size(932, 430) is the
  // key: width > height → landscape → 2-col. A test at 430×932
  // (the same physical device in portrait) would assert the
  // opposite — see the portrait test above for that.
  testWidgets(
      'ProductDetailScreen: in phone landscape (932x430) uses the '
      '2-col PC layout — same as iPad landscape / PC, even though '
      'width < 1024 dp',
      (tester) async {
    final product = Product(
      id: 'p-phone-land',
      name: 'Phone landscape test product',
      description: 'Phone landscape layout test',
      price: 199000,
      imageUrl: '',
      category: 'Áo',
      rating: 4.5,
      specs: const ['Spec A'],
      images: const ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
    );
    await tester.pumpWidget(_wrapSized(
      ProductDetailScreen(product: product),
      const Size(932, 430), // width > height → landscape
    ));
    await tester.pump();

    // Same structural assertions as the PC test: InfoSection +
    // DetailsSection are SIBLINGS, the strip lives below the row.
    expect(find.byType(InfoSection), findsOneWidget);
    expect(find.byType(DetailsSection), findsOneWidget);
    expect(
      find.descendant(of: find.byType(InfoSection), matching: find.byType(DetailsSection)),
      findsNothing,
      reason: 'phone landscape must use compact InfoSection — '
          'DetailsSection is a sibling below the row, not a child of '
          'the right column',
    );
    expect(
      find.descendant(of: find.byType(GallerySection), matching: find.byType(ThumbnailStrip)),
      findsNothing,
      reason: 'phone landscape must render the ThumbnailStrip below the '
          'row, not inside the gallery column',
    );
    expect(find.byType(ThumbnailStrip), findsOneWidget);
  });

  // Regression: SiteInfoFooter was rendering full-bleed on PC because
  // it was a sibling of `body` at the ListView level. The
  // banner image inside the footer's Card uses `width:
  // double.infinity`, so without a width constraint the banner
  // stretched edge-to-edge across the viewport instead of staying
  // inside the page's `maxContentWidth` (1200 dp on desktop).
  //
  // Fix: move the SiteInfoFooter into the inner Column (inside the
  // `Container(maxWidth: maxContentWidth)` wrapper), matching the
  // pattern used by the home page.
  //
  // Structural assertion: the footer MUST have at least one
  // Container ancestor with a finite maxWidth constraint. That's
  // the Container wrapping the body — without it the banner
  // stretches full-bleed.
  testWidgets(
      'ProductDetailScreen: SiteInfoFooter is constrained to '
      'maxContentWidth on PC (was full-bleed before the fix)',
      (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrapSized(
      ProductDetailScreen(product: product),
      const Size(1280, 800), // PC landscape
    ));
    await tester.pump();

    // The footer must exist (the screen always renders it).
    expect(find.byType(SiteInfoFooter), findsOneWidget);

    // The footer MUST be a descendant of a Container with a
    // maxWidth constraint (== maxContentWidth, 1200 dp on
    // desktop). Without that ancestor, the banner image inside
    // the footer's Card (width: double.infinity) would stretch
    // edge-to-edge.
    final constrainedAncestors = find.ancestor(
      of: find.byType(SiteInfoFooter),
      matching: find.byType(Container),
    );
    final hasMaxWidthAncestor = constrainedAncestors.evaluate().any((element) {
      final container = element.widget as Container;
      return container.constraints != null &&
          container.constraints!.maxWidth.isFinite &&
          container.constraints!.maxWidth <= 1200.0;
    });
    expect(hasMaxWidthAncestor, isTrue,
        reason: 'SiteInfoFooter must have at least one Container '
            'ancestor with a finite maxWidth ≤ 1200 dp — that\'s how '
            'the banner image gets its width constraint instead of '
            'stretching full-bleed across the viewport');

    // Additionally: the footer's nearest Container ancestor (in
    // the widget tree depth sense — via `firstWidget` of the
    // ancestor finder, which returns the deepest match) must have
    // the constraint. `find.ancestor(...).first` returns the
    // topmost ancestor in tree depth order, which is the
    // OUTERMOST constrained Container = the `body` wrapper. So
    // if THAT one is constrained, the fix is in place.
    final outermost = constrainedAncestors.first.evaluate().single.widget
        as Container;
    expect(outermost.constraints?.maxWidth.isFinite, isTrue,
        reason: 'the outermost constrained Container ancestor is the '
            '`body` wrapper — it must carry the maxContentWidth '
            'constraint so the footer is constrained on PC');
  });
}