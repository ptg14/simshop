import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime configuration loaded from `.env` (via `flutter_dotenv`).
///
/// Centralizes the backend base URL so the six services (`product`,
/// `article`, `event`, `store`, `admin_auth`, plus any future
/// callers) share a single source of truth instead of each holding
/// its own `http://localhost:8080` fallback. Keeping the
/// configuration in one place means a deployment just has to swap
/// `.env` (or pass `BASE_URL` overrides at build time) and every
/// service picks up the new value on next launch.
///
/// The default value below is intentionally permissive — if the
/// `.env` file is missing or malformed (key absent, blank value,
/// etc.) the app still boots pointing at the local dev server.
/// Production deployments must commit a real `.env`; see
/// `.env.example` for the documented shape.
class ApiConfig {
  ApiConfig._();

  /// Key used inside `.env`. Centralized so renames are a single
  /// edit and so tests can assert against it without string-typing
  /// the value at every call site.
  static const String baseUrlKey = 'API_BASE_URL';

  /// Fallback used when the key is missing or blank. Matches the
  /// local Go backend default (see `backend/README.md`). Stays a
  /// `localhost` URL — never a real production hostname — so a
  /// misconfigured release can't accidentally hit a live API.
  static const String defaultBaseUrl = 'http://localhost:8080';

  /// Returns the API base URL from `.env`, or [defaultBaseUrl] if
  /// the key is unset / blank. Trailing slashes are stripped so
  /// callers can safely concatenate `'$baseUrl/api/...'` without
  /// producing `//api/...`.
  ///
  /// Wrapped in try/catch because `flutter_dotenv` throws
  /// [NotInitializedError] when accessed before
  /// [dotenv.load] has run. Tests that construct services
  /// directly (without spinning up `main()`) would otherwise crash
  /// with that exception — falling back to [defaultBaseUrl] keeps
  /// the unit-test suite usable and matches the "missing config
  /// means local dev" semantics the docstring promises.
  static String get apiBaseUrl {
    String raw = '';
    try {
      raw = dotenv.maybeGet(baseUrlKey)?.trim() ?? '';
    } on Object {
      // dotenv not initialized (test environment, or main() ran
      // before dotenv.load) → behave as if the key were absent.
      raw = '';
    }
    final value = raw.isEmpty ? defaultBaseUrl : raw;
    return value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
  }
}