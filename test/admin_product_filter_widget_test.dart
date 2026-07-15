import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:simshop/models/category.dart';
import 'package:simshop/models/event.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
import 'package:simshop/services/i_product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/views/admin/admin_product/admin_product_screen.dart';

/// In-memory [IProductService] backing the admin filter + stock-stepper
/// tests. Mirrors the contract `RealProductService` exposes so the
/// VM's interface-based dispatch (we removed the `as RealProductService`
/// casts) finds the right method.
class _FilterProductService implements IProductService {
  _FilterProductService(this._products);

  final List<Product> _products;

  /// Recorded updateProduct calls. Test asserts on payload + count
  /// to confirm the VM is round-tripping the right shape (the
  /// backend has no stock-only endpoint — full PUT is the only way
  /// to change stock).
  /// Recorded updateStock calls. The widget test asserts on payload
  /// + count to confirm the VM hits the dedicated stock-only
  /// endpoint instead of round-tripping the whole product.
  final List<({String id, int? stock})> stockUpdates = [];

  @override
  Future<List<Product>> getAllProducts() async => List.of(_products);

  @override
  Future<List<Product>> getProductsByCategory(String category) async =>
      _products.where((p) => p.category == category).toList();

  @override
  Future<Product> getProductById(String id) async =>
      _products.firstWhere((p) => p.id == id);

  @override
  Future<List<Product>> searchProducts(String query) async => const [];

  @override
  Future<void> deleteProduct(String id) async {
    _products.removeWhere((p) => p.id == id);
  }

  @override
  Future<Product> createProduct(
    Product product, {
    List<String>? removedImageUrls,
  }) =>
      Future.value(product);

  @override
  Future<Product> updateProduct(
    String id,
    Product product, {
    List<String>? removedImageUrls,
  }) async {
    // The stock-stepper flow no longer goes through updateProduct
    // (it uses the dedicated stock-only endpoint via updateStock),
    // so this stub just mirrors the row locally for any caller
    // that still exercises the full PUT path (e.g. the edit dialog).
    final idx = _products.indexWhere((p) => p.id == id);
    if (idx >= 0) _products[idx] = product;
    return product;
  }

  @override
  Future<Product> updateStock(String id, int? stock) async {
    stockUpdates.add((id: id, stock: stock));
    final idx = _products.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      _products[idx] = _products[idx].copyWith(stock: stock);
    }
    return _products.firstWhere((p) => p.id == id);
  }

  @override
  Future<void> deleteCategory(String name) async {}

  @override
  Future<List<String>> getLargeCategories() async => const ['Thời trang'];

  @override
  Future<List<Category>> getCategoriesWithParent() async => [
        Category(name: 'Áo cũ', largeCategory: null),
        Category(name: 'Quần cũ', largeCategory: null),
        Category(name: 'Áo thun', largeCategory: 'Thời trang'),
      ];

  @override
  Future<void> createLargeCategory(String name) async {}

  @override
  Future<void> deleteLargeCategory(String name) async {}

  @override
  Future<void> createCategoryWithParent(
          String name, String largeCategoryName) async {}

  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName, String? productId, int startIndex = 1}) async =>
      null;

  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName, String? productId, int startIndex = 1}) async =>
      const [];
}

Product _product({
  required String id,
  required String name,
  int? stock = 0,
  List<String> categories = const ['Áo thun'],
  String category = 'Áo thun',
  double? price,
  double? originalPrice,
  double? effectivePrice,
  Event? currentEvent,
}) =>
    Product(
      id: id,
      name: name,
      description: '',
      price: price ?? 100,
      originalPrice: originalPrice,
      imageUrl: '',
      category: category,
      categories: categories,
      rating: 0,
      stock: stock,
      specs: const [],
      effectivePrice: effectivePrice,
      currentEvent: currentEvent,
    );

Future<AdminViewModel> _seeded(_FilterProductService svc) async {
  final vm = AdminViewModel(productService: svc);
  await vm.initialize();
  return vm;
}

Widget _harness(AdminViewModel vm) => MaterialApp(
      home: ChangeNotifierProvider<AdminViewModel>.value(
        value: vm,
        child: const Scaffold(body: AdminProductsScreen()),
      ),
    );

