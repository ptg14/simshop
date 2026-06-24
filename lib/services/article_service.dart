import '../models/article.dart';
import '../models/banner.dart';

/// Article-with-products payload returned by [IArticleService.getArticle].
///
/// Slice 2's backend joins the products referenced by [Article.productIds]
/// so the article screen can render product chips in one round trip.
class ArticleWithProducts {
  const ArticleWithProducts({required this.article, required this.products});

  final Article article;
  final List<ProductStub> products;
}

/// Minimal product shape for chip rendering. The full [Product] model is
/// in `lib/models/product.dart` — we only need `id`, `name`, and
/// `imageUrl` to render a chip, so a stub avoids re-fetching the full
/// record. The detail screen re-fetches by id when the chip is tapped.
class ProductStub {
  const ProductStub({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  factory ProductStub.fromJson(Map<String, dynamic> json) => ProductStub(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        imageUrl: json['image_url'] as String? ?? '',
      );

  final String id;
  final String name;
  final String imageUrl;
}

/// Contract for the articles + banner slides feature.
///
/// Slice 1: interface only (no real implementation). Slice 2 + 3
/// provide `RealArticleService` against the backend.
abstract class IArticleService {
  /// Fetches the home carousel slides, ordered by `ord`.
  Future<List<BannerSlide>> getBanners();

  /// Fetches a single article plus the products it mentions (joined
  /// server-side). Returns `null` if the article does not exist.
  Future<ArticleWithProducts?> getArticle(String id);

  /// Admin: create a new article. Returns the persisted record
  /// (with server-assigned fields if any).
  Future<Article> createArticle(Article article);

  /// Admin: replace the record at [article.id].
  Future<Article> updateArticle(Article article);

  /// Admin: delete. Server cascades the banner FK to NULL.
  Future<void> deleteArticle(String id);

  /// Admin: create a banner slide. [BannerSlide.id] is ignored; the
  /// server assigns one.
  Future<BannerSlide> createBanner(BannerSlide slide);

  /// Admin: replace the record at [slide.id].
  Future<BannerSlide> updateBanner(BannerSlide slide);

  /// Admin: delete.
  Future<void> deleteBanner(String id);
}
