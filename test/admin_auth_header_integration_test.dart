// Integration test that PINs the actual HTTP request shape sent by
// [RealProductService.createProduct] with a real (in-memory)
// SharedPreferences + a recording HTTP client.
//
// Why this exists: the production bug ("POST /api/products has no
// Authorization header") cannot be reproduced reliably via the
// existing [_FakeProductService] fakes because those don't go through
// the [withAdminAuth] / [detectAdminSessionExpiry] paths. Only an
// end-to-end test that drives the real [RealProductService] against
// a recording client can pin what reaches the wire.
//
// Run with:
//   flutter test test/admin_auth_header_integration_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
import 'package:simshop/services/admin_auth_service.dart';
import 'package:simshop/services/product_service.dart';

class _RecordedRequest {
  _RecordedRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _RecordingClient extends http.BaseClient {
  final List<_RecordedRequest> requests = [];
  /// When non-null, the next request receives this status + body.
  /// Lets tests stage success/failure responses without coupling
  /// the recording client to a real backend.
  _StubResponse? nextResponse;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request
        ? request.body
        : request is http.MultipartRequest
            ? '[multipart]'
            : '';
    requests.add(
      _RecordedRequest(
        request.method,
        request.url,
        Map<String, String>.from(request.headers),
        body,
      ),
    );
    final stub = nextResponse ?? const _StubResponse(200, '{}');
    return http.StreamedResponse(
      Stream.value(utf8.encode(stub.body)),
      stub.status,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _StubResponse {
  const _StubResponse(this.status, this.body);
  final int status;
  final String body;
}

Product _sampleProduct() => Product(
      id: '',
      name: 'Áo thun test',
      description: 'desc',
      price: 100000,
      imageUrl: '',
      category: 'All',
      categories: const ['All'],
      rating: 0,
      stock: 0,
      specs: const [],
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('RealProductService.createProduct wire shape', () {
    test(
      'attaches Authorization: Bearer <token> when the auth service '
      'has a stored token (no images)',
      () async {
        // Pre-condition: a token has been persisted. Mirrors a
        // returning admin who already authenticated via
        // RealAdminAuthService.verify and now opens the create-
        // product dialog.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kAdminTokenStorageKey, 'tok-from-storage');

        final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
        final product = RealProductService(
          baseUrl: 'http://localhost:8080',
          authService: auth,
        );
        final recorder = _RecordingClient();

        // Override the product service's underlying client would
        // require touching its constructor. Simpler: build the
        // RealProductService such that when it calls
        // [http.post], it routes through the recorder. We do that by
        // instantiating a [RealAdminAuthService] with the same
        // client (proves the token round-trips through storage)
        // AND by intercepting the post via [http.runWithClient].
        // Stage a 201 with a body shaped to satisfy
        // [Product.fromJson]. Only the header assertion matters
        // for the regression — the response body is just there
        // to let createProduct's success branch run cleanly.
        recorder.nextResponse = const _StubResponse(
          201,
          '{"id":"p1","name":"Áo thun test","description":"desc",'
              '"price":100000,"image_url":"","images":[],'
              '"category":"All","categories":["All"],'
              '"specs":[],"rating":0,"reviews":0}',
        );
        final result = await http.runWithClient(
          () => product.createProduct(_sampleProduct()),
          () => recorder,
        );
        expect(result, isA<Product>());

        expect(recorder.requests, hasLength(1),
            reason: 'one POST must reach the wire');
        final req = recorder.requests.single;
        expect(req.method, 'POST');
        expect(req.uri.path, '/api/products');
        expect(req.headers['Authorization'], 'Bearer tok-from-storage',
            reason: 'createProduct must call withAdminAuth, which must '
                'read the token from SharedPreferences and attach the '
                'Bearer header. The production trace shows the header '
                'missing — this test pins the contract that the header '
                'is present.');
      },
    );

    test(
      'sends NO Authorization header when no token is stored '
      '(precondition check)',
      () async {
        // [withAdminAuth]'s contract: when no token is stored
        // (admin has never authenticated) the headers are returned
        // unchanged. The backend will then 401, and
        // [detectAdminSessionExpiry] surfaces it as
        // [AdminSessionExpiredException]. Pinning the no-token
        // path here so a future refactor can't accidentally start
        // emitting a fake/wrong header.
        final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
        final product = RealProductService(
          baseUrl: 'http://localhost:8080',
          authService: auth,
        );
        final recorder = _RecordingClient();

        // Stage a 401 so the catch-and-throw path runs cleanly.
        recorder.nextResponse = const _StubResponse(
          401,
          '{"error":"admin session required"}',
        );

        await expectLater(
          http.runWithClient(
            () => product.createProduct(_sampleProduct()),
            () => recorder,
          ),
          throwsA(isA<AdminSessionExpiredException>()),
        );

        expect(recorder.requests, hasLength(1));
        final req = recorder.requests.single;
        expect(req.headers.containsKey('Authorization'), isFalse,
            reason: 'no token in storage → no Authorization header. '
                'Production bug: the header IS missing because the '
                'token was cleared by [detectAdminSessionExpiry] but '
                'the test below proves the actual cause-and-effect.');
      },
    );

    test(
      'REGRESSION: token round-trips through storage → service → '
      'Authorization header (the production trace wire format)',
      () async {
        // This is the test that pins the production bug: a brand-
        // new admin authenticates (server returns a token),
        // RealAdminAuthService persists it, then createProduct
        // reads it back and attaches it as a Bearer header. If
        // this test ever fails the way production failed, we have
        // a regression on the storage round-trip.
        final client = _RecordingClient();
        final auth = RealAdminAuthService(
          baseUrl: 'http://localhost:8080',
          client: client,
        );
        // Stage verify-success response.
        client.nextResponse = const _StubResponse(
          200,
          '{"token":"server-issued-tok","expires_at":9999999999}',
        );

        await auth.verify(
          nonce: 'n',
          signatureHex: '00' * 64,
          secretKeyBytes: Uint8List.fromList(List.filled(32, 0x42)),
        );

        // Token must now be in SharedPreferences. Read it back
        // independently to prove the storage step.
        final stored = await auth.getStoredToken();
        expect(stored, 'server-issued-tok',
            reason: 'verify must persist the token before returning');
        // Suppress the unused warning — keep the read for the
        // explicit "token landed in storage" assertion.
        expect(stored, isNotNull);

        // Now drive createProduct through a separate recording
        // client. We need TWO clients because [RealAdminAuthService]
        // owns its own and [RealProductService] uses
        // [http.runWithClient].
        final productClient = _RecordingClient();
        productClient.nextResponse = const _StubResponse(
          201,
          '{"id":"p1","name":"Áo thun test","description":"desc",'
              '"price":100000,"image_url":"","images":[],'
              '"category":"All","categories":["All"],'
              '"specs":[],"rating":0,"reviews":0}',
        );
        final productSvc = RealProductService(
          baseUrl: 'http://localhost:8080',
          authService: auth,
        );

        await http.runWithClient(
          () => productSvc.createProduct(_sampleProduct()),
          () => productClient,
        );

        expect(productClient.requests, hasLength(1));
        final req = productClient.requests.single;
        expect(req.headers['Authorization'], 'Bearer server-issued-tok',
            reason: 'production regression: this is the exact header '
                'that was missing from the trace. If this fails, the '
                'token round-trip is broken — check SharedPreferences '
                'key, host settings, or service wiring.');
      },
    );
  });
}
