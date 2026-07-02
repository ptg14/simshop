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
  Future<StoreInfo> updateStoreInfo(StoreInfo info) async => info;
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
}