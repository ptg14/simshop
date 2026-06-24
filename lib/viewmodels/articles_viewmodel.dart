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

  List<BannerSlide> get banners => _banners;
  List<Article> get articles => _articles;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch the latest banner list. Safe to call multiple times.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _banners = await _service.getBanners();
    } catch (e) {
      _error = 'Lỗi tải banner: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Admin: fetch every article (newest first). Used by the "Bài viết"
  /// tab list.
  Future<void> loadArticles() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _articles = await _service.listArticles();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Lỗi tải bài viết: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // -- Article CRUD --

  Future<bool> createArticle(Article article) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _service.createArticle(article);
      _articles = [saved, ..._articles];
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi tạo bài viết: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateArticle(Article article) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _service.updateArticle(article);
      _articles = [
        for (final a in _articles)
          if (a.id == saved.id) saved else a,
      ];
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi cập nhật bài viết: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteArticle(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.deleteArticle(id);
      _articles = _articles.where((a) => a.id != id).toList();
      // Banner FK cascades to NULL on the server, so we re-pull.
      _banners = await _service.getBanners();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi xóa bài viết: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // -- Banner CRUD --

  Future<bool> createBanner(BannerSlide slide) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _service.createBanner(slide);
      _banners = [..._banners, saved]
        ..sort((a, b) => a.ord.compareTo(b.ord));
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi tạo banner: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateBanner(BannerSlide slide) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final saved = await _service.updateBanner(slide);
      _banners = [
        for (final b in _banners)
          if (b.id == saved.id) saved else b,
      ]..sort((a, b) => a.ord.compareTo(b.ord));
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi cập nhật banner: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteBanner(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.deleteBanner(id);
      _banners = _banners.where((b) => b.id != id).toList();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi xóa banner: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
