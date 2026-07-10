import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/store_info.dart';
import '_http_with_admin_token.dart';
import 'admin_auth_service.dart';

/// Service for the singleton site config (identity + branding).
///
/// Mirrors the IProductService pattern: a small interface, a real HTTP
/// implementation, and a default base URL sourced from [ApiConfig]
/// (which reads `.env` at app startup).
abstract class IStoreService {
  /// Fetch the current site config. Returns an empty [StoreInfo] when
  /// the backend is unreachable; the caller can show a fallback.
  Future<StoreInfo> getStoreInfo();

  /// Persist site config. Throws on validation or network failure so
  /// the viewmodel can surface a SnackBar.
  ///
  /// Pass the previously-saved banner URL as [oldBannerUrl]; when
  /// [info.bannerUrl] differs the backend best-effort deletes the
  /// previous file from disk after the PUT commits, so /uploads/
  /// doesn't accumulate orphan banners. Pass `null` or `""` to skip
  /// the diff (back-compat — the file is left in place).
  Future<StoreInfo> updateStoreInfo(StoreInfo info, {String? oldBannerUrl});
}

class RealStoreService implements IStoreService {
  RealStoreService({String? baseUrl, IAdminAuthService? authService})
      : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _auth = authService;

  final String _baseUrl;
  // Optional — when present, admin write endpoints (PUT store-info)
  // attach the bearer token. Optional so unit tests don't need a
  // SharedPreferences dependency.
  final IAdminAuthService? _auth;

  Uri _storeInfoUri() => Uri.parse('$_baseUrl/api/store-info');

  @override
  Future<StoreInfo> getStoreInfo() async {
    try {
      final response = await http.get(_storeInfoUri());
      if (response.statusCode != 200) {
        return const StoreInfo.empty();
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      return StoreInfo.fromJson(data);
    } catch (_) {
      // Network errors are not fatal here — fall back to defaults so the
      // home page can still render while the backend is down.
      return const StoreInfo.empty();
    }
  }

  @override
  Future<StoreInfo> updateStoreInfo(StoreInfo info, {String? oldBannerUrl}) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final map = info.toJson();
    if (oldBannerUrl != null && oldBannerUrl.isNotEmpty) {
      map['old_banner_url'] = oldBannerUrl;
    }
    final response = await http.put(
      _storeInfoUri(),
      headers: headers,
      body: json.encode(map),
    );
    // Mirror the product_service pattern: if the server rejected our
    // cached admin token with the standard 401, clear it locally and
    // surface [AdminSessionExpiredException] so the viewmodel can
    // bounce the admin back to [AdminAuthGate] for re-auth. Without
    // this the request just looks like a generic PUT failure, the
    // cached dead token stays in SharedPreferences, and every
    // subsequent PUT keeps failing with the same "admin session
    // required" 401 until the user manually clears app data.
    await detectAdminSessionExpiry(_auth, response);
    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to update site info: $body');
    }
    return StoreInfo.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }
}