void main() {
  group('AdminViewModel filter state', () {
    test('no filter shows every product', () async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
        _product(id: 'b', name: 'Áo thun B', categories: ['Áo cũ']),
        _product(
          id: 'c',
          name: 'Quần cũ C',
          categories: ['Quần cũ'],
          category: 'Quần cũ',
        ),
      ]);
      final vm = await _seeded(svc);
      expect(vm.products, hasLength(3));
    });

    test('selecting a real Large keeps only products under that Large',
        () async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
        // Primary `category` defaults to 'Áo thun' which would
        // match via the legacy-string fallback; explicit empty
        // category exposes the strict AND-by-Large check.
        _product(
            id: 'b',
            name: 'Quần cũ B',
            categories: ['Quần cũ'],
            category: 'Quần cũ'),
      ]);
      final vm = await _seeded(svc);
      vm.selectFilterLarge('Thời trang');
      expect(vm.products.map((p) => p.id), ['a']);
    });

    test('selecting the orphan bucket keeps only orphan-tagged products',
        () async {
      // Mirror the user-facing intent: orphan subs group every
      // product whose `categories` includes an orphan (or whose
      // primary `category` is an orphan name).
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun parented'),
        _product(id: 'b', name: 'Áo cũ orphan', categories: ['Áo cũ']),
        _product(
          id: 'c',
          name: 'Quần cũ orphan',
          categories: ['Quần cũ'],
          category: 'Quần cũ',
        ),
      ]);
      final vm = await _seeded(svc);
      vm.selectFilterLarge(AdminViewModel.orphanBucket);
      expect(vm.products.map((p) => p.id).toSet(), {'b', 'c'});
    });

    test('multi-sub selection AND-filters products', () async {
      // Mirrors the home menu logic: with two real subs selected a
      // product must carry BOTH tags to stay visible.
      final svc = _FilterProductService([
        _product(
            id: 'a',
            name: 'Áo thun cũ',
            categories: ['Áo thun', 'Áo cũ']),
        _product(id: 'b', name: 'Áo thun new', categories: ['Áo thun']),
      ]);
      final vm = await _seeded(svc);
      vm.selectFilterLarge('Thời trang');
      vm.toggleFilterSub('Áo cũ');
      expect(vm.products.map((p) => p.id), ['a'],
          reason: 'AND across subs: only the product carrying both '
              '"Áo thun" + "Áo cũ" should remain');
    });

    test('orphan bucket shows orphan subs in the second row', () async {
      final svc = _FilterProductService([_product(id: 'a', name: 'X')]);
      final vm = await _seeded(svc);
      vm.selectFilterLarge(AdminViewModel.orphanBucket);
      final subs = vm.visibleFilterSubs;
      expect(subs.first, 'Tất cả');
      expect(subs.sublist(1), containsAll(['Áo cũ', 'Quần cũ']));
      expect(subs, hasLength(3));
    });

    test('clearFilter resets every dimension', () async {
      final svc = _FilterProductService([_product(id: 'a', name: 'X')]);
      final vm = await _seeded(svc);
      vm.selectFilterLarge('Thời trang');
      vm.toggleFilterSub('Áo thun');
      vm.clearFilter();
      expect(vm.filterLarge, isNull);
      expect(vm.filterSelectedSubs, isEmpty);
    });
  });

  group('AdminProductFilter widget', () {
    testWidgets('no orphan bucket pill when the service reports no orphan subs',
        (tester) async {
      // Custom seed: a service whose getCategoriesWithParent()
      // returns ONLY parented subs. The "Chưa phân loại" pill must
      // stay hidden because there is no orphan bucket to filter on.
      final svc = _ParentedOnlyProductService();
      final vm = AdminViewModel(productService: svc);
      await vm.initialize();
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      expect(find.text('Chưa phân loại'), findsNothing,
          reason: 'orphan bucket pill must not render when the hierarchy '
              'has no orphan subs');
    });

    testWidgets(
        'orphan bucket pill renders once any orphan sub exists',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
        _product(id: 'b', name: 'Orphan row', categories: ['Áo cũ']),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      expect(find.text('Chưa phân loại'), findsOneWidget);
    });

    testWidgets('tapping the orphan pill reveals orphan sub chips',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
        _product(id: 'b', name: 'Orphan row', categories: ['Áo cũ']),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      // The orphan bucket is selected → orphan sub chips render.
      await tester.tap(find.text('Chưa phân loại'));
      await tester.pump();
      expect(find.text('Áo cũ'), findsOneWidget,
          reason: 'orphan sub chip must render once the bucket is selected');
      expect(find.text('Quần cũ'), findsOneWidget,
          reason: 'every orphan sub is surfaced, not just one');
      // Real Larges' subs must NOT show under the orphan bucket.
      expect(find.text('Áo thun'), findsNothing,
          reason: 'parented sub must not leak into the orphan row');
    });

    testWidgets('clearing filter via the "Xoá lọc" button restores all rows',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
        _product(id: 'b', name: 'Orphan row', categories: ['Áo cũ']),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      await tester.tap(find.text('Chưa phân loại'));
      await tester.pump();
      expect(find.text('Orphan row'), findsOneWidget,
          reason: 'orphan-tagged product is visible under the bucket');
      expect(find.text('Áo thun A'), findsNothing,
          reason: 'parented product should be filtered out');
      // Clear filter and confirm both products are back.
      await tester.tap(find.text('Xoá lọc'));
      await tester.pump();
      expect(find.text('Áo thun A'), findsOneWidget);
      expect(find.text('Orphan row'), findsOneWidget);
    });
  });

  group('ProductListTile stock stepper', () {
    testWidgets('+/- buttons bump stock via AdminViewModel.quickAdjustStock',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun', stock: 5),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      // Initial stock label.
      expect(find.text('5'), findsOneWidget);

      // Tap the stepper's "+" button — keyed by tooltip to avoid
      // colliding with the "Thêm sản phẩm" header button (which
      // also uses Icons.add but inside a FilledButton, not an
      // IconButton).
      await tester.tap(find.byTooltip('Tăng 1'));
      await tester.pump();
      await tester.pump();
      expect(vm.products.first.stock, 6);
      // The stock-stepper flow MUST hit the dedicated stock-only
      // endpoint — a full PUT would risk clobbering concurrent
      // edits to other fields, which is the whole reason this
      // endpoint exists.
      expect(svc.stockUpdates, hasLength(1));
      expect(svc.stockUpdates.first.id, 'a');
      expect(svc.stockUpdates.first.stock, 6);

      // Tap the "−" button.
      await tester.tap(find.byTooltip('Giảm 1'));
      await tester.pump();
      await tester.pump();
      expect(vm.products.first.stock, 5);
      expect(svc.stockUpdates, hasLength(2));
      expect(svc.stockUpdates.last.stock, 5);
    });

    testWidgets('negative button is disabled when stock is already 0',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun', stock: 0),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      final minusButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(minusButton.onPressed, isNull,
          reason: 'minus button must be disabled at floor to prevent '
              'queueing a useless backend round-trip');
    });

    testWidgets('null stock renders as "?" so admins notice missing data',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun', stock: null),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      expect(find.text('?'), findsOneWidget,
          reason: 'missing stock must render as ?, not 0 — otherwise admins '
              'mistakenly treat "no data" as "out of stock"');
    });

    testWidgets('stale admin session 401 surfaces the redirect signal',
        (tester) async {
      // The stock stepper must NOT swallow AdminSessionExpiredException;
      // it must flip vm.adminSessionExpired so the admin shell routes
      // the user back to the auth gate. Without this branch the
      // user gets stuck with a stale token and no path to recover.
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun', stock: 3),
      ]);
      final svc2 = _StockThrowingService(svc);
      final vm = AdminViewModel(productService: svc2);
      await vm.initialize();
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      expect(vm.adminSessionExpired, isFalse);
      await tester.tap(find.byTooltip('Tăng 1'));
      await tester.pump();
      await tester.pump();
      expect(vm.adminSessionExpired, isTrue,
          reason: '401 from the stock PATCH must surface as a session-expired '
              'flag so the shell pops back to AdminAuthGate');
      expect(svc.stockUpdates, hasLength(1),
          reason: 'one optimistic PATCH happened before the failure');
      expect(svc.stockUpdates.first.stock, 4,
          reason: 'the +1 step must send the new stock value (4) so the '
              'server-side write would have flipped 3→4 had it not 401-ed');
      // After the failure, the local row should revert to the
      // pre-tap stock (3), not the optimistic 4.
      expect(vm.products.first.stock, 3,
          reason: 'optimistic local update must revert on failure so the '
              'row stays consistent with the server');
    });
  });

  group('ProductListTile sale pill', () {
    // The pill slot in each row's subtitle replaced the legacy
    // "Tồn kho: N" text. The stock stepper still owns the stock
    // value; the pill now communicates *promotion state* instead.
    // Three meaningful flavours:
    //   • Active event   → tag = event.formatDiscount(),
    //                      detail = event name + effective price.
    //   • Manual discount (legacy `originalPrice > price`)
    //                    → tag = "-N%", detail = effective price.
    //   • No discount    → pill is absent (the row just shows base
    //                      price with no extra chrome).
    testWidgets('active event renders -N% tag + event name', (tester) async {
      final ev = Event(
        id: 'e1',
        name: 'Black Friday',
        endTime: DateTime.now().add(const Duration(days: 1)),
        discountType: DiscountType.percent,
        discountValue: 20,
      );
      final svc = _FilterProductService([
        _product(
          id: 'a',
          name: 'Áo thun sale',
          price: 200000,
          effectivePrice: 160000,
          currentEvent: ev,
        ),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      // The tag uses formatDiscount() — "-20%" for percent events.
      expect(find.text('-20%'), findsOneWidget,
          reason: 'event pill must surface the event\'s discount tag');
      // Detail row carries the event name + the post-discount price.
      // The detail is rendered with whitespace separators, so look
      // for the substrings instead of a single exact string.
      expect(
        find.textContaining('Black Friday'),
        findsOneWidget,
        reason: 'event name must appear in the pill so admins can '
            'cross-reference with the Events tab',
      );
      expect(
        find.textContaining('160,000'),
        findsOneWidget,
        reason: 'effective price must be visible alongside the event '
            'name — that\'s the price the customer actually pays '
            '(formatted via formatCurrency → "160,000đ")',
      );
    });

    testWidgets('manual discount (legacy originalPrice) renders -N% tag',
        (tester) async {
      final svc = _FilterProductService([
        _product(
          id: 'a',
          name: 'Áo thun cũ',
          price: 80000,
          originalPrice: 100000, // 20% off, no active event
        ),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      expect(find.text('-20%'), findsOneWidget,
          reason: 'legacy manual discounts must still show a -N% tag so '
              'admins can scan for on-sale rows');
      // The original "Tồn kho" text MUST be gone — stock info is
      // owned by the stepper now.
      expect(find.textContaining('Tồn kho'), findsNothing);
    });

    testWidgets('no discount: pill is absent, only base price shows',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun thường', price: 100000),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      // No tag text patterns from either pill kind.
      expect(find.text('-20%'), findsNothing);
      expect(find.text('-0%'), findsNothing);
      // And — crucially — the legacy "Tồn kho: N" text must NOT
      // appear. Stock info now lives in the stepper only.
      expect(find.textContaining('Tồn kho'), findsNothing,
          reason: 'subtitle must no longer carry stock info; that\'s '
              'owned by the stepper');
    });
  });

  group('AdminProductFilter clear-button placement', () {
    // Regression for the layout change: "Xoá lọc" used to live on
    // its own third row beneath the sub-row. The new layout folds
    // it into the Large pill row at the RIGHTMOST position so it
    // sits to the right of every pill — including "Chưa phân loại"
    // — and the band stays one logical control. The orphan bucket
    // stays anchored at the leftmost position.
    testWidgets(
        'clear button is absent until a filter is active (no dead chrome)',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      expect(find.text('Xoá lọc'), findsNothing,
          reason: 'no active filter → no clear button to render');
    });

    testWidgets('clear button sits to the RIGHT of "Chưa phân loại"',
        (tester) async {
      final svc = _FilterProductService([
        _product(id: 'a', name: 'Áo thun A'),
        _product(id: 'b', name: 'Orphan row', categories: ['Áo cũ']),
      ]);
      final vm = await _seeded(svc);
      await tester.pumpWidget(_harness(vm));
      await tester.pump();
      // Activate the orphan bucket → filter becomes active → clear
      // button now renders.
      await tester.tap(find.text('Chưa phân loại'));
      await tester.pump();
      expect(find.text('Xoá lọc'), findsOneWidget,
          reason: 'an active filter must surface the clear button');
      // The two siblings share a horizontal band; the strongest
      // assertion is that on the rendered axis the button's left
      // edge is AFTER the pill's left edge. We compare centres
      // because Flutter does not expose "x-of-first-pixel" for a
      // widget — centre.x is monotonically increasing across the
      // scroll axis and proves the trailing-button placement.
      final buttonCentre = tester.getCenter(find.text('Xoá lọc'));
      final pillCentre = tester.getCenter(find.text('Chưa phân loại'));
      expect(buttonCentre.dx, greaterThan(pillCentre.dx),
          reason: 'Xoá lọc must render to the RIGHT of "Chưa phân loại" '
              'on the same horizontal axis (centre.dx must be larger)');
    });
  });
}

/// Wraps an inner [IProductService] and throws
/// [AdminSessionExpiredException] from [updateStock]. Used by the
/// stale-session regression test above.
class _StockThrowingService implements IProductService {
  _StockThrowingService(this._inner);
  final _FilterProductService _inner;

  @override
  Future<Product> updateProduct(
    String id,
    Product product, {
    List<String>? removedImageUrls,
  }) =>
      _inner.updateProduct(id, product);

  @override
  Future<Product> updateStock(String id, int? stock) async {
    _inner.stockUpdates.add((id: id, stock: stock));
    throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.');
  }

  // Pass-throughs for everything the VM reads.
  @override
  Future<List<Product>> getAllProducts() => _inner.getAllProducts();
  @override
  Future<List<Product>> getProductsByCategory(String category) =>
      _inner.getProductsByCategory(category);
  @override
  Future<Product> getProductById(String id) => _inner.getProductById(id);
  @override
  Future<List<Product>> searchProducts(String query) =>
      _inner.searchProducts(query);
  @override
  Future<void> deleteProduct(String id) => _inner.deleteProduct(id);
  @override
  Future<Product> createProduct(Product product,
          {List<String>? removedImageUrls}) =>
      _inner.createProduct(product);
  @override
  Future<void> deleteCategory(String name) => _inner.deleteCategory(name);
  @override
  Future<List<String>> getLargeCategories() => _inner.getLargeCategories();
  @override
  Future<List<Category>> getCategoriesWithParent() =>
      _inner.getCategoriesWithParent();
  @override
  Future<void> createLargeCategory(String name) =>
      _inner.createLargeCategory(name);
  @override
  Future<void> deleteLargeCategory(String name) =>
      _inner.deleteLargeCategory(name);
  @override
  Future<void> createCategoryWithParent(String name, String largeCategoryName) =>
      _inner.createCategoryWithParent(name, largeCategoryName);
  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName, String? productId, int startIndex = 1}) =>
      _inner.uploadImage(file,
          productName: productName, productId: productId, startIndex: startIndex);
  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName, String? productId, int startIndex = 1}) =>
      _inner.uploadImages(files,
          productName: productName,
          productId: productId,
          startIndex: startIndex);
}

