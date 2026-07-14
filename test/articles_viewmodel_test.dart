import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/models/banner.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/viewmodels/articles_viewmodel.dart';

/// In-memory service used to drive the viewmodel in tests without
/// touching the network.
class _FakeArticleService implements IArticleService {
  // [articles] is not used by the tests in this file (they only cover
  // the banner path), but a sibling `_FakeArticleService` in
  // `article_screen_test.dart` does pass `articles:` — keeping the
  // parameter here matches that shape so future tests can swap a
  // single fake across files without changing the constructor.
  // ignore: unused_element_parameter
  _FakeArticleService({this.banners = const [], this.articles = const []});

  List<BannerSlide> banners;
  List<Article> articles;
  bool shouldFail = false;
  /// When true, every write method throws
  /// [AdminSessionExpiredException] (mirrors the real service
  /// layer's behavior on a stale 401). Used to pin the viewmodel's
  /// adminSessionExpired-flag flip without spinning up the network.
  bool shouldThrowAdminSessionExpired = false;
  int getBannersCount = 0;
  int createBannerCount = 0;

  @override
  Future<List<BannerSlide>> getBanners() async {
    getBannersCount++;
    if (shouldFail) throw Exception('boom');
    return banners;
  }

  @override
  Future<List<Article>> listArticles() async {
    if (shouldFail) throw Exception('boom');
    return articles;
  }

  @override
  Future<ArticleWithProducts?> getArticle(String id) async {
    final found = articles.where((a) => a.id == id).toList();
    if (found.isEmpty) return null;
    return ArticleWithProducts(article: found.first, products: const []);
  }

  @override
  Future<Article> createArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    final saved = article.copyWith();
    articles = [saved, ...articles];
    return saved;
  }

  @override
  Future<Article> updateArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    articles = [
      for (final a in articles)
        if (a.id == article.id) article else a,
    ];
    return article;
  }

  @override
  Future<void> deleteArticle(String id) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    articles = articles.where((a) => a.id != id).toList();
  }

  @override
  Future<BannerSlide> createBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async {
    createBannerCount++;
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    banners = [...banners, slide]..sort((a, b) => a.ord.compareTo(b.ord));
    return slide;
  }

  @override
  Future<BannerSlide> updateBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    banners = [
      for (final b in banners)
        if (b.id == slide.id) slide else b,
    ]..sort((a, b) => a.ord.compareTo(b.ord));
    return slide;
  }

  @override
  Future<void> deleteBanner(String id) async {
    if (shouldThrowAdminSessionExpired) {
      throw AdminSessionExpiredException(
        'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
      );
    }
    if (shouldFail) throw Exception('boom');
    banners = banners.where((b) => b.id != id).toList();
  }
}

void main() {
  group('ArticlesViewModel', () {
    test('load() exposes banners and notifies listeners', () async {
      final fake = _FakeArticleService(banners: [
        const BannerSlide(id: 'b1', imageUrl: 'http://x/1.jpg', ord: 0),
      ]);
      final vm = ArticlesViewModel(service: fake);

      var notifications = 0;
      vm.addListener(() => notifications++);

      await vm.load();

      expect(vm.banners.length, 1);
      expect(vm.banners.first.id, 'b1');
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
      expect(fake.getBannersCount, 1);
      expect(notifications, greaterThanOrEqualTo(2));
    });

    test('createBanner appends and keeps list sorted by ord', () async {
      final fake = _FakeArticleService();
      final vm = ArticlesViewModel(service: fake);

      await vm.load();
      final ok1 = await vm.createBanner(
        const BannerSlide(id: 'b2', imageUrl: 'http://x/2.jpg', ord: 5),
      );
      final ok2 = await vm.createBanner(
        const BannerSlide(id: 'b3', imageUrl: 'http://x/3.jpg', ord: 1),
      );

      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(vm.banners.map((b) => b.id).toList(), ['b3', 'b2']);
    });

    test('deleteBanner removes the row', () async {
      final fake = _FakeArticleService(banners: [
        const BannerSlide(id: 'b1', imageUrl: 'http://x/1.jpg', ord: 0),
      ]);
      final vm = ArticlesViewModel(service: fake);
      await vm.load();

      final ok = await vm.deleteBanner('b1');
      expect(ok, isTrue);
      expect(vm.banners, isEmpty);
    });

    test('failure sets error and returns false', () async {
      final fake = _FakeArticleService();
      fake.shouldFail = true;
      final vm = ArticlesViewModel(service: fake);

      final ok = await vm.createBanner(
        const BannerSlide(id: 'b1', imageUrl: 'http://x/1.jpg', ord: 0),
      );

      expect(ok, isFalse);
      expect(vm.error, isNotNull);
    });

    test(
      'createArticle flips adminSessionExpired when the service throws '
      'AdminSessionExpiredException (cached token is dead)',
      () async {
        // The fix: when the article service surfaces a stale 401, the
        // viewmodel must flip adminSessionExpired so AdminShell can
        // route back to AdminAuthGate. Without this branch the user
        // sees "Lỗi tạo bài viết: AdminSessionExpiredException: ..."
        // — generic and unhelpful, with no path back to auth.
        final fake = _FakeArticleService();
        fake.shouldThrowAdminSessionExpired = true;
        final vm = ArticlesViewModel(service: fake);

        final ok = await vm.createArticle(
          const Article(id: '', title: 'T', body: ''),
        );

        expect(ok, isFalse);
        expect(vm.adminSessionExpired, isTrue,
            reason: 'AdminShell watches this flag (alongside the other '
                'three admin-write viewmodels) and pops the user back '
                'to AdminAuthGate.');
        expect(vm.error, contains('Phiên quản trị đã hết hạn'));
      },
    );

    test(
      'clearAdminSessionExpired() resets the flag without I/O',
      () async {
        final fake = _FakeArticleService();
        fake.shouldThrowAdminSessionExpired = true;
        final vm = ArticlesViewModel(service: fake);
        await vm.createArticle(const Article(id: '', title: 'T', body: ''));
        expect(vm.adminSessionExpired, isTrue);

        // Called by AdminShell.initState on every fresh mount.
        vm.clearAdminSessionExpired();
        expect(vm.adminSessionExpired, isFalse);
      },
    );
  });
}
