import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../models/banner.dart';
import '../services/article_service.dart';

/// ViewModel for the home carousel banners and the admin "Bài viết" tab.
///
/// Holds the cached list of banner slides (loaded on app start so the
/// home screen renders without a spinner). Article CRUD happens
/// through this viewmodel too — the admin UI calls [createArticle],
/// [updateArticle], [deleteArticle] (and the matching banner methods)
/// and we keep the local list in sync.
class ArticlesViewModel extends ChangeNotifier {
  ArticlesViewModel({IArticleService? service})
      : _service = service ?? RealArticleService();

  final IArticleService _service;

  List<BannerSlide> _banners = const [];
  List<Article> _articles = const [];
  bool _isLoading = false;
  String? _error;

  /// True after [dispose] has run. The home-screen banner
  /// `load()` fires on app start; on web, hot-restart can tear
  /// the widget tree down before the HTTP response arrives. The
  /// late `notifyListeners()` then throws
  /// "ChangeNotifier used after being disposed" — see the
  /// matching guard in [HomeViewModel] / [SiteConfigViewModel]
  /// for the same fix.
  bool _disposed = false;

  List<BannerSlide> get banners => _banners;
  List<Article> get articles => _articles;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch the latest banner list. Safe to call multiple times.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      _banners = await _service.getBanners();
    } catch (e) {
      _error = 'Lỗi tải banner: $e';
    } finally {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  /// Admin: fetch every article (newest first). Used by the "Bài viết"
  /// tab list.
  Future<void> loadArticles() async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      _articles = await _service.listArticles();
      _isLoading = false;
      _notifyIfAlive();
    } catch (e) {
      _error = 'Lỗi tải bài viết: $e';
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  // -- Article CRUD --

  Future<bool> createArticle(Article article) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.createArticle(article);
      _articles = [saved, ..._articles];
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } catch (e) {
      _error = 'Lỗi tạo bài viết: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  Future<bool> updateArticle(Article article) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.updateArticle(article);
      _articles = [
        for (final a in _articles)
          if (a.id == saved.id) saved else a,
      ];
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } catch (e) {
      _error = 'Lỗi cập nhật bài viết: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  Future<bool> deleteArticle(String id) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      await _service.deleteArticle(id);
      _articles = _articles.where((a) => a.id != id).toList();
      // Banner FK cascades to NULL on the server, so we re-pull.
      _banners = await _service.getBanners();
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } catch (e) {
      _error = 'Lỗi xóa bài viết: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  // -- Banner CRUD --

  Future<bool> createBanner(BannerSlide slide) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.createBanner(slide);
      _banners = [..._banners, saved]
        ..sort((a, b) => a.ord.compareTo(b.ord));
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } catch (e) {
      _error = 'Lỗi tạo banner: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  Future<bool> updateBanner(BannerSlide slide) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.updateBanner(slide);
      _banners = [
        for (final b in _banners)
          if (b.id == saved.id) saved else b,
      ]..sort((a, b) => a.ord.compareTo(b.ord));
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } catch (e) {
      _error = 'Lỗi cập nhật banner: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  Future<bool> deleteBanner(String id) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      await _service.deleteBanner(id);
      _banners = _banners.where((b) => b.id != id).toList();
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } catch (e) {
      _error = 'Lỗi xóa banner: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  /// No-op once [dispose] has flipped [_disposed]. See
  /// [HomeViewModel._notifyIfAlive] for the full rationale.
  void _notifyIfAlive() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
