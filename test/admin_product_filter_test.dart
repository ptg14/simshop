import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';

/// In-memory IProductService backing the filter / stock tests.
/// Every test seeds the underlying list and asserts on what the VM
/// computes / sends — no real HTTP calls.
class _InMemoryProductService implements IProductService {
  _InMemoryProductService(this._products);
  final List<Product> _products;

  /// Records every [updateProduct] call so quickAdjustStock tests can
  /// assert on what payload the VM sent to the backend.
  final List<({String id, Product product})> updates = [];

  @override
  Future<List<Product>> getAllProducts() async => List.of(_products);
  @override
  Future<List<Product>> getProductsByCategory(String category) async =>
      _products.where((p) => p.category == category).toList();
  @override
  Future<Product> getProductById(String id) async =>
      _products.firstWhere((p) => p.id == id);
  @override
  Future<List<Product>> searchProducts(String query) async {
    final q = query.toLowerCase();
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<void> deleteProduct(String id) async {
    _products.removeWhere((p) => p.id == id);
  }

  @override
  Future<Product> createProduct(
    Product product, {
    List<String>? removedImageUrls,
  }) async =>
      product;

  @override
  Future<Product> updateProduct(
    String id,
    Product product, {
    List<String>? removedImageUrls,
  }) async {
    updates.add((id: id, product: product));
    final idx = _products.indexWhere((p) => p.id == id);
    if (idx >= 0) _products[idx] = product;
    return product;
  }

  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<void> deleteCategory(String name) async {}
  @override
  Future<List<String>> getLargeCategories() async =>
      const ['Clothing', 'Electronics'];
  @override
  Future<List<Category>> getCategoriesWithParent() async => [
        Category(name: 'Shirts', largeCategory: 'Clothing'),
        Category(name: 'Pants', largeCategory: 'Clothing'),
        Category(name: 'Phones', largeCategory: 'Electronics'),
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

Product _p({
  required String id,
  required String name,
  String description = '',
  int? stock = 0,
  List<String> categories = const ['Shirts'],
  String category = 'Shirts',
}) =>
    Product(
      id: id,
      name: name,
      description: description,
      price: 100,
      imageUrl: '',
      category: category,
      categories: categories,
      rating: 0,
      stock: stock,
      specs: const [],
    );

/// Build a fully-initialized [AdminViewModel] backed by [svc]. Used
/// by every filter test so the product list + category hierarchy
/// are loaded before assertions run.
Future<AdminViewModel> _seeded(
  _InMemoryProductService svc,
) async {
  final vm = AdminViewModel(productService: svc);
  await vm.initialize();
  return vm;
}

void main() {
  group('AdminViewModel filter state', () {
    test('default state returns every product', () async {
      final svc = _InMemoryProductService([
        _p(id: 'a', name: 'Áo sơ mi'),
        _p(
            id: 'b',
            name: 'Quần jean',
            categories: ['Pants'],
            category: 'Pants'),
      ]);
      final vm = await _seeded(svc);
      expect(vm.filteredProducts.length, 2);
    });

    test('setFilterLargeCategory narrows to subs under that Large', () async {
      final svc = _InMemoryProductService([
        _p(id: 'a', name: 'Áo sơ mi'),
        _p(
            id: 'b',
            name: 'Quần jean',
            categories: ['Pants'],
            category: 'Pants'),
      ]);
      final vm = await _seeded(svc);
      vm.setFilterLargeCategory('Clothing');
      expect(vm.filteredProducts.map((p) => p.id), ['a', 'b']);
      vm.setFilterLargeCategory('Electronics');
      expect(vm.filteredProducts, isEmpty);
    });

    test('setFilterSubCategory drills down within a Large', () async {
      final svc = _InMemoryProductService([
        _p(id: 'a', name: 'Áo sơ mi'),
        _p(
            id: 'b',
            name: 'Quần jean',
            categories: ['Pants'],
            category: 'Pants'),
        _p(
            id: 'c',
            name: 'Áo thun',
            categories: ['Shirts'],
            category: 'Shirts'),
      ]);
      final vm = await _seeded(svc);
      vm.setFilterLargeCategory('Clothing');
      vm.setFilterSubCategory('Shirts');
      expect(vm.filteredProducts.map((p) => p.id).toSet(), {'a', 'c'});
    });

    test('clearing filter resets every dimension', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo sơ mi')]);
      final vm = await _seeded(svc);
      vm.setFilterLargeCategory('Clothing');
      vm.setFilterSubCategory('Shirts');
      vm.setFilterSearch('áo');
      vm.clearFilters();
      expect(vm.filterLargeCategory, isNull);
      expect(vm.filterSubCategory, isNull);
      expect(vm.filterSearch, isEmpty);
      expect(vm.filteredProducts.length, 1);
    });

    test('free-text search matches name and description, case-insensitive',
        () async {
      final svc = _InMemoryProductService([
        _p(id: 'a', name: 'Áo sơ mi', description: 'cotton 100%'),
        _p(id: 'b', name: 'Quần jean', description: 'denim classic'),
        _p(id: 'c', name: 'Mũ lưỡi trai', description: 'phụ kiện'),
      ]);
      final vm = await _seeded(svc);
      vm.setFilterSearch('COTTON');
      expect(vm.filteredProducts.map((p) => p.id), ['a']);
      vm.setFilterSearch('denim');
      expect(vm.filteredProducts.map((p) => p.id), ['b']);
      vm.setFilterSearch('zzzzz-no-match');
      expect(vm.filteredProducts, isEmpty);
    });

    test('unassigned sentinel matches products with no category', () async {
      final svc = _InMemoryProductService([
        _p(id: 'a', name: 'Áo sơ mi'),
        _p(
            id: 'b',
            name: 'Chưa phân loại 1',
            categories: const [],
            category: ''),
        _p(
            id: 'c',
            name: 'Chưa phân loại 2',
            categories: const [],
            category: ''),
      ]);
      final vm = await _seeded(svc);
      vm.setFilterSubCategory(AdminViewModel.unassignedSentinel);
      final ids = vm.filteredProducts.map((p) => p.id).toSet();
      expect(ids, {'b', 'c'});
    });

    test('large filter cleans up stale sub-category selection', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo sơ mi')]);
      final vm = await _seeded(svc);
      vm.setFilterLargeCategory('Clothing');
      vm.setFilterSubCategory('Shirts');
      // Picking a *different* large should clear the orphan sub.
      vm.setFilterLargeCategory('Electronics');
      expect(vm.filterSubCategory, isNull);
    });

    test('filteredSubCategories mirrors selected Large', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo sơ mi')]);
      final vm = await _seeded(svc);
      // All subs when no Large picked.
      final allSubs = vm.filteredSubCategories.map((c) => c.name).toSet();
      expect(allSubs, {'Shirts', 'Pants', 'Phones'});
      vm.setFilterLargeCategory('Clothing');
      final clothingSubs = vm.filteredSubCategories.map((c) => c.name).toSet();
      expect(clothingSubs, {'Shirts', 'Pants'});
    });
  });

