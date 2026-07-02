import 'package:http/http.dart' as http;

import 'admin_auth_service.dart';

/// Thrown when an admin write request returns 401 — the cached
/// token is stale (server restart, TTL elapsed, etc.). Callers
/// should surface this so the user is sent back to
/// [AdminAuthGate] to re-authenticate.
class AdminSessionExpiredException implements Exception {
  AdminSessionExpiredException(this.message);
  final String message;
  @override
  String toString() => 'AdminSessionExpiredException: $message';
}

/// Returns true if the response is the standard admin "session
/// required" 401 — `{ "error": "admin session required" }`.
bool _isAdminSessionExpired(http.Response response) {
  if (response.statusCode != 401) return false;
  // Cheap content sniff — we don't want to JSON-decode every 401,
  // only the ones from admin write endpoints.
  return response.body.contains('admin session required');
}

/// Inspect an [http.Response] from an admin write endpoint and, if
/// the server returned 401 because the cached token is no longer
/// valid, clear the local copy and throw
/// [AdminSessionExpiredException]. Non-401 responses pass through
/// untouched so callers can handle them with their normal error
/// logic.
Future<void> detectAdminSessionExpiry(
  IAdminAuthService? service,
  http.Response response,
) async {
  if (!_isAdminSessionExpired(response)) return;
  if (service != null) {
    // Best-effort: drop the cached token so the next write doesn't
    // re-send the same dead credential.
    await service.clearStoredToken();
  }
  throw AdminSessionExpiredException(
    'Phiên quản trị đã hết hạn, vui lòng đăng nhập lại.',
  );
}

/// Returns a copy of [headers] augmented with `Authorization: Bearer
/// <token>` when a token is stored locally. If no token is stored
/// (admin hasn't authenticated yet, or has logged out) the original
/// headers are returned unchanged — the backend will then 401 the
/// request, which the caller is expected to detect via
/// [detectAdminSessionExpiry].
Future<Map<String, String>> withAdminAuth(
  IAdminAuthService? service,
  Map<String, String> headers,
) async {
  if (service == null) return headers;
  final token = await service.getStoredToken();
  if (token == null || token.isEmpty) return headers;
  return {
    ...headers,
    'Authorization': 'Bearer $token',
  };
}

/// Same as [withAdminAuth] but for a `http.Request` / `http.MultipartRequest`
/// — useful when callers want to mutate headers in place.
Future<void> attachAdminAuth(
  IAdminAuthService? service,
  http.BaseRequest request,
) async {
  if (service == null) return;
  final token = await service.getStoredToken();
  if (token == null || token.isEmpty) return;
  request.headers['Authorization'] = 'Bearer $token';
}