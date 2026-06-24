import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/viewmodels/home_viewmodel.dart';
import 'package:simshop/views/admin/admin_product/edit_product_dialog.dart';

/// In-memory product service. The dialogs we test call
/// `updateProduct` indirectly (via the VM), so the fake is hit only if
/// the dialog actually uploads new images, which neither test does.
class _FakeProductService implements IProductService {
  @override
  Future<List<Product>> getAllProducts() async => const [];
  @override
  Future<List<Product>> getProductsByCategory(String category) async => const [];
  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError('not used in these tests');
  @override
  Future<List<String>> getCategories() async => const [];
  @override
  Future<void> createCategory(String name) async {}
  @override
  Future<void> deleteCategory(String name) async {}
  @override
  Future<List<Product>> searchProducts(String query,
          {int? limit}) async =>
      const [];
  @override
  Future<List<String>> getLargeCategories() async => const [];
  @override
  Future<List<Category>> getCategoriesWithParent() async => const [];
  @override
  Future<void> createLargeCategory(String name) async {}
  @override
  Future<void> deleteLargeCategory(String name) async {}
  @override
  Future<void> createCategoryWithParent(String name, String largeCategoryName) async {}
  @override
  Future<Product> createProduct(Product product) async => product;
  @override
  Future<Product> updateProduct(String id, Product product) async => product;
  @override
  Future<void> deleteProduct(String id) async {}
  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName, String? productId, int startIndex = 1}) async =>
      null;
  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName, String? productId, int startIndex = 1}) async =>
      const [];
}

/// Subclass that captures the product passed to [updateProduct] so the
/// test can assert what the dialog actually submitted (e.g. that the
/// option's `imageUrls` survived a name edit).
class _CapturingAdminViewModel extends AdminViewModel {
  _CapturingAdminViewModel(IProductService svc) : super(productService: svc);

  Product? lastSubmitted;

  @override
  Future<void> updateProduct(String id, Product product,
      {dynamic imageFile}) async {
    lastSubmitted = product;
  }
}

void main() {
  // Pin a wide surface so the dialog fits naturally.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Edit dialog: 3 option rows do not overlap (y monotonic)',
      (tester) async {
    useWideSurface(tester);
    final product = Product(
      id: 'p-1',
      name: 'Áo thun',
      description: '',
      price: 100,
      imageUrl: 'https://example.test/a.jpg',
      images: ['https://example.test/a.jpg'],
      category: 'All',
      categories: ['All'],
      rating: 0,
      reviews: 0,
      stock: 0,
      specs: [],
      options: [
        Option(id: 'o1', name: 'Red'),
        Option(id: 'o2', name: 'Blue'),
        Option(id: 'o3', name: 'Green'),
      ],
    );
    final vm = _CapturingAdminViewModel(_FakeProductService());

    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<AdminViewModel>.value(
        value: vm,
        child: Scaffold(
          body: Center(
            child: EditProductDialog(viewModel: vm, product: product),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 3 option name fields -> 3 TextFormField widgets in y-order.
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));

    final ys = <double>[];
    for (var i = 0; i < 3; i++) {
      ys.add(tester.getTopLeft(fields.at(i)).dy);
    }
    // Monotonically increasing with a positive gap (no overlap, no
    // collapsing rows).
    expect(ys[1], greaterThan(ys[0]),
        reason: 'row 1 should render below row 0');
    expect(ys[2], greaterThan(ys[1]),
        reason: 'row 2 should render below row 1');
    expect(ys[1] - ys[0], greaterThan(20),
        reason: 'rows should not visually overlap (gap > 20px)');
    expect(ys[2] - ys[1], greaterThan(20),
        reason: 'rows should not visually overlap (gap > 20px)');
  });

  testWidgets('Edit dialog: typing in an option name preserves imageUrls',
      (tester) async {
    useWideSurface(tester);
    const url = 'https://example.test/img.jpg';
    final product = Product(
      id: 'p-1',
      name: 'Áo thun',
      description: '',
      price: 100,
      imageUrl: url,
      images: [url],
      category: 'All',
      categories: ['All'],
      rating: 0,
      reviews: 0,
      stock: 0,
      specs: [],
      options: [Option(id: 'o1', name: 'Red', imageUrls: const [url])],
    );
    final vm = _CapturingAdminViewModel(_FakeProductService());

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AdminViewModel>.value(value: vm),
          ChangeNotifierProvider<HomeViewModel>(create: (_) => HomeViewModel()),
        ],
        child: Scaffold(
          body: Center(
            child: EditProductDialog(viewModel: vm, product: product),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Type into the first (and only) option name field.
    final field = find.byType(TextFormField).first;
    await tester.enterText(field, 'Crimson');
    await tester.pump();

    // Submit the dialog.
    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();

    // The captured product must retain the option's imageUrls.
    expect(vm.lastSubmitted, isNotNull);
    expect(vm.lastSubmitted!.options, hasLength(1));
    expect(vm.lastSubmitted!.options[0].name, 'Crimson');
    expect(vm.lastSubmitted!.options[0].imageUrls, [url]);
  });
}
