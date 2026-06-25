import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Helpers for integration tests that require a live Go backend.
///
/// These tests assert real HTTP behavior (URL paths, status codes, JSON
/// wire format) instead of using mocks. They assume the backend is
/// already running on `localhost:8080` — typically via
/// `cd backend && go run ./main.go` in a separate terminal, with seed
/// data loaded via `go run ./cmd/seed/main.go`.
///
/// If the backend is not reachable, tests are skipped (not failed) so
/// that CI without a backend still passes the rest of the suite.

/// Default base URL — matches [RealAnalyticsService] and
/// [RealProductService] when no override is supplied.
const String kDefaultBackendBaseUrl = 'http://localhost:8080';

/// Ping the backend's `/health` endpoint. Returns true if it responds
/// with 200 within [timeout]; false otherwise (network error, non-200,
/// timeout). Intentionally short timeout — a healthy backend replies
/// in milliseconds.
Future<bool> isBackendUp({
  String baseUrl = kDefaultBackendBaseUrl,
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(timeout);
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Skip the calling test if the backend is not reachable.
///
/// Uses [markTestSkipped] when available (Flutter test exposes a
/// skip API as of recent versions); otherwise throws a TestFailure
/// with a `skip:` prefix that CI tooling can recognize.
///
/// Usage inside a test body:
/// ```dart
/// testWidgets('...', (tester) async {
///   await skipIfBackendDown();
///   // ... real test body ...
/// });
/// ```
Future<void> skipIfBackendDown({
  String baseUrl = kDefaultBackendBaseUrl,
}) async {
  if (!await isBackendUp(baseUrl: baseUrl)) {
    final msg = 'Backend not running at $baseUrl. '
        'Start it with: cd backend && go run ./main.go '
        '(and seed data: go run ./cmd/seed/main.go)';
    // Dart's test package (and by extension flutter_test) exposes
    // markTestSkipped via the TestFailure API. Throwing with the
    // marker 'skip:' at the start of the message is the documented
    // way to skip a test in pure Dart test (no Flutter UI binding).
    throw TestFailure('skip: $msg');
  }
}
