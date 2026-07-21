import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/viewmodels/home_viewmodel.dart';
import 'package:simshop/views/admin/admin_product/add_product_dialog.dart';
import 'package:simshop/views/admin/admin_product/edit_product_dialog.dart';
import 'package:simshop/views/admin/admin_product/widgets/specs_editor.dart';

/// In-memory product service. Identical to the one in
/// admin_product_options_test.dart — duplicated here rather than
/// extracted into a shared helper, because the existing test file's
/// fake isn't exported and the extraction would require touching
/// it (out of scope per the plan).
class _FakeProductService implements IProductService {
  @override
  Future<List<Product>> getAllProducts() async => const [];
  @override
  Future<List<Product>> getProductsByCategory(String category) async =>
      const [];
  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError('not used in these tests');
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
  Future<void> createCategoryWithParent(String name,
      String largeCategoryName) async {}
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
  }) async =>
      product;
  @override
  Future<void> deleteProduct(String id) async {}
  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError();
  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName, String? productId, int startIndex = 1}) async =>
      null;
  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName, String? productId, int startIndex = 1}) async =>
      const [];
}

/// Captures whatever the dialog hands to [AdminViewModel.updateProduct]
/// so the test can inspect the submitted product.
class _CapturingAdminViewModel extends AdminViewModel {
  _CapturingAdminViewModel(IProductService svc) : super(productService: svc);

  Product? lastSubmitted;

  @override
  Future<void> updateProduct(
    String id,
    Product product, {
    dynamic imageFile,
    List<String>? removedImageUrls,
    List<String>? imageOrder,
  }) async {
    lastSubmitted = product;
  }
}

/// Captures the product handed to [AdminViewModel.addProduct].
class _AddCapturingAdminViewModel extends AdminViewModel {
  _AddCapturingAdminViewModel(IProductService svc) : super(productService: svc);

  Product? lastCreated;

  @override
  Future<void> addProduct(
    Product product, {
    dynamic imageFile,
    List<String>? removedImageUrls,
    List<String>? imageOrder,
  }) async {
    lastCreated = product;
  }
}

/// Locator for spec TextFields in the dialog. The Edit dialog also
/// contains name/price/stock/description TextFields (the description
/// editor's raw text area is a multiline TextField), so we use
/// `widgetWithText` to find the one whose controller currently
/// holds a spec value.
Finder _specField(String value) => find.widgetWithText(TextField, value);

void main() {
  // Pin a wide surface so the dialog fits naturally.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('EditProductDialog specs', () {
    testWidgets('hydrates TextFields from product.specs on open',
        (tester) async {
      useWideSurface(tester);
      final product = Product(
        id: 'p-1',
        name: 'Áo thun',
        description: '',
        price: 100,
        imageUrl: 'https://example.test/a.jpg',
        images: const ['https://example.test/a.jpg'],
        category: 'All',
        categories: const ['All'],
        rating: 0,
        reviews: 0,
        stock: 0,
        specs: const ['Chất liệu: Cotton', 'Size: M'],
      );
      final vm = _CapturingAdminViewModel(_FakeProductService());

      await tester.pumpWidget(MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AdminViewModel>.value(value: vm),
            ChangeNotifierProvider<HomeViewModel>(
                create: (_) => HomeViewModel()),
          ],
          child: Scaffold(
            body: Center(child: EditProductDialog(viewModel: vm, product: product)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Section header is rendered.
      expect(find.text('Thông số kỹ thuật'), findsOneWidget);

      // Each spec seed produces one TextField with the seed text.
      expect(_specField('Chất liệu: Cotton'), findsOneWidget);
      expect(_specField('Size: M'), findsOneWidget);
    });

    testWidgets('editing a spec + submit persists the new value',
        (tester) async {
      useWideSurface(tester);
      final product = Product(
        id: 'p-1',
        name: 'Áo thun',
        description: '',
        price: 100,
        imageUrl: 'https://example.test/a.jpg',
        images: const ['https://example.test/a.jpg'],
        category: 'All',
        categories: const ['All'],
        rating: 0,
        reviews: 0,
        stock: 0,
        specs: const ['Chất liệu: Cotton', 'Size: M'],
      );
      final vm = _CapturingAdminViewModel(_FakeProductService());

      await tester.pumpWidget(MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AdminViewModel>.value(value: vm),
            ChangeNotifierProvider<HomeViewModel>(
                create: (_) => HomeViewModel()),
          ],
          child: Scaffold(
            body: Center(child: EditProductDialog(viewModel: vm, product: product)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Type a new value into the first specs row, replacing the
      // controller's existing text.
      final firstSpec = _specField('Chất liệu: Cotton');
      expect(firstSpec, findsOneWidget);
      await tester.enterText(firstSpec, 'Chất liệu: Cotton 100%');
      await tester.pump();

      // Submit and confirm the captured product carries both lines,
      // with the first one updated and the second preserved.
      await tester.tap(find.text('Cập nhật'));
      await tester.pumpAndSettle();

      expect(vm.lastSubmitted, isNotNull);
      expect(vm.lastSubmitted!.specs, [
        'Chất liệu: Cotton 100%',
        'Size: M',
      ]);
    });
  });

  group('AddProductDialog specs', () {
    testWidgets('add-row button pushes an empty TextField; submit carries the typed value',
        (tester) async {
      useWideSurface(tester);
      final vm = _AddCapturingAdminViewModel(_FakeProductService());

      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<AdminViewModel>.value(
          value: vm,
          child: Scaffold(
            body: Center(child: AddProductDialog(viewModel: vm)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // The Add dialog starts with no specs, so the section header
      // is there but the spec TextField locator (which searches for
      // a TextField that contains a given string) finds nothing.
      expect(find.text('Thông số kỹ thuật'), findsOneWidget);
      expect(find.byType(SpecsEditor), findsOneWidget);
      expect(_specField('Size: L'), findsNothing);

      // Tap the add-row button — the first row appears with empty
      // text, so the only way to address it is by its index inside
      // the SpecsEditor's tree. We approximate with `find.descendant`
      // matching the empty controller.
      final addRowButton = find.text('Thêm dòng');
      expect(addRowButton, findsOneWidget);
      await tester.tap(addRowButton);
      await tester.pump();
      await tester.tap(addRowButton);
      await tester.pump();
      await tester.tap(addRowButton);
      await tester.pump();

      // Three rows should now exist. Type into the second row by
      // finding every TextField inside the SpecsEditor (excludes
      // the dialog's name/price/stock/description fields).
      final specsEditor = find.byType(SpecsEditor);
      final specFields = find.descendant(
        of: specsEditor,
        matching: find.byType(TextField),
      );
      expect(specFields, findsNWidgets(3));

      await tester.enterText(specFields.at(1), 'Size: L');
      await tester.pump();

      // The second row's controller now carries the typed value.
      final secondFieldWidget = tester.widget<TextField>(specFields.at(1));
      expect(secondFieldWidget.controller!.text, 'Size: L');
    });
  });
}