import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';
import 'package:simshop/viewmodels/home_viewmodel.dart';
import 'package:simshop/views/admin/admin_product/edit_product_dialog.dart';
import 'package:simshop/views/admin/admin_product/widgets/options_editor_with_images.dart';

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
  Future<List<Product>> searchProducts(String query,
          {int? limit}) async =>
      const [];
  @override
  Future<void> deleteCategory(String name) async {}
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
  Future<Product> updateStock(String id, int? stock) async =>
      throw UnimplementedError();
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
  List<String>? lastRemovedImageUrls;

  @override
  Future<void> updateProduct(
    String id,
    Product product, {
    dynamic imageFile,
    List<String>? removedImageUrls,
  }) async {
    lastSubmitted = product;
    lastRemovedImageUrls = removedImageUrls;
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

  testWidgets('Add dialog: adding an option shows new image bytes thumb',
      (tester) async {
    useWideSurface(tester);

    // The Add dialog's image-picker grid feeds _selectedImagesBytes.
    // We construct the dialog and reach into the public VM to bypass
    // the actual file picker; the editor's image strip should still
    // show the bytes via OptionsEditorWithImages.
    final pngBytes = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
      0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
      0x82,
    ]);
    final vm = _CapturingAdminViewModel(_FakeProductService());

    // Drive the editor directly — the Add dialog's _selectedImagesBytes
    // is private, so we exercise the same OptionsEditorWithImages
    // with the bytes the dialog would feed it.
    final options = <Option>[];

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AdminViewModel>.value(value: vm),
          ChangeNotifierProvider<HomeViewModel>(create: (_) => HomeViewModel()),
        ],
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => OptionsEditorWithImages(
              options: options,
              existingImages: const [],
              newImageBytes: [pngBytes],
              onChanged: (opts) => setState(() => options
                ..clear()
                ..addAll(opts)),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Add an option.
    await tester.tap(find.text('Thêm option'));
    await tester.pumpAndSettle();

    // The bytes thumb is visible in the option row.
    final memImages = find
        .byWidgetPredicate((w) => w is Image && w.image is MemoryImage)
        .evaluate();
    expect(memImages, isNotEmpty,
        reason: 'picked bytes should be visible as Image.memory in the option row');
  });

  // Edit dialog contract: the option row shows BOTH existing URL
  // thumbs (selectable) AND new bytes thumbs (non-selectable), so
  // admins can see what they've picked and what's still server-
  // backed in the same row.
  testWidgets(
      'Edit dialog: option row shows existing URL thumbs and new bytes thumbs',
      (tester) async {
    useWideSurface(tester);

    final pngBytes = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
      0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
      0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
      0x82,
    ]);

    // Existing URL won't be decoded in the test (network is off),
    // but the widget should still render it as an Image.network.
    const existingUrl = 'https://example.test/existing.jpg';

    final options = <Option>[Option(id: 'o1', name: 'Red')];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => OptionsEditorWithImages(
            options: options,
            existingImages: const [existingUrl],
            newImageBytes: [pngBytes],
            onChanged: (opts) => setState(() => options
              ..clear()
              ..addAll(opts)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Network image (existing URL) rendered.
    final netImages = find
        .byWidgetPredicate((w) => w is Image && w.image is NetworkImage)
        .evaluate();
    expect(netImages, isNotEmpty,
        reason: 'existing URL should be visible as Image.network in the option row');

    // Bytes image (newly picked) rendered.
    final memImages = find
        .byWidgetPredicate((w) => w is Image && w.image is MemoryImage)
        .evaluate();
    expect(memImages, isNotEmpty,
        reason: 'newly picked bytes should be visible as Image.memory in the option row');
  });

  // Regression: when the admin deletes a product-gallery image whose
  // URL is also referenced by an option's `imageUrls`, the option's
  // gallery would still show the deleted image on the detail page
  // because the URL was never pruned from `option.imageUrls` on
  // submit. The backend deletes the file from /uploads/, so the option
  // ended up holding a broken URL. Fix: strip removed URLs from each
  // option's `imageUrls` before submit.
  testWidgets(
      'Edit dialog: deleting a gallery image also strips that URL from every option',
      (tester) async {
    useWideSurface(tester);
    const redUrl = 'https://example.test/red.jpg';
    const blueUrl = 'https://example.test/blue.jpg';
    // Two product images. Both are referenced by the "Red" option
    // (so the bug had two URLs to leak through). The "Blue" option
    // references only the blue image so we can prove the strip is
    // targeted, not a blanket wipe.
    final product = Product(
      id: 'p-1',
      name: 'Áo thun',
      description: '',
      price: 100,
      imageUrl: redUrl,
      images: [redUrl, blueUrl],
      category: 'All',
      categories: ['All'],
      rating: 0,
      reviews: 0,
      stock: 0,
      specs: [],
      options: [
        Option(id: 'o1', name: 'Red', imageUrls: const [redUrl, blueUrl]),
        Option(id: 'o2', name: 'Blue', imageUrls: const [blueUrl]),
      ],
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

    // Find the gallery's existing-image tiles by their "Xóa ảnh"
    // Semantics button and tap the FIRST one (the redUrl). The X
    // button sits in a Stack on top of each existing image, and the
    // Wrap orders them red then blue (matching `existingImages`).
    final removeButtons = find.bySemanticsLabel('Xóa ảnh');
    expect(removeButtons, findsNWidgets(2),
        reason: 'one X button per existing image');
    await tester.tap(removeButtons.first);
    await tester.pump();

    // Submit the dialog.
    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();

    // The dialog forwarded the removed URL to the VM.
    expect(vm.lastRemovedImageUrls, [redUrl]);

    // The submitted product has only blueUrl in the gallery.
    expect(vm.lastSubmitted, isNotNull);
    expect(vm.lastSubmitted!.images, [blueUrl]);

    // The "Red" option used to contain both URLs. redUrl must be
    // pruned; blueUrl stays because the admin only removed the red
    // one.
    expect(vm.lastSubmitted!.options, hasLength(2));
    expect(vm.lastSubmitted!.options[0].id, 'o1');
    expect(vm.lastSubmitted!.options[0].imageUrls, [blueUrl],
        reason: 'redUrl must be stripped from the Red option');
    // The "Blue" option only ever had blueUrl; sanity-check it
    // survives the prune untouched.
    expect(vm.lastSubmitted!.options[1].id, 'o2');
    expect(vm.lastSubmitted!.options[1].imageUrls, [blueUrl]);
  });
}
