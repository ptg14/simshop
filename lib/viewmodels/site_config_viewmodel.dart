import 'package:flutter/foundation.dart';
import '../models/store_info.dart';
import '../services/_http_with_admin_token.dart';
import '../services/store_service.dart';

/// ViewModel for the singleton site config.
///
/// Exposes a single [StoreInfo] to both admin (for editing) and
/// home/product detail (for display). Loading and error state are
/// tracked so the UI can show progress + error feedback.
class SiteConfigViewModel extends ChangeNotifier {
  SiteConfigViewModel({IStoreService? service})
      : _service = service ?? RealStoreService();

  final IStoreService _service;

  StoreInfo _info = const StoreInfo();
  bool _isLoading = false;
  String? _error;

  /// True after [dispose] has run. The initial `load()` in
  /// `main()` fires on app start; on web, hot-restart can tear
  /// the widget tree down before the HTTP response arrives. The
  /// late `notifyListeners()` then throws
  /// "ChangeNotifier used after being disposed" — see the matching
  /// guard in [HomeViewModel] / [ArticlesViewModel] for the same
  /// fix.
  bool _disposed = false;

  /// True after a write returned 401 "admin session required".
  /// The admin shell watches this flag (alongside
  /// [AdminViewModel.adminSessionExpired]) and pops back to the
  /// auth gate so the user can re-authenticate. Mirrors the
  /// same pattern as [AdminViewModel] — without it the user
  /// stays on the settings screen, every retry keeps failing,
  /// and the only escape is to clear app data.
  bool _adminSessionExpired = false;
  bool get adminSessionExpired => _adminSessionExpired;

  /// Force-clear the [adminSessionExpired] flag without performing
  /// any I/O. Called by [AdminShell] in [State.initState] when a
  /// fresh shell mounts after the user came back through the auth
  /// gate — see [AdminViewModel.clearAdminSessionExpired] for the
  /// full reasoning. Same lifetime, same fix. Does NOT notify
  /// listeners for the same reason as [AdminViewModel].
  void clearAdminSessionExpired() {
    _adminSessionExpired = false;
  }

  /// Current site config. Defaults to name='simshop' on first frame so
  /// the home page never has to special-case an empty model.
  StoreInfo get siteInfo => _info;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch the latest site config from the backend. Safe to call multiple
  /// times — the UI calls it on pull-to-refresh and on admin screen open.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      _info = await _service.getStoreInfo();
    } catch (e) {
      _error = 'Lỗi tải thông tin cửa hàng: $e';
    } finally {
      _isLoading = false;
      _notifyIfAlive();
    }
  }

  /// Persist [info] to the backend. On success, the local model is
  /// updated so listeners see the new values immediately. On failure
  /// the previous values are preserved and [error] is set.
  ///
  /// [oldBannerUrl] is the banner_url the row held before this save.
  /// When the admin replaces the banner, the backend best-effort
  /// deletes the previous file from disk after the PUT commits —
  /// forward the prior URL so that diff happens. Pass `null` to skip
  /// the diff (back-compat — the file is left in place).
  Future<bool> update(StoreInfo info, {String? oldBannerUrl}) async {
    _isLoading = true;
    _error = null;
    _notifyIfAlive();
    try {
      _info = await _service.updateStoreInfo(info, oldBannerUrl: oldBannerUrl);
      _isLoading = false;
      _notifyIfAlive();
      return true;
    } on AdminSessionExpiredException catch (e) {
      // Cached Bearer token was rejected. Flip the flag so the
      // admin shell pops back to [AdminAuthGate]; the service
      // has already cleared the dead token from local storage.
      _adminSessionExpired = true;
      _error = e.message;
      _isLoading = false;
      _notifyIfAlive();
      return false;
    } catch (e) {
      _error = 'Lỗi lưu thông tin cửa hàng: $e';
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
