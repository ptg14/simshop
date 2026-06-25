import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/analytics_service.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/views/admin/admin_overview.dart';

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

class _FakeAnalyticsService implements IAnalyticsService {
  _FakeAnalyticsService([AnalyticsSummary? summary])
      : _summary = summary ?? const AnalyticsSummary(totalVisits: 0, topProducts: []);

  AnalyticsSummary _summary;

  set summary(AnalyticsSummary value) => _summary = value;

  @override
  Future<void> recordPageview(String eventType, {String productId = ''}) async {}

  @override
  Future<AnalyticsSummary> getSummary({int topN = 5}) async => _summary;
}

Widget _wrap(Widget child, AdminViewModel vm) => MaterialApp(
      home: ChangeNotifierProvider<AdminViewModel>.value(
        value: vm,
        child: child,
      ),
    );

void main() {
  testWidgets('AdminOverviewScreen renders the 5th "Tổng lượt truy cập" card',
      (tester) async {
    final vm = AdminViewModel(
      productService: _FakeProductService(),
      analyticsService: _FakeAnalyticsService(
        const AnalyticsSummary(totalVisits: 123, topProducts: []),
      ),
    );
    await vm.initialize();

    await tester.pumpWidget(_wrap(const AdminOverviewScreen(), vm));
    await tester.pumpAndSettle();

    expect(find.text('Tổng lượt truy cập'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
  });

  testWidgets('AdminOverviewScreen shows top products list when data exists',
      (tester) async {
    const summary = AnalyticsSummary(
      totalVisits: 50,
      topProducts: [
        TopProductView(
          productId: 'p-A',
          name: 'Áo thun A',
          imageUrl: '',
          viewCount: 25,
        ),
        TopProductView(
          productId: 'p-B',
          name: 'Quần jean B',
          imageUrl: '',
          viewCount: 10,
        ),
      ],
    );
    final vm = AdminViewModel(
      productService: _FakeProductService(),
      analyticsService: _FakeAnalyticsService(summary),
    );
    await vm.initialize();

    await tester.pumpWidget(_wrap(const AdminOverviewScreen(), vm));
    await tester.pumpAndSettle();

    expect(find.text('Sản phẩm xem nhiều nhất'), findsOneWidget);
    expect(find.text('Áo thun A'), findsOneWidget);
    expect(find.text('Quần jean B'), findsOneWidget);
    expect(find.text('25 lượt xem'), findsOneWidget);
    expect(find.text('10 lượt xem'), findsOneWidget);
    // Rank chips render 1, 2.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('AdminOverviewScreen shows empty hint when no top products',
      (tester) async {
    final vm = AdminViewModel(
      productService: _FakeProductService(),
      analyticsService: _FakeAnalyticsService(),
    );
    await vm.initialize();

    await tester.pumpWidget(_wrap(const AdminOverviewScreen(), vm));
    await tester.pumpAndSettle();

    expect(find.text('Sản phẩm xem nhiều nhất'), findsOneWidget);
    expect(
      find.textContaining('Chưa có dữ liệu truy cập'),
      findsOneWidget,
    );
  });
}
