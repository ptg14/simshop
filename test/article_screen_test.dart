import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/models/banner.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/views/article_screen.dart';

/// In-memory service so tests don't touch the network. The article
/// returned for id 'a-1' includes a product stub so the chip rendering
/// path is exercised too.
class _FakeArticleService implements IArticleService {
  _FakeArticleService({this.found, this.articles = const []});

  ArticleWithProducts? found;
  final List<Article> articles;

  @override
  Future<ArticleWithProducts?> getArticle(String id) async {
    if (id == 'a-2') return null;
    return found ??
        ArticleWithProducts(
          article: articles.firstWhere((a) => a.id == id),
          products: const [
            ProductStub(id: 'p-1', name: 'Áo thun', imageUrl: ''),
          ],
        );
  }

  @override
  Future<List<BannerSlide>> getBanners() async => const [];
  @override
  Future<List<Article>> listArticles() async => articles;
  @override
  Future<Article> createArticle(Article article) async => article;
  @override
  Future<Article> updateArticle(Article article) async => article;
  @override
  Future<void> deleteArticle(String id) async {}
  @override
  Future<BannerSlide> createBanner(BannerSlide slide) async => slide;
  @override
  Future<BannerSlide> updateBanner(BannerSlide slide) async => slide;
  @override
  Future<void> deleteBanner(String id) async {}
}

Widget _wrap(Widget child, IArticleService service) => MaterialApp(
      home: Provider<IArticleService>.value(
        value: service,
        child: child,
      ),
    );

void main() {
  testWidgets('ArticleScreen renders title, markdown and product chips',
      (tester) async {
    const article = Article(
      id: 'a-1',
      title: 'Khuyến mãi tháng 6',
      body: '## Điểm nổi bật\n\nGiảm **30%** cho tất cả sản phẩm.',
    );
    final svc = _FakeArticleService(articles: [article]);

    await tester.pumpWidget(_wrap(
      const ArticleScreen(articleId: 'a-1'),
      svc,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Khuyến mãi tháng 6'), findsOneWidget);
    expect(find.text('Điểm nổi bật'), findsOneWidget);
    expect(find.text('Sản phẩm nhắc đến'), findsOneWidget);
    expect(find.text('Áo thun'), findsOneWidget);
  });

  testWidgets('ArticleScreen shows deleted state when getArticle returns null',
      (tester) async {
    final svc = _FakeArticleService(found: null);
    await tester.pumpWidget(_wrap(
      const ArticleScreen(articleId: 'a-2'),
      svc,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bài viết đã bị xóa'), findsOneWidget);
  });

  // Regression: the cover image (when present) must render *before* the
  // title, so the article reads as Banner → Body → Products. This pins
  // the order at `lib/views/article_screen.dart:99-151` against future
  // refactors that might swap the layout.
  testWidgets('ArticleScreen renders cover image before the title',
      (tester) async {
    const article = Article(
      id: 'a-1',
      title: 'Khuyến mãi tháng 6',
      body: 'Nội dung ngắn.',
      coverImageUrl: 'https://example.test/cover.jpg',
    );
    final svc = _FakeArticleService(articles: [article]);

    await tester.pumpWidget(_wrap(
      const ArticleScreen(articleId: 'a-1'),
      svc,
    ));
    await tester.pumpAndSettle();

    // The cover image (Image.network) must be vertically above the
    // title text. We compare widget top coordinates (dy in screen
    // space). The 1px tolerance guards against sub-pixel rounding.
    final coverTop = tester.getTopLeft(find.byType(Image)).dy;
    final titleTop = tester.getTopLeft(find.text('Khuyến mãi tháng 6')).dy;
    expect(coverTop, lessThan(titleTop),
        reason: 'cover image must render above the title');
  });
}
