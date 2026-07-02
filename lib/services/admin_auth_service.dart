import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

/// Storage key for the admin session token. Survives app restart
/// on mobile (SharedPreferences) and web (localStorage). Treated as
/// a long-lived bearer credential — anyone who can read this value
/// is admin until the server-side 24h TTL expires or the user
/// explicitly logs out.
const String kAdminTokenStorageKey = 'simshop.admin_token';

/// Contract for the admin challenge/verify protocol.
///
/// Flow (mirrored from [RealAdminAuthService]):
///   1. [requestChallenge] — POST /api/admin/auth/challenge → nonce.
///   2. Caller signs the nonce with the secret key file bytes.
///   3. [verify] — POST /api/admin/auth/verify (multipart) → token.
///   4. Token is cached locally and surfaced via [getStoredToken] so
///      other services can attach it as `Authorization: Bearer ...`.
///
/// All methods throw on transport errors; callers (the gate viewmodel)
/// are expected to catch + surface them.
abstract class IAdminAuthService {
  Future<String> requestChallenge();

  Future<String> verify({
    required String nonce,
    required String signatureHex,
    required Uint8List secretKeyBytes,
  });

  Future<void> logout();

  /// Returns the cached token, or null if no session is stored.
  Future<String?> getStoredToken();

  /// Clears the cached token without calling the server (e.g. after a
  /// 401 makes the cached token useless).
  Future<void> clearStoredToken();
}

/// HTTP-backed admin auth. Talks to the Go backend's
/// `/api/admin/auth/*` endpoints.
class RealAdminAuthService implements IAdminAuthService {
  RealAdminAuthService({String? baseUrl, http.Client? client})
      : _baseUrl = baseUrl ?? ApiConfig.apiBaseUrl,
        _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Uri _challengeUri() => Uri.parse('$_baseUrl/api/admin/auth/challenge');
  Uri _verifyUri() => Uri.parse('$_baseUrl/api/admin/auth/verify');
  Uri _logoutUri() => Uri.parse('$_baseUrl/api/admin/auth/logout');

  @override
  Future<String> requestChallenge() async {
    // Drive the request through [_client.send] so tests can plug in a
    // fake http.BaseClient without an IOClient bypassing them. Going
    // through [Client.post] on a BaseClient subclass forwards to a
    // default IOClient because [BaseClient] does not override the
    // typed convenience methods ([http.Client.post] lives on the
    // concrete [IOClient] base).
    final req = http.Request('POST', _challengeUri());
    final streamed = await _client
        .send(req)
        .timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception('Challenge failed (${response.statusCode})');
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final nonce = body['nonce'] as String?;
    if (nonce == null || nonce.isEmpty) {
      throw Exception('Challenge returned empty nonce');
    }
    return nonce;
  }

  @override
  Future<String> verify({
    required String nonce,
    required String signatureHex,
    required Uint8List secretKeyBytes,
  }) async {
    final request = http.MultipartRequest('POST', _verifyUri());
    request.fields['nonce'] = nonce;
    request.fields['signature'] = signatureHex;
    request.files.add(
      http.MultipartFile.fromBytes('key', secretKeyBytes, filename: 'admin.key'),
    );

    // Same reason as [requestChallenge]: route through [_client.send]
    // (not [MultipartRequest.send], which always builds an IOClient
    // internally) so a fake BaseClient can intercept the call.
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      final errBody = response.body.isNotEmpty ? response.body : 'unknown';
      throw Exception('Verify failed (${response.statusCode}): $errBody');
    }
    final body = json.decode(response.body) as Map<String, dynamic>;
    final token = body['token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('Verify returned empty token');
    }
    await _persistToken(token);
    return token;
  }

  @override
  Future<void> logout() async {
    final token = await getStoredToken();
    if (token == null) return;
    try {
      final req = http.Request('POST', _logoutUri());
      req.headers['Authorization'] = 'Bearer $token';
      await _client.send(req).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Logout is best-effort; if the server is unreachable we still
      // want to clear the local copy so the user has to re-auth.
    }
    await clearStoredToken();
  }

  @override
  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(kAdminTokenStorageKey);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  @override
  Future<void> clearStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAdminTokenStorageKey);
  }

  Future<void> _persistToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminTokenStorageKey, token);
  }
}

/// Helper that signs a UTF-8 message with the first 32 bytes of an
/// Ed25519 secret key (interpreted as the seed). Returns 64 raw
/// signature bytes.
///
/// The backend accepts both 32-byte seeds and 64-byte expanded keys.
/// We only need to read 32 bytes here, so the helper is trivial; it
/// lives at the top level so the gate screen + tests can share it
/// without dragging the cryptography package into the viewmodel.
Future<Uint8List> signEd25519(Uint8List secretKeyBytes, String message) async {
  if (secretKeyBytes.length < 32) {
    throw const FormatException('Ed25519 secret key must be at least 32 bytes');
  }
  final seed = secretKeyBytes.sublist(0, 32);
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  final signature = await algorithm.sign(utf8.encode(message), keyPair: keyPair);
  return Uint8List.fromList(signature.bytes);
}

/// Lowercase hex encode, no separators. Equivalent to Go's
/// `hex.EncodeToString`. Used to format the signature (and could be
/// used for the public key) before sending over the wire.
String bytesToHex(Uint8List bytes) {
  const chars = '0123456789abcdef';
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(chars[(b >> 4) & 0xf]);
    out.write(chars[b & 0xf]);
  }
  return out.toString();
}