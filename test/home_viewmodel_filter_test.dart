import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/home_viewmodel.dart';

/// Minimal in-memory [IProductService] used by the filter tests.
/// Only the three endpoints the view-model's `initialize()` flow
/// touches return meaningful data; everything else throws so a
/// test that accidentally calls the wrong method fails loudly.
class _FakeProductService implements IProductService {
  _FakeProductService({
    this.products = const [],
    this.largeCategories = const [],
    this.subCategories = const [],
  });

  List<Product> products;
  List<String> largeCategories;
  List<Category> subCategories;

  @override
  Future<List<Product>> getAllProducts() async => products;

  @override
  Future<List<String>> getLargeCategories() async => largeCategories;

  @override
  Future<List<Category>> getCategoriesWithParent() async => subCategories;

  // ---- Unused endpoints in these tests. They throw so a test
  // that accidentally calls one fails loud and clear, instead of
  // silently passing because the stub returned an empty list.
  @override
  Future<List<Product>> getProductsByCategory(String category) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<List<Product>> searchProducts(String query, {int? limit}) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<void> deleteCategory(String name) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<void> createLargeCategory(String name) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<void> deleteLargeCategory(String name) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<void> createCategoryWithParent(
          String name, String largeCategoryName) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<Product> createProduct(
    Product product, {
    List<String>? removedImageUrls,
  }) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<Product> updateProduct(
    String id,
    Product product, {
    List<String>? removedImageUrls,
  }) async =>
      throw UnimplementedError('not used in these tests');

  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<void> deleteProduct(String id) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName,
          String? productId,
          int startIndex = 1}) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName,
          String? productId,
          int startIndex = 1}) async =>
      throw UnimplementedError('not used in these tests');
}

/// Build a product whose `category` + `categories` are exactly the
/// provided [categories] list (also used to populate the legacy
/// `category` field, taking the first entry).
Product _product(String id, {required List<String> categories, double price = 0}) {
  return Product(
    id: id,
    name: id,
    description: '',
    price: price,
    imageUrl: '',
    category: categories.isNotEmpty ? categories.first : '',
    categories: categories,
    rating: 0,
    specs: const [],
  );
}

