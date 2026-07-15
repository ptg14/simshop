import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:simshop/models/article.dart';
import 'package:simshop/models/banner.dart';
import 'package:simshop/models/category.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/views/admin/admin_articles/banner_dialog.dart';

/// In-memory product service — BannerDialog calls into
/// IProductService only when uploading the picked banner image,
/// which these tests never do.
class _FakeProductService implements IProductService {
  @override
  Future<List<Product>> getAllProducts() async => const [];
  @override
  Future<List<Product>> getProductsByCategory(String category) async => const [];
  @override
  Future<Product> getProductById(String id) async =>
      throw UnimplementedError();
  @override
  Future<List<Product>> searchProducts(String query, {int? limit}) async =>
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
  Future<Product> createProduct(Product product, {List<String>? removedImageUrls}) async => product;
  @override
  Future<Product> updateProduct(String id, Product product, {List<String>? removedImageUrls}) async => product;
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

void main() {
  // Pin a wide surface so the dialog fits naturally.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
      'BannerDialog: does not assert when banner.articleId points at an article not in the list',
      (tester) async {
    // Regression: DropdownButtonFormField<String?> asserts at build
    // time that exactly one item matches initialValue. When the
    // banner references an article the dialog's article list
    // doesn't carry (draft article hidden by a stale public-list
    // fetch, article deleted out from under the banner, malformed
    // payload), the assertion fired with
    //   "There should be exactly one item with [DropdownButton]'s
    //    value: 1784018224931000".
    // The dialog must instead drop the missing link and render the
    // dropdown on its fallback ("— Không liên kết —") so the admin
    // can still edit the banner.
    useWideSurface(tester);
    const url = 'https://example.test/img.jpg';
    const banner = BannerSlide(
      id: 'b-1',
      imageUrl: url,
      title: 'Banner',
      subtitle: '',
      ord: 0,
      // Points at an article that isn't in `articles` below.
      articleId: '1784018224931000',
    );
    final articles = <Article>[
      const Article(id: 'a-1', title: 'Khác'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Provider<IProductService>.value(
          value: _FakeProductService(),
          child: Center(
            child: BannerDialog(
              existing: banner,
              articles: articles,
              onSave: (_, __) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The dialog must build without throwing — the previous bug
    // surfaced as a build-time assertion that aborted this
    // pumpAndSettle.
    expect(find.text('Sửa banner'), findsOneWidget);

    // The "— Không liên kết —" sentinel item is rendered (the
    // fallback) — proves initialValue silently collapsed to null
    // instead of asserting.
    expect(find.text('— Không liên kết —'), findsOneWidget);
  });

  testWidgets(
      'BannerDialog: dedupes duplicate article ids so the dropdown does not assert',
      (tester) async {
    // Same assertion class, different root cause: two articles with
    // the same id in `articles` make DropdownButton find two items
    // with the same value and bail.
    useWideSurface(tester);
    const url = 'https://example.test/img.jpg';
    const banner = BannerSlide(
      id: 'b-1',
      imageUrl: url,
      title: 'Banner',
      subtitle: '',
      ord: 0,
      articleId: 'dup',
    );
    final articles = <Article>[
      const Article(id: 'dup', title: 'Lần 1'),
      const Article(id: 'dup', title: 'Lần 2'),
      const Article(id: 'a-1', title: 'Khác'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Provider<IProductService>.value(
          value: _FakeProductService(),
          child: Center(
            child: BannerDialog(
              existing: banner,
              articles: articles,
              onSave: (_, __) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sửa banner'), findsOneWidget);
    // The first occurrence of the duplicate id wins.
    expect(find.text('Lần 1'), findsOneWidget);
    expect(find.text('Lần 2'), findsNothing,
        reason: 'dedupe must drop the second occurrence so the dropdown does not double-emit');
  });

  testWidgets(
      'BannerDialog: selects the linked article when it is in the list',
      (tester) async {
    useWideSurface(tester);
    const url = 'https://example.test/img.jpg';
    const banner = BannerSlide(
      id: 'b-1',
      imageUrl: url,
      title: 'Banner',
      subtitle: '',
      ord: 0,
      articleId: 'a-1',
    );
    final articles = <Article>[
      const Article(id: 'a-1', title: 'Bài liên kết'),
      const Article(id: 'a-2', title: 'Bài khác'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Provider<IProductService>.value(
          value: _FakeProductService(),
          child: Center(
            child: BannerDialog(
              existing: banner,
              articles: articles,
              onSave: (_, __) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Sanity: the dialog builds and the linked article is rendered
    // on the dropdown's closed surface (the selected value). The
    // other dropdown items stay hidden inside the menu until the
    // user taps to open it — `find.text` only matches visible
    // widgets, so we limit the assertion to what the closed
    // dropdown actually shows.
    expect(find.text('Sửa banner'), findsOneWidget);
    expect(find.text('Bài liên kết'),
        findsOneWidget,
        reason: 'selected article shows on the closed dropdown');
  });
}
