import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/store_service.dart';
import 'package:simshop/viewmodels/site_config_viewmodel.dart';
import 'package:simshop/views/product_detail_screen.dart';

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    // The address appears as the button label.
    expect(find.text('12 Nguyễn Huệ'), findsWidgets);
  });

// User-reported regression: on mobile (Android / iOS) horizontal
  // swipes across the product gallery did nothing — the customer
  // could see all the dot indicators but couldn't flip between
  // them, both for the default gallery and for the variant
  // gallery after picking an option.
  //
  // Three pieces, all pinned here:
  //
  // 1. The vertical scroll view hosting the carousel must use
  //    `ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics())`,
  //    otherwise the parent claims every drag when its content is
  //    short enough to sit at the top of its scroll bounds, leaving
  //    the [PageView] no surface to detect a horizontal swipe.
  //    The default `ClampingScrollPhysics()` (no parent) is what
  //    caused the original "stuck carousel" symptom.
  //
  // 2. The [ImageCarousel] wraps its [PageView] in a
  //    [GestureDetector] that owns horizontal drags manually (calls
  //    `_controller.jumpTo` / `animateToPage` directly) and gives
  //    the [PageView] [NeverScrollableScrollPhysics] so its own
  //    drag detector stays out of the gesture arena entirely.
  //    This is the definitive fix: it bypasses the arena between
  //    the carousel and its parent scroll view, so the carousel
  //    always wins the horizontal swipe on mobile.
  //
  // 3. As a residual defense, the [PageView] must still NOT use
  //    [PageScrollPhysics] — that variant competes with the parent
  //    vertical drag and mis-classifies horizontal swipes as
  //    vertical ones, which is exactly the symptom we're fixing.
  testWidgets(
      'ProductDetailScreen: vertical scroll uses AlwaysScrollable parent so nested carousel keeps its swipes',
      (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    // We use `pump()` (not `pumpAndSettle`) because the carousel
    // mounts `AppNetworkImage` widgets that retry forever when
    // given an empty URL in test — `pumpAndSettle` would never
    // return. We're only inspecting widget configs here, not
    // waiting for the page to fully paint.
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    final physics = scrollView.physics;
    expect(physics, isNotNull,
        reason:
            'a non-null physics is required so the carousel can claim '
            'horizontal drags instead of the parent swallowing them');
    expect(physics, isA<ClampingScrollPhysics>(),
        reason:
            'the parent should still clamp (so the page does not '
            'overscroll past the bottom)');
    expect(physics!.parent, isA<AlwaysScrollableScrollPhysics>(),
        reason:
            'the clamping parent MUST be wrapped in '
            'AlwaysScrollableScrollPhysics — without it, the vertical '
            'scroll view eats the first horizontal swipe when content '
            'fits the viewport, leaving the carousel "stuck"');
  });

  testWidgets(
      'ProductDetailScreen: carousel PageView uses NeverScrollableScrollPhysics so the surrounding GestureDetector owns the drag',
      (tester) async {
    final product = _buildProduct();
    await tester.pumpWidget(_wrap(ProductDetailScreen(product: product)));
    await tester.pump();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    final physics = pageView.physics;
    // The carousel now drives its [PageController] from a
    // surrounding [GestureDetector] (`onHorizontalDragUpdate` +
    // `onHorizontalDragEnd`) so it can claim horizontal drags
    // even when the parent vertical [SingleChildScrollView] is
    // sitting at its scroll bounds. The [PageView] itself is
    // given [NeverScrollableScrollPhysics] so its own horizontal
    // drag detector stays out of the gesture arena entirely —
    // if we left any other physics in place here, both the
    // [GestureDetector] and the [PageView] would race for the
    // same drag, and on mobile the wrong one would still win
    // some of the time.
    expect(physics, isA<NeverScrollableScrollPhysics>(),
        reason:
            'the carousel must not have its own horizontal drag detector — '
            'NeverScrollableScrollPhysics lets the surrounding GestureDetector '
            'be the sole owner of horizontal drags, so they can\'t get '
            'swallowed by the parent SingleChildScrollView');
    expect(physics, isNot(isA<PageScrollPhysics>()),
        reason:
            'PageScrollPhysics would compete with the parent scroll view '
            'on mobile and the carousel would appear stuck again');
  });
}