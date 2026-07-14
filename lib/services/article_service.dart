import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/article.dart';
import '../models/banner.dart';
import '_http_with_admin_token.dart';
import 'admin_auth_service.dart';

/// Article-with-products payload returned by [IArticleService.getArticle].
///
/// The backend joins the products referenced by [Article.productIds] so
/// the article screen can render product chips in one round trip.
class ArticleWithProducts {
  const ArticleWithProducts({required this.article, required this.products});

  factory ArticleWithProducts.fromJson(Map<String, dynamic> json) =>
      ArticleWithProducts(
        article: Article.fromJson(json['article'] as Map<String, dynamic>),
        products: ((json['products'] as List<dynamic>?) ?? const [])
            .map((e) => ProductStub.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final Article article;
  final List<ProductStub> products;
}

/// Minimal product shape for chip rendering.
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
abstract class IArticleService {
  /// Fetches the home carousel slides, ordered by `ord`.
  Future<List<BannerSlide>> getBanners();

  /// Fetches a single article plus the products it mentions (joined
  /// server-side). Returns `null` if the article does not exist.
  Future<ArticleWithProducts?> getArticle(String id);

  /// Admin: create a new article. Returns the persisted record.
  ///
  /// [oldCoverURL] / [removedImageUrls] are accepted for symmetry with
  /// the update path but are no-op on create: there is no pre-existing
  /// cover image to diff against on a brand-new article.
  Future<Article> createArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  });

  /// Admin: replace the record at [article.id].
  ///
  /// Pass the cover_image_url the row held before this update as
  /// [oldCoverURL]; when [article.coverImageUrl] differs the previous
  /// file is best-effort deleted from disk after the PUT commits.
  /// [removedImageUrls] is unused for articles today but reserved for
  /// future galleries (pass `null` to skip).
  Future<Article> updateArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  });

  /// Admin: delete. Server cascades the banner FK to NULL and
  /// best-effort deletes the cover image file.
  Future<void> deleteArticle(String id);

  /// Admin: create a banner slide.
  ///
  /// [oldImageURL] / [removedImageUrls] are accepted for symmetry
  /// with the update path but are no-op on create.
  Future<BannerSlide> createBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  });

  /// Admin: replace the record at [slide.id].
  ///
  /// Pass the image_url the row held before this update as
  /// [oldImageURL]; when [slide.imageUrl] differs the previous file
  /// is best-effort deleted from disk after the PUT commits.
  /// [removedImageUrls] is unused for banners today (pass `null`).
  Future<BannerSlide> updateBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  });

  /// Admin: delete.
  Future<void> deleteBanner(String id);

  /// Admin: list every article (newest first). Used by the admin
  /// "Bài viết" tab.
  Future<List<Article>> listArticles();
}

/// Real implementation that talks to the Go backend API.
class RealArticleService implements IArticleService {
  RealArticleService({
    String? baseUrl,
    http.Client? client,
    IAdminAuthService? authService,
  })  : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _client = client ?? http.Client(),
        _auth = authService;

  final String _baseUrl;
  final http.Client _client;
  // Optional — when present, admin write endpoints attach the
  // bearer token. Optional so unit tests don't need SharedPreferences.
  final IAdminAuthService? _auth;

  Uri _bannersUri() => Uri.parse('$_baseUrl/api/banners');
  Uri _bannerUri(String id) => Uri.parse('$_baseUrl/api/banners/$id');
  Uri _articlesUri() => Uri.parse('$_baseUrl/api/articles');
  Uri _articleUri(String id) => Uri.parse('$_baseUrl/api/articles/$id');

  Future<List<T>> _decodeList<T>(
    http.Response response,
    String field,
    T Function(Map<String, dynamic>) build,
  ) async {
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final raw = body[field] as List<dynamic>? ?? const [];
    return raw.map((e) => build(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<BannerSlide>> getBanners() async {
    final response = await _client.get(_bannersUri());
    return _decodeList(response, 'banners', BannerSlide.fromJson);
  }

  @override
  Future<ArticleWithProducts?> getArticle(String id) async {
    final response = await _client.get(_articleUri(id));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Request failed (${response.statusCode})');
    }
    return ArticleWithProducts.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<Article> createArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await _client.post(
      _articlesUri(),
      headers: headers,
      body: _encodeArticleBody(
        article,
        removedImageUrls: removedImageUrls,
      ),
    );
    // Mirror product_service.createProduct: clear the dead token on
    // a stale-session 401 so the admin can re-authenticate via
    // AdminAuthGate. Without this the dead token stays in
    // SharedPreferences and every subsequent write keeps failing
    // with the same generic message and no path back to the gate.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Create article failed (${response.statusCode})');
    }
    return Article.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<Article> updateArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await _client.put(
      _articleUri(article.id),
      headers: headers,
      body: _encodeArticleBody(
        article,
        oldCoverURL: oldCoverURL,
        removedImageUrls: removedImageUrls,
      ),
    );
    // Detect stale session — see createArticle above for context.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 200) {
      throw Exception('Update article failed (${response.statusCode})');
    }
    return Article.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }

  /// Attach [removed_image_urls] and (only when provided) [old_cover_url]
  /// to the article JSON body. Both fields are optional — the backend
  /// treats their absence as back-compat (no-op cleanup).
  String _encodeArticleBody(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) {
    final map = article.toJson();
    if (removedImageUrls != null && removedImageUrls.isNotEmpty) {
      map['removed_image_urls'] = removedImageUrls;
    }
    if (oldCoverURL != null && oldCoverURL.isNotEmpty) {
      map['old_cover_url'] = oldCoverURL;
    }
    return json.encode(map);
  }

  @override
  Future<void> deleteArticle(String id) async {
    final response = await _client.delete(_articleUri(id),
        headers: await withAdminAuth(_auth, const {}));
    // Detect stale session — see createArticle above for context.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Delete article failed (${response.statusCode})');
    }
  }

  @override
  Future<BannerSlide> createBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await _client.post(
      _bannersUri(),
      headers: headers,
      body: _encodeBannerBody(
        slide,
        removedImageUrls: removedImageUrls,
      ),
    );
    // Detect stale session — see createArticle above for context.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Create banner failed (${response.statusCode})');
    }
    return BannerSlide.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<BannerSlide> updateBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await _client.put(
      _bannerUri(slide.id),
      headers: headers,
      body: _encodeBannerBody(
        slide,
        oldImageURL: oldImageURL,
        removedImageUrls: removedImageUrls,
      ),
    );
    // Detect stale session — see createArticle above for context.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 200) {
      throw Exception('Update banner failed (${response.statusCode})');
    }
    return BannerSlide.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }

  /// Attach [removed_image_urls] and (only when provided) [old_image_url]
  /// to the banner JSON body. Both fields are optional — the backend
  /// treats their absence as back-compat (no-op cleanup).
  String _encodeBannerBody(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) {
    final map = slide.toJson();
    if (removedImageUrls != null && removedImageUrls.isNotEmpty) {
      map['removed_image_urls'] = removedImageUrls;
    }
    if (oldImageURL != null && oldImageURL.isNotEmpty) {
      map['old_image_url'] = oldImageURL;
    }
    return json.encode(map);
  }

  @override
  Future<void> deleteBanner(String id) async {
    final response = await _client.delete(_bannerUri(id),
        headers: await withAdminAuth(_auth, const {}));
    // Detect stale session — see createArticle above for context.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Delete banner failed (${response.statusCode})');
    }
  }

  @override
  Future<List<Article>> listArticles() async {
    final response = await _client.get(_articlesUri());
    return _decodeList(response, 'articles', Article.fromJson);
  }
}