/// Service stub whose `getCategoriesWithParent()` returns ONLY
/// parented subs (no orphans). Used by the regression test that
/// verifies the "Chưa phân loại" pill is suppressed when there are
/// no orphan subs to filter on.
class _ParentedOnlyProductService implements IProductService {
  @override
  Future<List<Product>> getAllProducts() async => const [];

  @override
  Future<List<Product>> getProductsByCategory(String category) async =>
      const [];

  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError();

  @override
  Future<List<Product>> searchProducts(String query) async => const [];

  @override
  Future<void> deleteProduct(String id) async {}

  @override
  Future<Product> createProduct(Product product,
          {List<String>? removedImageUrls}) async =>
      product;

  @override
  Future<Product> updateProduct(String id, Product product,
          {List<String>? removedImageUrls}) async =>
      product;

  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteCategory(String name) async {}

  @override
  Future<List<String>> getLargeCategories() async => const ['Thời trang'];

  @override
  Future<List<Category>> getCategoriesWithParent() async => [
        Category(name: 'Áo thun', largeCategory: 'Thời trang'),
      ];

  @override
  Future<void> createLargeCategory(String name) async {}

  @override
  Future<void> deleteLargeCategory(String name) async {}

  @override
  Future<void> createCategoryWithParent(
          String name, String largeCategoryName) async {}

  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName, String? productId, int startIndex = 1}) async =>
      null;

  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName, String? productId, int startIndex = 1}) async =>
      const [];
}