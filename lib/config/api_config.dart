import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime configuration loaded from `.env` (via `flutter_dotenv`,
/// dev builds only) with a compile-time override via `--dart-define`.
///
/// Centralizes the backend base URL so the six services (`product`,
/// `article`, `event`, `store`, `admin_auth`, plus any future
/// callers) share a single source of truth instead of each holding
/// its own fallback. Keeping the configuration in one place means
/// a deployment just has to set the build arg (or `.env` for local
/// dev) and every service picks up the new value on next launch.
///
/// Resolution order (highest priority first):
///   1. `String.fromEnvironment('API_BASE_URL')` — compile-time,
///      set via `--dart-define=API_BASE_URL=...`. This is what
///      production Docker builds use (`docker compose` passes the
///      URL via build arg). Compile-time wins because:
///        - It's immutable per build artifact (no surprise flip).
///        - The `.env` asset bundle is no longer shipped in release
///          builds (removed from pubspec.yaml assets list), so
///          `dotenv.load()` never runs in production and
///          `dotenv.maybeGet` always returns null. There's no
///          possibility of a stale local `.env` overriding the
///          production URL.
///   2. `dotenv.maybeGet('API_BASE_URL')` — runtime, from a `.env`
///      asset present in dev builds only. When `flutter run`
///      launches a debug build the developer may have a real `.env`
///      at the repo root and we read it for convenience.
///   3. [_defaultBaseUrl] — empty string. With no override and no
///      .env, [apiBaseUrl] returns `''`. Services built on top
///      must handle the empty case (throw a clear error on first
///      network call). Crucially, no `localhost` literal is baked
///      into the release bundle, so a misconfigured release fails
///      fast instead of silently hitting a dev box.
///
/// All builds — including dev — MUST set `API_BASE_URL` either
/// via `--dart-define` or via `.env`. Empty is the documented
/// "misconfigured" state; see `docker/.env.example` for the
/// production shape and the `tool/dev.dart` helper for the dev one.
class ApiConfig {
  ApiConfig._();

  /// Key used inside `.env`. Centralized so renames are a single
  /// edit and so tests can assert against it without string-typing
  /// the value at every call site.
  static const String baseUrlKey = 'API_BASE_URL';

  /// Compile-time override. When the build is invoked with
  /// `--dart-define=API_BASE_URL=https://api.example.com`, this
  /// constant carries that value at compile time and wins over the
  /// `.env` asset at runtime. Empty string means "no override
  /// supplied"; the resolver falls through to dotenv / default.
  ///
  /// Declared `const String.fromEnvironment` so it's a compile-time
  /// constant — the Dart tree-shaker drops the `if (override.isNotEmpty)`
  /// branch from the release bundle entirely when no override is set.
  static const String _compileTimeOverride =
      String.fromEnvironment('API_BASE_URL');

  /// Last-resort value when neither compile-time nor `.env` provides
  /// one. Empty so that:
  ///   - The release bundle never contains a `localhost` string that
  ///     would silently re-route production traffic to a dev box.
  ///   - [apiBaseUrl] callers can detect misconfiguration by checking
  ///     `isEmpty` and surface a clear error.
  static const String _defaultBaseUrl = '';

  /// Returns the API base URL using the resolution order described
  /// at class level. Trailing slashes are stripped so callers can
  /// safely concatenate `'$baseUrl/api/...'` without producing
  /// `//api/...`.
  ///
  /// Wrapped in try/catch around the dotenv access because
  /// `flutter_dotenv` throws `NotInitializedError` when accessed
  /// before `dotenv.load` has run, or `MissingAsset` when the `.env`
  /// file is no longer in the asset manifest. Both are treated as
  /// "no runtime value" and fall through to [apiBaseUrl]'s default.
  static String get apiBaseUrl {
    // Step 1: compile-time override (highest priority).
    final compileTime = _compileTimeOverride.trim();
    if (compileTime.isNotEmpty) {
      return _stripTrailingSlash(compileTime);
    }

    // Step 2: runtime .env asset (dev builds only).
    String raw = '';
    try {
      raw = dotenv.maybeGet(baseUrlKey)?.trim() ?? '';
    } on Object {
      // dotenv not initialized or `.env` not shipped as asset
      // (e.g. release Docker build, or unit tests) → behave as if
      // the key were absent.
      raw = '';
    }
    final value = raw.isEmpty ? _defaultBaseUrl : raw;
    return _stripTrailingSlash(value);
  }

  /// Trailing slash trim isolated so both branches share the same
  /// behaviour. Kept private — callers should never need to invoke
  /// it directly.
  static String _stripTrailingSlash(String value) => value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
}