import 'package:flutter/foundation.dart';
import '../models/store_info.dart';
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
    notifyListeners();
    try {
      _info = await _service.getStoreInfo();
    } catch (e) {
      _error = 'Lỗi tải thông tin cửa hàng: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Persist [info] to the backend. On success, the local model is
  /// updated so listeners see the new values immediately. On failure
  /// the previous values are preserved and [error] is set.
  Future<bool> update(StoreInfo info) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _info = await _service.updateStoreInfo(info);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Lỗi lưu thông tin cửa hàng: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
