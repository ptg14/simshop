import 'package:flutter_test/flutter_test.dart';
import 'package:simshop/config/api_config.dart';

/// Pins the runtime-config behavior of [ApiConfig].
///
/// Why these tests exist: the original symptom was a blank screen
/// because the backend URL was hardcoded inside each service. When
/// we centralized the URL behind [ApiConfig.apiBaseUrl], we also
/// added a defensive try/catch around `dotenv.maybeGet` so tests
/// and misconfigured environments fall back to the local default
/// instead of throwing `NotInitializedError` at startup. These
/// tests pin both pieces of behavior so a future change can't
/// silently regress either.
void main() {
  group('ApiConfig', () {
    test('defaultBaseUrl points at the local Go backend', () {
      // The dev server runs on :8080 by default (see backend README).
      // We assert the literal value rather than parsing it so a
      // change to the port shows up here, not in some downstream
      // network test that took 12 seconds to fail.
      expect(ApiConfig.defaultBaseUrl, 'http://localhost:8080');
    });

    test('baseUrlKey matches the .env contract', () {
      // If this drifts, every contributor's .env stops working
      // silently. The key is exposed so callers (and tests) can
      // reference it without re-typing the string.
      expect(ApiConfig.baseUrlKey, 'API_BASE_URL');
    });

    test('apiBaseUrl never throws when dotenv is uninitialized', () {
      // `flutter_dotenv.maybeGet` throws NotInitializedError when
      // called before `dotenv.load()`. Services constructed inside
      // unit tests (which bypass `main()`) must still produce a
      // usable URL — the whole point of the centralized config is
      // that services can be built anywhere without crashing.
      expect(() => ApiConfig.apiBaseUrl, returnsNormally);
    });

    test('apiBaseUrl returns a non-empty URL even with dotenv uninitialized',
        () {
      final url = ApiConfig.apiBaseUrl;
      expect(url, isNotEmpty);
      expect(url.startsWith('http://') || url.startsWith('https://'), isTrue,
          reason: 'fallback must be a usable URL, not a slash or empty');
    });

    test('apiBaseUrl uses defaultBaseUrl when neither override nor env set',
        () {
      // String.fromEnvironment('API_BASE_URL') with no --dart-define
      // yields an empty string at runtime. dotenv is not initialized
      // in unit tests so dotenv.maybeGet throws → caught. Both paths
      // fall through to defaultBaseUrl.
      expect(ApiConfig.apiBaseUrl, ApiConfig.defaultBaseUrl);
    });
  });
}

/// Compile-time override behavior is exercised by
/// `flutter test --dart-define=API_BASE_URL=...`. We pin the
/// precedence in code review rather than via a separate test file
/// because Dart test runners don't compose --dart-define across
/// multiple `test(...)` blocks without each test re-stating it.
/// The contract: when the override is set, ApiConfig.apiBaseUrl
/// returns it verbatim (trailing slash stripped), regardless of
/// what's in the .env asset.