import 'package:flutter/foundation.dart';

import '../services/admin_auth_service.dart';

/// State of the admin auth gate.
///
/// `idle`    — initial state, no in-flight request
/// `loading` — challenge/verify in flight
/// `success` — token persisted; gate should navigate away
/// `error`   — last attempt failed; [AdminAuthViewModel.error] holds the message
enum AdminAuthState { idle, loading, success, error }

/// Drives the admin auth gate UI.
///
/// Single-shot state machine: the gate screen pushes
/// `authenticateWithSecretFile(keyBytes)` and listens for the
/// [state] transition. We expose a separate [isAuthenticated] for
/// callers that just want to know "is there a token in storage?" —
/// useful for the admin shell to short-circuit out of the gate on
/// hot-restart.
class AdminAuthViewModel extends ChangeNotifier {
  AdminAuthViewModel({IAdminAuthService? service})
      : _service = service ?? RealAdminAuthService();

  final IAdminAuthService _service;

  AdminAuthState _state = AdminAuthState.idle;
  String? _error;

  AdminAuthState get state => _state;
  String? get error => _error;
  bool get isLoading => _state == AdminAuthState.loading;
  bool get isAuthenticated => _state == AdminAuthState.success;

  /// Returns true if a token is already in storage. The gate calls
  /// this on initState so a returning admin doesn't have to re-upload
  /// the key file every app open.
  Future<bool> hasStoredToken() async {
    final token = await _service.getStoredToken();
    return token != null && token.isNotEmpty;
  }

  /// Run the full challenge → sign → verify flow.
  ///
  /// On success transitions to [AdminAuthState.success] and the
  /// caller should push the admin shell. On failure transitions to
  /// [AdminAuthState.error] with a user-facing message in [error].
  Future<bool> authenticateWithSecretKey(Uint8List keyBytes) async {
    if (_state == AdminAuthState.loading) return false;
    _setState(AdminAuthState.loading);
    try {
      final nonce = await _service.requestChallenge();
      final sigBytes = await signEd25519(keyBytes, nonce);
      final sigHex = bytesToHex(sigBytes);
      await _service.verify(
        nonce: nonce,
        signatureHex: sigHex,
        secretKeyBytes: keyBytes,
      );
      _setState(AdminAuthState.success);
      return true;
    } catch (e) {
      _setState(AdminAuthState.error, _humanizeError(e));
      return false;
    }
  }

  /// Clear local session. Used by the admin shell's logout button (if
  /// any) and when a write fails with 401 so we drop the stale token.
  Future<void> logout() async {
    await _service.logout();
    _setState(AdminAuthState.idle);
  }

  /// Clear stale token after a 401 — keeps the gate state as-is so
  /// the user can retry with the same key file.
  Future<void> clearStaleToken() async {
    await _service.clearStoredToken();
  }

  /// Reset transient state (e.g. when the user dismisses the error
  /// banner). Doesn't touch the stored token.
  void reset() {
    if (_state == AdminAuthState.error) {
      _setState(AdminAuthState.idle);
    }
  }

  void _setState(AdminAuthState s, [String? err]) {
    _state = s;
    _error = err;
    notifyListeners();
  }

  /// Convert raw exceptions into messages the gate screen can show
  /// verbatim. Most are already strings from [RealAdminAuthService].
  String _humanizeError(Object e) {
    final raw = e.toString();
    if (raw.startsWith('Exception: ')) return raw.substring('Exception: '.length);
    return raw;
  }
}