  group('AdminViewModel.quickAdjustStock', () {
    test('positive delta persists a new stock value', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo', stock: 5)]);
      final vm = await _seeded(svc);

      final newStock = await vm.quickAdjustStock('a', 3);
      expect(newStock, 8);
      expect(vm.products.first.stock, 8);
      expect(svc.updates, hasLength(1));
      expect(svc.updates.first.product.stock, 8);
    });

    test('negative delta clamps at zero instead of going negative', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo', stock: 2)]);
      final vm = await _seeded(svc);

      final newStock = await vm.quickAdjustStock('a', -5);
      expect(newStock, 0);
      expect(vm.products.first.stock, 0);
      expect(svc.updates, hasLength(1));
    });

    test('already-at-floor returns null without hitting backend', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo', stock: 0)]);
      final vm = await _seeded(svc);

      final newStock = await vm.quickAdjustStock('a', -1);
      expect(newStock, isNull);
      expect(svc.updates, isEmpty);
    });

    test('zero delta is a no-op', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo', stock: 3)]);
      final vm = await _seeded(svc);

      final newStock = await vm.quickAdjustStock('a', 0);
      expect(newStock, isNull);
      expect(svc.updates, isEmpty);
    });

    test('non-existent product id is a no-op', () async {
      final svc = _InMemoryProductService([_p(id: 'a', name: 'Áo', stock: 3)]);
      final vm = await _seeded(svc);

      final newStock = await vm.quickAdjustStock('does-not-exist', 5);
      expect(newStock, isNull);
      expect(svc.updates, isEmpty);
    });
  });
}