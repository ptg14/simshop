import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/i_product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/views/admin/admin_product/widgets/product_category_picker.dart';

/// In-memory [IProductService] that seeds a category hierarchy with
/// orphans. Used by the orphan-bucket regression test below.
class _OrphanProductService implements IProductService {
  final List<Category> _subs = <Category>[
    Category(name: 'Áo cũ', largeCategory: null),
    Category(name: 'Quần cũ', largeCategory: null),
    Category(name: 'Áo thun', largeCategory: 'Thời trang'),
    Category(name: 'Quần jean', largeCategory: 'Thời trang'),
  ];
  final List<String> _large = <String>['Thời trang'];

  /// Last arguments passed to [createCategoryWithParent]. The picker
  /// must invoke this with an empty `largeCategoryName` when the user
  /// adds a sub while the dropdown is on "-- Chọn danh mục lớn --"
  /// (the orphan bucket). We push into the local [_subs] so the new
  /// row surfaces in the next render of the chip list.
  Object? createCategoryParent;

  @override
  Future<List<Product>> getAllProducts() async => const <Product>[];

  @override
  Future<List<String>> getLargeCategories() async => List<String>.from(_large);

  @override
  Future<List<Category>> getCategoriesWithParent() async =>
      List<Category>.from(_subs);

  @override
  Future<void> createCategoryWithParent(
      String name, String largeCategoryName) async {
    createCategoryParent = largeCategoryName;
    _subs.add(Category(name: name, largeCategory: largeCategoryName.isEmpty
        ? null
        : largeCategoryName));
    if (largeCategoryName.isNotEmpty && !_large.contains(largeCategoryName)) {
      _large.add(largeCategoryName);
    }
  }

  // ---- Unused endpoints — throw to surface accidental calls.
  @override
  Future<List<Product>> getProductsByCategory(String category) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<List<Product>> searchProducts(String query, {int? limit}) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<void> deleteCategory(String name) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<void> createLargeCategory(String name) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<void> deleteLargeCategory(String name) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<Product> createProduct(Product product,
          {List<String>? removedImageUrls}) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<Product> updateProduct(String id, Product product,
          {List<String>? removedImageUrls}) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<void> deleteProduct(String id) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<String?> uploadImage(dynamic file,
          {String? productName, String? productId, int startIndex = 1}) async =>
      throw UnimplementedError('not used in this test');

  @override
  Future<List<String>> uploadImages(List<dynamic> files,
          {String? productName, String? productId, int startIndex = 1}) async =>
      throw UnimplementedError('not used in this test');
}

Widget _harness(AdminViewModel vm, ValueChanged<List<String>> onChanged) =>
    MaterialApp(
      home: Scaffold(
        body: ProductCategoryPicker(
          viewModel: vm,
          selectedCategories: const [],
          onChanged: onChanged,
        ),
      ),
    );

void main() {
  testWidgets(
      'orphan subs appear as ChoiceChips under "-- Chọn danh mục lớn --"',
      (tester) async {
    final svc = _OrphanProductService();
    final vm = AdminViewModel(productService: svc);
    await vm.loadLargeCategories();
    await vm.loadSubCategories();

    final picked = <String>[];
    final emitted = <List<String>>[];
    await tester.pumpWidget(_harness(vm, (l) {
      picked
        ..clear()
        ..addAll(l);
      emitted.add(List<String>.from(l));
    }));

    // The orphan bucket (dropdown == null) must show every sub with
    // largeCategory == null as a chip. Before the fix the same null
    // value produced "Vui lòng chọn danh mục lớn trước" and no chips.
    expect(find.text('Vui lòng chọn danh mục lớn trước'), findsNothing,
        reason: 'null Large dropdown must now mean "orphan bucket", '
            'not "please pick a Large"');
    expect(find.text('Áo cũ'), findsOneWidget,
        reason: 'orphan sub must surface in the chip row');
    expect(find.text('Quần cũ'), findsOneWidget,
        reason: 'orphan sub must surface in the chip row');
    expect(find.text('Áo thun'), findsNothing,
        reason: 'parented subs must NOT show in the orphan bucket');
    expect(find.text('Quần jean'), findsNothing,
        reason: 'parented subs must NOT show in the orphan bucket');
  });

  testWidgets(
      'tapping an orphan chip emits its name through onChanged', (tester) async {
    final svc = _OrphanProductService();
    final vm = AdminViewModel(productService: svc);
    await vm.loadLargeCategories();
    await vm.loadSubCategories();

    final picked = <String>[];
    await tester.pumpWidget(_harness(vm, (l) {
      picked
        ..clear()
        ..addAll(l);
    }));

    await tester.tap(find.text('Áo cũ'));
    await tester.pump();
    expect(picked, ['Áo cũ'],
        reason: 'orphan chip toggle must propagate to onChanged');
  });

  testWidgets(
      'add-submit while Large == null persists an orphan row',
      (tester) async {
    final svc = _OrphanProductService();
    final vm = AdminViewModel(productService: svc);
    await vm.loadLargeCategories();
    await vm.loadSubCategories();

    await tester.pumpWidget(_harness(vm, (_) {}));

    // Open the inline add-sub input. The plus button is the only
    // Icon in the chip row's trailing slot — tap it directly.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();

    // Type a name and submit.
    await tester.enterText(find.byType(TextField).last, 'Mũ cũ');
    await tester.tap(find.byIcon(Icons.check).first);
    await tester.pump();
    await tester.pump();

    expect(svc.createCategoryParent, '',
        reason: 'empty parent must reach the backend so the row is '
            'persisted with large_category_id = NULL (orphan)');
    // The new sub should now be a chip in the picker.
    expect(find.text('Mũ cũ'), findsOneWidget,
        reason: 'newly created orphan sub must render in the chip row');
  });
}