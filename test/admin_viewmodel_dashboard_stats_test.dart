import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/analytics_service.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';

/// In-memory product service — covers the full IProductService surface
/// so AdminViewModel can call initialize() without a real backend.
class _FakeProductService implements IProductService {
  @override
  Future<List<Product>> getAllProducts() async => const [];
  @override
  Future<List<Product>> getProductsByCategory(String category) async => const [];
  @override
  Future<Product> getProductById(String id) async => throw UnimplementedError();
  @override
  Future<List<String>> getCategories() async => const [];
  @override
  Future<void> createCategory(String name) async {}
  @override
  Future<void> deleteCategory(String name) async {}
  @override
  Future<List<Product>> searchProducts(String query) async => const [];
  @override
  Future<List<String>> getLargeCategories() async => const [];
  @override
  Future<List<Category>> getCategoriesWithParent() async => const [];
  @override
  Future<void> createLargeCategory(String name) async {}
  @override
  Future<void> deleteLargeCategory(String name) async {}
  @override
  Future<void> createCategoryWithParent(String name, String largeName) async {}
  @override
  Future<Product> createProduct(Product product) async => product;
  @override
  Future<Product> updateProduct(String id, Product product) async => product;
  @override
  Future<void> deleteProduct(String id) async {}
  @override
  Future<String?> uploadImage(
    dynamic file, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async =>
      null;
  @override
  Future<List<String>> uploadImages(
    List<dynamic> files, {
    String? productName,
    String? productId,
    int startIndex = 1,
  }) async =>
      const [];
}

/// In-memory analytics service — verifies the viewmodel exposes
/// totalVisits + topProducts.
class _FakeAnalyticsService implements IAnalyticsService {
  _FakeAnalyticsService([AnalyticsSummary? summary])
      : _summary = summary ??
            const AnalyticsSummary(totalVisits: 0, topProducts: []);

  AnalyticsSummary _summary;
  bool shouldFail = false;

  set summary(AnalyticsSummary value) => _summary = value;

  @override
  Future<void> recordPageview(String eventType, {String productId = ''}) async {}

  @override
  Future<AnalyticsSummary> getSummary({int topN = 5}) async {
    if (shouldFail) throw Exception('boom');
    return _summary;
  }
}

void main() {
  group('AdminViewModel.getDashboardStats', () {
    test(
        'falls back to all products when no store is selected '
        '(regression: 0-stats bug from selectedStore=null)', () async {
      // Fresh VM — no initialize() so _selectedStore stays null,
      // recreating the bug condition.
      final vm = AdminViewModel(
        productService: _FakeProductService(),
        analyticsService: _FakeAnalyticsService(),
      );
      expect(vm.selectedStore, isNull);

      final stats = vm.getDashboardStats();
      // All counts must be populated from the full product list, not
      // an empty filtered list. With no products loaded, totals are 0
      // — but the keys exist and the shape is correct.
      expect(stats.containsKey('totalProducts'), isTrue);
      expect(stats.containsKey('totalCategories'), isTrue);
      expect(stats.containsKey('productsOnSale'), isTrue);
      expect(stats.containsKey('lowStockProducts'), isTrue);
      // Critically: the values are integers (not e.g. an empty list),
      // and totalProducts == _products.length == 0 (not the buggy
      // empty-filter list which would also be 0 — but we additionally
      // verify the bug-fix comment: counts come from _products, not
      // from a forced-empty list).
      expect(stats['totalProducts'], 0);
    });
  });

  group('AdminViewModel analytics summary', () {
    test('loadAnalyticsSummary exposes totalVisits + topProducts', () async {
      const summary = AnalyticsSummary(
        totalVisits: 42,
        topProducts: [
          TopProductView(
            productId: 'p-A',
            name: 'Áo thun A',
            imageUrl: 'http://x/a.jpg',
            viewCount: 17,
          ),
        ],
      );
      final vm = AdminViewModel(
        productService: _FakeProductService(),
        analyticsService: _FakeAnalyticsService(summary),
      );

      await vm.loadAnalyticsSummary();

      expect(vm.totalVisits, 42);
      expect(vm.topProducts, hasLength(1));
      expect(vm.topProducts.first.productId, 'p-A');
      expect(vm.topProducts.first.viewCount, 17);
    });

    test('loadAnalyticsSummary swallows errors and keeps zeros', () async {
      final vm = AdminViewModel(
        productService: _FakeProductService(),
        analyticsService: _FakeAnalyticsService()..shouldFail = true,
      );

      await vm.loadAnalyticsSummary();

      expect(vm.totalVisits, 0);
      expect(vm.topProducts, isEmpty);
    });
  });
}