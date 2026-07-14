import 'package:flutter/foundation.dart';
import '../models/article.dart';
import '../models/banner.dart';
import '../services/_http_with_admin_token.dart';
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

  /// True after a write returned 401 "admin session required" (server
  /// restart, TTL elapsed, etc.). The admin shell watches this flag
  /// alongside [AdminViewModel.adminSessionExpired] and
  /// [SiteConfigViewModel.adminSessionExpired] and pops back to the
  /// auth gate so the user can re-authenticate. Mirrors the same
  /// pattern as those viewmodels — without it the user stays on the
  /// "Bài viết" tab, every retry keeps failing, and the only escape
  /// is to clear app data.
  ///
  /// The service layer throws [AdminSessionExpiredException] via
  /// [detectAdminSessionExpiry] in `_http_with_admin_token.dart` on
  /// the canonical wire shape `401 {"error":"admin session required"}`.
  /// We catch it explicitly so we can flip the flag *before* the
  /// generic error string overwrites the user-facing message with
  /// something unhelpful like
  /// "Lỗi tạo bài viết: AdminSessionExpiredException: ...".
  bool _adminSessionExpired = false;
  bool get adminSessionExpired => _adminSessionExpired;

  /// Force-clear the [adminSessionExpired] flag without performing
  /// any I/O. Called by [AdminShell] in [State.initState] when a
  /// fresh shell mounts after the user came back through the auth
  /// gate — see [AdminViewModel.clearAdminSessionExpired] for the
  /// full reasoning. Does NOT notify listeners for the same reason
  /// as [AdminViewModel] (the shell is still inside initState, so a
  /// listener rebuild would be a "setState during build" violation).
  void clearAdminSessionExpired() {
    _adminSessionExpired = false;
  }

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

  /// [oldCoverURL] is the cover_image_url the row held before this
  /// create/update. On update it lets the backend diff the URL and
  /// best-effort delete the previous file after the PUT commits; it
  /// is plumbed through create for signature symmetry (no-op on create).
  /// [removedImageUrls] is unused today but reserved for future
  /// multi-image galleries.
  Future<bool> createArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.createArticle(
        article,
        oldCoverURL: oldCoverURL,
        removedImageUrls: removedImageUrls,
      );
      _articles = [saved, ..._articles];
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } on AdminSessionExpiredException catch (e) {
      // Cached Bearer token was rejected. Flip the flag so the
      // admin shell pops back to [AdminAuthGate]; the service has
      // already cleared the dead token from local storage.
      // Same pattern as [SiteConfigViewModel.update] / [AdminViewModel].
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
    } catch (e) {
      _error = 'Lỗi tạo bài viết: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  Future<bool> updateArticle(
    Article article, {
    String? oldCoverURL,
    List<String>? removedImageUrls,
  }) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.updateArticle(
        article,
        oldCoverURL: oldCoverURL,
        removedImageUrls: removedImageUrls,
      );
      _articles = [
        for (final a in _articles)
          if (a.id == saved.id) saved else a,
      ];
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
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
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
    } catch (e) {
      _error = 'Lỗi xóa bài viết: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  // -- Banner CRUD --

  /// [oldImageURL] is the image_url the row held before this
  /// create/update. On update the backend diffs the URL and
  /// best-effort deletes the previous file after the PUT commits; it
  /// is plumbed through create for signature symmetry (no-op on create).
  /// [removedImageUrls] is unused for single-image banners today.
  Future<bool> createBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.createBanner(
        slide,
        oldImageURL: oldImageURL,
        removedImageUrls: removedImageUrls,
      );
      _banners = [..._banners, saved]
        ..sort((a, b) => a.ord.compareTo(b.ord));
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
    } catch (e) {
      _error = 'Lỗi tạo banner: $e';
      _isLoading = false;
      _notifyIfAlive();
      return false;
    }
  }

  Future<bool> updateBanner(
    BannerSlide slide, {
    String? oldImageURL,
    List<String>? removedImageUrls,
  }) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      final saved = await _service.updateBanner(
        slide,
        oldImageURL: oldImageURL,
        removedImageUrls: removedImageUrls,
      );
      _banners = [
        for (final b in _banners)
          if (b.id == saved.id) saved else b,
      ]..sort((a, b) => a.ord.compareTo(b.ord));
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
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
    } on AdminSessionExpiredException catch (e) {
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
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
