import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/i_product_service.dart';
import 'package:simshop/services/store_service.dart';
import 'package:simshop/viewmodels/articles_viewmodel.dart';
import 'package:simshop/viewmodels/home_viewmodel.dart';
import 'package:simshop/viewmodels/site_config_viewmodel.dart';
import 'package:simshop/views/home_screen.dart';
import 'package:simshop/widgets/site_info_footer.dart';

/// In-memory [IProductService] that drives the home screen into the
/// empty-filter branch: the only product on disk is tagged "Phone"
/// (no Large = "Clothing"), so applying the Clothing + Shirt + Pants
/// AND-filter yields zero matches while the raw `_products` list
/// stays non-empty.
class _EmptyFilterProductService implements IProductService {
  @override
  Future<List<Product>> getAllProducts() async => <Product>[
        Product(
          id: 'p-phone-1',
          name: 'Phone',
          description: '',
          price: 0,
          imageUrl: '',
          category: 'Phone',
          categories: ['Phone'],
          rating: 0,
          specs: const [],
        ),
      ];

  @override
  Future<List<String>> getLargeCategories() async => const ['Clothing'];

  @override
  Future<List<Category>> getCategoriesWithParent() async => <Category>[
        Category(name: 'Shirt', largeCategory: 'Clothing'),
        Category(name: 'Pants', largeCategory: 'Clothing'),
      ];

  // ---- Unused endpoints. Throw so an accidental call surfaces as
  // a loud test failure instead of silently passing.
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
  Future<void> createCategoryWithParent(
          String name, String largeCategoryName) async =>
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

/// Minimal [IStoreService] for the footer. The home screen only
/// reads via [SiteConfigViewModel.load] → [getStoreInfo], so we
/// just return the seeded value. [updateStoreInfo] is unused in
/// this test path.
class _RecordingStoreService implements IStoreService {
  _RecordingStoreService(this._info);

  final StoreInfo _info;

  @override
  Future<StoreInfo> getStoreInfo() async => _info;

  @override
  Future<StoreInfo> updateStoreInfo(StoreInfo info,
          {String? oldBannerUrl}) async =>
      info;
}

void main() {
  testWidgets(
      'HomeScreen renders SiteInfoFooter exactly once when the filter '
      'matches zero products — regression for the doubled store banner',
      (tester) async {
    // Pre-seed HomeViewModel with a Clothing Large whose Shirt+Pants
    // AND-filter matches no product. After `initialize()`,
    // `vm.products` is empty but `hasLoadedProducts` is true, so
    // HomeScreen renders _buildLoaded → _buildEmpty. The empty
    // branch used to embed its own SiteInfoFooter on top of the
    // outer Column's footer, doubling the banner + store info.
    final homeVm = HomeViewModel(
      productService: _EmptyFilterProductService(),
    );
    await homeVm.initialize();
    homeVm.selectLarge('Clothing');
    homeVm.toggleSub('Shirt');
    homeVm.toggleSub('Pants');
    expect(homeVm.products, isEmpty,
        reason: 'test fixture must produce an empty filter');
    expect(homeVm.hasLoadedProducts, isTrue,
        reason: 'screen should be in the loaded branch, not skeleton');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HomeViewModel>.value(value: homeVm),
          ChangeNotifierProvider<ArticlesViewModel>(
            create: (_) => ArticlesViewModel(),
          ),
          ChangeNotifierProvider<SiteConfigViewModel>(
            create: (_) => SiteConfigViewModel(
              service: _RecordingStoreService(const StoreInfo.empty()),
            )..load(),
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Let the post-frame data wave + first paint settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // The empty-state copy must be visible…
    expect(find.text('Không tìm thấy sản phẩm nào'), findsOneWidget,
        reason: 'empty-state branch should be on screen');
    // …and the footer (banner + store info card) must appear exactly
    // once. Before the fix this finder matched twice — the empty
    // widget's footer stacked on top of the outer Column's footer.
    expect(find.byType(SiteInfoFooter), findsOneWidget,
        reason: 'SiteInfoFooter must render exactly once, not twice');
  });
}
