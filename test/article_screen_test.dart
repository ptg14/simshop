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

  // Bug 3: user asked for products to render as a *list* (one
  // product per row, vertically stacked), not as a chip wrap.
  // The previous implementation used ActionChips inside a Wrap,
  // which read as a tag cloud rather than a list. This test pins
  // the layout: products in a Column with monotonically increasing
  // y-coords and a non-trivial vertical gap.
  testWidgets('ArticleScreen: products render as a vertical list, not chips',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const article = Article(
      id: 'a-1',
      title: 'Khuyến mãi tháng 6',
      body: 'Nội dung ngắn.',
    );
    final svc = _FakeArticleService(articles: [
      article,
    ], found: const ArticleWithProducts(
      article: article,
      products: [
        ProductStub(id: 'p-1', name: 'Áo thun', imageUrl: ''),
        ProductStub(id: 'p-2', name: 'Quần jeans', imageUrl: ''),
        ProductStub(id: 'p-3', name: 'Giày thể thao', imageUrl: ''),
      ],
    ));

    await tester.pumpWidget(_wrap(
      const ArticleScreen(articleId: 'a-1'),
      svc,
    ));
    await tester.pumpAndSettle();

    // All three products render.
    expect(find.text('Áo thun'), findsOneWidget);
    expect(find.text('Quần jeans'), findsOneWidget);
    expect(find.text('Giày thể thao'), findsOneWidget);

    // No ActionChip at all (the previous chip-wrap implementation).
    expect(find.byType(ActionChip), findsNothing,
        reason: 'products must render as a list, not a chip wrap');

    // Vertical layout: each product is below the previous one with
    // a non-trivial gap (>8px). This is the "list" the user asked
    // for; chips wrap horizontally and would fail this check.
    final y1 = tester.getTopLeft(find.text('Áo thun')).dy;
    final y2 = tester.getTopLeft(find.text('Quần jeans')).dy;
    final y3 = tester.getTopLeft(find.text('Giày thể thao')).dy;
    expect(y2, greaterThan(y1),
        reason: 'product 2 must be below product 1');
    expect(y3, greaterThan(y2),
        reason: 'product 3 must be below product 2');
    expect(y2 - y1, greaterThan(8),
        reason: 'rows must be visually separated, not stacked');
    expect(y3 - y2, greaterThan(8),
        reason: 'rows must be visually separated, not stacked');
  });

  // Bug 3: user asked for the body content to be left-aligned.
  // MarkdownBody uses center alignment for some block elements by
  // default in older versions, so we pin the Column containing the
  // MarkdownBody to start-align. The wrapping Column already uses
  // crossAxisAlignment: start (see lib/views/article_screen.dart:97),
  // so this test is a regression guard.
  testWidgets('ArticleScreen: body and section headers are left-aligned',
      (tester) async {
    const article = Article(
      id: 'a-1',
      title: 'Khuyến mãi tháng 6',
      body: '## Điểm nội bật\n\nNội dung trái.',
    );
    final svc = _FakeArticleService(articles: [article]);

    await tester.pumpWidget(_wrap(
      const ArticleScreen(articleId: 'a-1'),
      svc,
    ));
    await tester.pumpAndSettle();

    // Title and section header x positions must equal the body's
    // left edge (i.e. they all start at the same x — left aligned).
    final titleX = tester.getTopLeft(find.text('Khuyến mãi tháng 6')).dx;
    final headingX = tester.getTopLeft(find.text('Điểm nội bật')).dx;
    final bodyX = tester.getTopLeft(find.text('Nội dung trái.')).dx;
    expect((titleX - headingX).abs(), lessThanOrEqualTo(1),
        reason: 'heading must share title x (left-aligned)');
    expect((titleX - bodyX).abs(), lessThanOrEqualTo(1),
        reason: 'body must share title x (left-aligned)');
  });
}
