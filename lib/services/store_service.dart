import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/store_info.dart';
import '_http_with_admin_token.dart';
import 'admin_auth_service.dart';

/// Service for the singleton site config (identity + branding).
///
/// Mirrors the IProductService pattern: a small interface, a real HTTP
/// implementation, and a default base URL of http://localhost:8080.
abstract class IStoreService {
  /// Fetch the current site config. Returns an empty [StoreInfo] when
  /// the backend is unreachable; the caller can show a fallback.
  Future<StoreInfo> getStoreInfo();

  /// Persist site config. Throws on validation or network failure so
  /// the viewmodel can surface a SnackBar.
  Future<StoreInfo> updateStoreInfo(StoreInfo info);
}

class RealStoreService implements IStoreService {
  RealStoreService({String? baseUrl, IAdminAuthService? authService})
      : _baseUrl = baseUrl ?? 'http://localhost:8080',
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
  Future<StoreInfo> updateStoreInfo(StoreInfo info) async {
    final headers = await withAdminAuth(
      _auth,
      const {'Content-Type': 'application/json'},
    );
    final response = await http.put(
      _storeInfoUri(),
      headers: headers,
      body: json.encode(info.toJson()),
    );
    if (response.statusCode != 200) {
      final body = response.body.isNotEmpty ? response.body : 'Unknown error';
      throw Exception('Failed to update site info: $body');
    }
    return StoreInfo.fromJson(json.decode(response.body) as Map<String, dynamic>);
  }
}