void main() {
  // Common fixture: two Large categories (Electronics, Clothing),
  // each with two sub-categories, and four products spread across
  // them — including one that lives in two subs simultaneously
  // (the motivating use case for the multi-select filter).
  final electronicsSubs = <Category>[
    Category(name: 'Phone', largeCategory: 'Electronics'),
    Category(name: 'Laptop', largeCategory: 'Electronics'),
  ];
  final clothingSubs = <Category>[
    Category(name: 'Shirt', largeCategory: 'Clothing'),
    Category(name: 'Pants', largeCategory: 'Clothing'),
  ];
  final products = <Product>[
    _product('p-phone-1', categories: ['Phone']),
    _product('p-phone-2', categories: ['Phone']),
    _product('p-laptop-1', categories: ['Laptop']),
    // Multi-category product: listed under both Phone and Laptop.
    _product('p-both', categories: ['Phone', 'Laptop']),
    _product('p-shirt-1', categories: ['Shirt']),
    _product('p-pants-1', categories: ['Pants']),
  ];

  _FakeProductService buildService() => _FakeProductService(
        products: products,
        largeCategories: ['Electronics', 'Clothing'],
        subCategories: [...electronicsSubs, ...clothingSubs],
      );

  group('HomeViewModel multi-select sub filter', () {
    test('initial state: only "All <Large>" pseudo-sub is selected', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();

      // `_selectedLarge` defaults to 'All' → sub row is hidden, but
      // the set is still primed with the placeholder pseudo-sub
      // (here "All All") so the invariant is satisfied.
      expect(vm.selectedSubs, {'All All'});
      expect(vm.selectedLarge, 'All');
    });

    test('selecting a Large reseeds subs to its "All <Large>" pseudo', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();

      vm.selectLarge('Electronics');
      expect(vm.selectedLarge, 'Electronics');
      expect(vm.selectedSubs, {'All Electronics'});
    });

    test('toggling a real sub removes "All" and adds the sub (AND filter)',
        () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');

      vm.toggleSub('Phone');

      // "All Electronics" pseudo-sub is replaced by the concrete sub.
      expect(vm.selectedSubs, {'Phone'});
      // Single-sub selection still matches any product that
      // includes "Phone" (including multi-category products).
      final ids = vm.products.map((p) => p.id).toList()..sort();
      expect(ids, ['p-both', 'p-phone-1', 'p-phone-2']);
    });

    test('toggling a second real sub combines via AND — only products '
        'with both tags survive', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');
      vm.toggleSub('Phone');
      vm.toggleSub('Laptop');

      expect(vm.selectedSubs, {'Phone', 'Laptop'});
      // AND filter: only `p-both` is tagged with BOTH Phone and
      // Laptop. Phone-only and Laptop-only products are excluded.
      final ids = vm.products.map((p) => p.id).toList()..sort();
      expect(ids, ['p-both']);
    });

    test('toggling the last selected real sub re-adds the All pseudo', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');
      vm.toggleSub('Phone');
      vm.toggleSub('Laptop');

      // Remove Phone → set still non-empty.
      vm.toggleSub('Phone');
      expect(vm.selectedSubs, {'Laptop'});

      // Remove Laptop too → set would become empty, so "All
      // Electronics" is re-added to keep the invariant.
      vm.toggleSub('Laptop');
      expect(vm.selectedSubs, {'All Electronics'});
      expect(vm.selectedSubs, isNotEmpty,
          reason: 'set must never be empty — always at least the All pseudo');

      // Filter is back to "all products under this Large".
      final ids = vm.products.map((p) => p.id).toList()..sort();
      expect(ids, [
        'p-both',
        'p-laptop-1',
        'p-phone-1',
        'p-phone-2',
      ]);
    });

    test('tapping the "All <Large>" pseudo clears every concrete sub', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');
      vm.toggleSub('Phone');
      vm.toggleSub('Laptop');
      expect(vm.selectedSubs, {'Phone', 'Laptop'});

      vm.toggleSub('All Electronics');
      expect(vm.selectedSubs, {'All Electronics'});
    });

    test('switching Large resets the sub selection to that Large\'s All', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');
      vm.toggleSub('Phone');
      vm.toggleSub('Laptop');
      expect(vm.selectedSubs, {'Phone', 'Laptop'});

      // Move to Clothing — old Electronics subs are no longer valid.
      vm.selectLarge('Clothing');
      expect(vm.selectedLarge, 'Clothing');
      expect(vm.selectedSubs, {'All Clothing'});
    });

    test('products missing any selected sub are filtered out (AND)', () async {
      // Dedicated test for the motivating use case: a product that
      // is missing one of the selected categories must disappear.
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');

      // Pick Phone — `p-laptop-1` (Laptop only) is filtered out,
      // but `p-both` (Phone + Laptop) survives because it has Phone.
      vm.toggleSub('Phone');
      expect(vm.products.any((p) => p.id == 'p-laptop-1'), isFalse);
      expect(vm.products.any((p) => p.id == 'p-phone-1'), isTrue);
      expect(vm.products.any((p) => p.id == 'p-both'), isTrue);

      // Now also pick Laptop — only `p-both` qualifies.
      vm.toggleSub('Laptop');
      expect(vm.products.map((p) => p.id).toList(), ['p-both']);
    });

    test('selectedSubs is never empty after any sequence of toggles', () async {
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      vm.selectLarge('Electronics');
      vm.toggleSub('Phone');
      vm.toggleSub('Phone'); // toggle off → re-adds All
      vm.toggleSub('All Electronics'); // pseudo → still single
      vm.toggleSub('Laptop'); // adds Laptop, removes All
      vm.toggleSub('Laptop'); // removes Laptop → re-adds All

      expect(vm.selectedSubs, isNotEmpty);
    });

    test(
        'hasLoadedProducts stays true after filtering down to zero — '
        'picks a tag with no products without flashing the skeleton',
        () async {
      // Regression for the home-screen skeleton flash bug:
      // `products` is the *filtered* list, so when the user picks
      // a Large that has no products, `products.isEmpty` is true
      // and the screen used to swap back to HomeSkeleton. The
      // home screen now reads `hasLoadedProducts` (raw product
      // count) instead.
      final vm = HomeViewModel(productService: buildService());
      await vm.initialize();
      // Sanity: at least one product is loaded.
      expect(vm.hasLoadedProducts, isTrue);
      expect(vm.products, isNotEmpty);

      // Filter down to zero by selecting Clothing + AND of two
      // incompatible subs (p-shirt-1 doesn't have Pants, p-pants-1
      // doesn't have Shirt — only products tagged with BOTH
      // would survive, and none exist).
      vm.selectLarge('Clothing');
      vm.toggleSub('Shirt');
      vm.toggleSub('Pants');

      // Filter collapses — but raw products are still loaded.
      expect(vm.products, isEmpty);
      expect(vm.hasLoadedProducts, isTrue,
          reason:
              'hasLoadedProducts must stay true so the home screen '
              'keeps rendering the loaded layout (and its empty-state) '
              'instead of flashing back to the loading skeleton.');
    });
  });
}
