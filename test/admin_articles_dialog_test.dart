import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/models/banner.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/viewmodels/articles_viewmodel.dart';
import 'package:simshop/views/admin/admin_articles.dart';

/// Minimal in-memory article service so the admin screen can be
/// pumped without hitting the network.
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

void main() {
  // Pin a wide surface so the admin layout uses NavigationRail-ish
  // widths and the dialog fits naturally.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openArticleDialog(WidgetTester tester) async {
    final vm = ArticlesViewModel(service: _FakeArticleService());
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<ArticlesViewModel>.value(
        value: vm,
        child: const Scaffold(body: AdminArticlesScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    // The "Thêm bài viết" button in the article section.
    await tester.tap(find.text('Thêm bài viết'));
    await tester.pumpAndSettle();
  }

  testWidgets('Article dialog has no Ảnh bìa (URL) text field', (tester) async {
    useWideSurface(tester);
    await openArticleDialog(tester);

    // The old TextField label must be gone.
    expect(find.text('Ảnh bìa (URL)'), findsNothing);
  });

  testWidgets('Article dialog has a "Chọn ảnh bìa" cover picker button',
      (tester) async {
    useWideSurface(tester);
    await openArticleDialog(tester);

    // The cover picker button should be present (mirrors the banner
    // dialog's "Chọn ảnh" pattern).
    expect(find.text('Chọn ảnh bìa'), findsOneWidget);
  });
}
