import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/models/banner.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/articles_viewmodel.dart';
import 'package:simshop/views/admin/admin_articles.dart';

class _FakeArticleService implements IArticleService {
  @override
  Future<List<BannerSlide>> getBanners() async => const [];
  @override
  Future<ArticleWithProducts?> getArticle(String id) async => null;
  @override
  Future<List<Article>> listArticles() async => const [];
  @override
  Future<Article> createArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async =>
      article;
  @override
  Future<Article> updateArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async =>
      article;
  @override
  Future<void> deleteArticle(String id) async {}
  @override
  Future<BannerSlide> createBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async =>
      slide;
  @override
  Future<BannerSlide> updateBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async =>
      slide;
  @override
  Future<void> deleteBanner(String id) async {}
}

/// Product service that returns canned results for search and ignores
/// every other call. Used so the article dialog's click-to-pick
/// product picker can be tested without a real backend.
class _FakeProductService implements IProductService {
  _FakeProductService({this.byQuery = const {}});

  /// Map of query substring -> matching products. Pick the first key
  /// that is contained in the query (case-insensitive).
  final Map<String, List<Product>> byQuery;

  int searchCallCount = 0;
  String lastQuery = '';

  @override
  Future<List<Product>> searchProducts(String query) async {
    searchCallCount++;
    lastQuery = query;
    final q = query.toLowerCase();
    for (final entry in byQuery.entries) {
      if (q.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return const [];
  }

  // Unused stubs — match the IProductService contract so the VM
  // (which holds this service) can be constructed in tests.
  @override
  Future<List<Product>> getAllProducts() async => const [];
  @override
  Future<List<Product>> getProductsByCategory(String category) async => const [];
  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError('not used');
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

Product _makeProduct(String id, String name) => Product(
      id: id,
      name: name,
      description: '',
      price: 100,
      imageUrl: '',
      category: 'All',
      categories: ['All'],
      rating: 0,
      reviews: 0,
      stock: 0,
      specs: [],
    );

void main() {
  // Pin a wide surface so the admin layout uses NavigationRail-ish
  // widths and the dialog fits naturally.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'Article dialog: picker dialog calls searchProducts and chip appears',
      (tester) async {
    useWideSurface(tester);

    final productSvc = _FakeProductService(
      byQuery: {
        'áo': [_makeProduct('p-1', 'Áo thun nam')],
      },
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<IProductService>.value(value: productSvc),
        ChangeNotifierProvider<ArticlesViewModel>(
          create: (_) => ArticlesViewModel(
            service: _FakeArticleService(),
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AdminArticlesScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Open the article dialog.
    await tester.tap(find.text('Thêm bài viết'));
    await tester.pumpAndSettle();

    // Open the picker dialog.
    await tester.tap(find.text('Chọn sản phẩm'));
    await tester.pumpAndSettle();

    // Sanity: picker dialog is visible with its search field.
    expect(find.text('Tìm kiếm'), findsOneWidget);

    // Type the query. The picker dialog uses its own _queryCtrl;
    // find the LAST TextField because the article dialog also has one
    // (for title) which is hidden under the dialog.
    final queryField = find.byType(TextField).last;
    await tester.enterText(queryField, 'áo');
    // Wait past the debounce (200ms).
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // The fake was hit and returned the canned product.
    expect(productSvc.searchCallCount, greaterThan(0));
    expect(productSvc.lastQuery, 'áo');

    // The fake returned one product — tap it.
    expect(find.text('Áo thun nam'), findsOneWidget);
    await tester.tap(find.text('Áo thun nam'));
    await tester.pumpAndSettle();

    // Picker closed; chip with the product name appears in the
    // article dialog.
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.descendant(
      of: find.byType(InputChip),
      matching: find.text('Áo thun nam'),
    ), findsOneWidget);
  });
}
