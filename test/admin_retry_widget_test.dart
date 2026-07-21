// Widget-level test for the "Thử lại" (retry) button on the admin
// products screen.
//
// The button in [AdminProductsScreen] calls [AdminViewModel.initialize]
// when tapped — see `lib/views/admin/admin_product/admin_product_screen.dart:112`.
// Before the fix, [AdminViewModel.initialize] did not reset its `_error`
// field on entry and silently swallowed `getAllProducts()` failures, so
// any prior failure left `_error` non-null and the error view stayed
// painted no matter how many times the user mashed the retry button.
//
// The fix makes `initialize()` clear `_error` on entry and capture
// `getAllProducts()` failures into `_error`. This widget test pins
// both halves of the contract: a failing-then-recovering service
// transitions the admin screen from the error view back to the
// loaded list when the retry button is tapped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/views/admin/admin_product/admin_product_screen.dart';

class _ToggleableService implements IProductService {
  /// When true, [getAllProducts] throws; otherwise it returns the
  /// current [_products] list. Tests flip this flag to drive the
  /// failure → recovery arc end-to-end.
  bool failNext = false;

  final List<Product> _products = [
    Product(
      id: 'p1',
      name: 'Áo thun test',
      description: 'desc',
      price: 100000,
      imageUrl: '',
      category: 'All',
      categories: const ['All'],
      rating: 0,
      stock: 0,
      specs: const [],
    ),
  ];

  int getAllCalls = 0;

  @override
  Future<List<Product>> getAllProducts() async {
    getAllCalls += 1;
    if (failNext) throw Exception('boom');
    return List.of(_products);
  }

  @override
  Future<List<Product>> getProductsByCategory(String category) async => _products;
  @override
  Future<Product> getProductById(String id) async => _products.first;
  @override
  Future<List<Product>> searchProducts(String query) async => _products;
  @override
  Future<void> deleteProduct(String id) async {}
  @override
  Future<Product> createProduct(Product product, {List<String>? removedImageUrls}) async => product;
  @override
  Future<Product> updateProduct(String id, Product product, {List<String>? removedImageUrls}) async => product;
  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteCategory(String name) async {}
  @override
  Future<List<String>> getLargeCategories() async => const ['All'];
  @override
  Future<List<Category>> getCategoriesWithParent() async => [
        Category(name: 'All', largeCategory: 'All'),
      ];
  @override
  Future<void> createLargeCategory(String name) async {}
  @override
  Future<void> deleteLargeCategory(String name) async {}
  @override
  Future<void> createCategoryWithParent(String name, String largeCategoryName) async {}
  @override
  Future<String?> uploadImage(dynamic file, {String? productName, String? productId, int startIndex = 1}) async => null;
  @override
  Future<List<String>> uploadImages(List<dynamic> files, {String? productName, String? productId, int startIndex = 1}) async => const [];
}

Widget _host(AdminViewModel vm) {
  return MaterialApp(
    home: ChangeNotifierProvider<AdminViewModel>.value(
      value: vm,
      child: const AdminProductsScreen(),
    ),
  );
}

void main() {
  testWidgets(
    'admin retry button transitions the screen from error → loaded',
    (tester) async {
      // The error view has heavy vertical padding (vertical: 64) and
      // a large icon (size: 80). The default Flutter test viewport
      // (800x600 minus appbar) is tight; bump to a tablet-ish size so
      // the layout doesn't trip RenderFlex-overflow diagnostics that
      // have nothing to do with the retry contract.
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final svc = _ToggleableService();
      final vm = AdminViewModel(productService: svc);

      // 1. First load fails → screen renders the error view + retry.
      svc.failNext = true;
      await tester.pumpWidget(_host(vm));
      // Let the post-frame [initialize] resolve.
      await tester.pumpAndSettle();

      expect(find.text('Không thể tải sản phẩm'), findsOneWidget,
          reason: 'the error view should be rendered after a failure');
      expect(find.text('Thử lại'), findsOneWidget);

      // 2. Network "recovers". Tap the retry button.
      svc.failNext = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      // 3. Error view is gone, product is visible. This is the step
      //    that was broken before the fix: `_error` stayed stuck and
      //    the error view stayed painted, making the retry button
      //    look completely useless.
      expect(find.text('Không thể tải sản phẩm'), findsNothing,
          reason: 'a successful retry must clear the error view');
      expect(find.text('Áo thun test'), findsOneWidget,
          reason: 'after retry the loaded product must render');
    },
  );
}
