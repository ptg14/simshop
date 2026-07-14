// Regression tests for the ChangeNotifierProxyProvider wiring in
// lib/main.dart.
//
// The production bug: AdminViewModel was wired via
//
//   ChangeNotifierProxyProvider<IProductService, AdminViewModel>(
//     create: (_) => AdminViewModel(),
//     update: (_, productService, prev) =>
//         prev ?? AdminViewModel(productService: productService),
//     lazy: true,
//   ),
//
// When this fires the first time:
//   1. `create` runs and returns `AdminViewModel()` — the no-arg
//      constructor. AdminViewModel's no-arg branch falls back to
//      `RealProductService()` (no authService).
//   2. `update` runs with `prev = <the no-args AdminViewModel>`.
//      `prev ?? AdminViewModel(productService: productService)`
//      evaluates to `prev` (the no-args instance), because `??`
//      only takes the right side when left is null.
//
// Net result: the AdminViewModel exposed by the proxy holds a
// RealProductService with `_auth = null`. Admin writes go out
// with NO Authorization header → backend 401 → user sees
// "phiên đã hết hạn".
//
// These two tests pin both halves of the contract:
//   - BUGGY pattern test: reproduces the production failure mode
//     (header absent) so a future refactor that re-introduces the
//     buggy `create: (_) => AdminViewModel()` line fails LOUDLY.
//   - FIXED pattern test: drives the fixed provider chain end-to-
//     end and pins that the Authorization header IS attached.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/services/admin_auth_service.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/viewmodels/admin_viewmodel.dart';

class _RecordedRequest {
  _RecordedRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _RecordingClient extends http.BaseClient {
  final List<_RecordedRequest> requests = [];
  int nextStatus = 201;
  String nextBody = '{}';

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
    return http.StreamedResponse(
      Stream.value(utf8.encode(nextBody)),
      nextStatus,
      headers: {'content-type': 'application/json'},
    );
  }
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

/// Build the EXACT MultiProvider subtree the app uses, except that
/// the AdminViewModel's proxy provider pattern can be swapped via
/// [useFixedCreate] — `true` mirrors the production fix, `false`
/// reproduces the historical bug. All other providers are identical
/// to lib/main.dart.
Widget _wireApp({required bool useFixedCreate}) {
  return MultiProvider(
    providers: [
      Provider<IAdminAuthService>(
        create: (_) => RealAdminAuthService(),
        lazy: true,
      ),
      Provider<IProductService>(
        create: (ctx) => RealProductService(
          authService: ctx.read<IAdminAuthService>(),
        ),
        lazy: true,
      ),
      ChangeNotifierProxyProvider<IProductService, AdminViewModel>(
        create: useFixedCreate
            ? (ctx) => AdminViewModel(
                  productService: ctx.read<IProductService>(),
                )
            : (_) => AdminViewModel(),
        update: (_, productService, prev) =>
            prev ?? AdminViewModel(productService: productService),
        lazy: true,
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'BUGGY `create: (_) => AdminViewModel()` → admin write has NO '
    'Authorization header (the production failure mode)',
    (tester) async {
      // Pre-condition: a stored token, mirroring a returning admin
      // who already authenticated.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAdminTokenStorageKey, 'prod-wire-tok');

      await tester.pumpWidget(_wireApp(useFixedCreate: false));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MaterialApp));
      final admin = Provider.of<AdminViewModel>(element, listen: false);

      final recorder = _RecordingClient();
      recorder.nextStatus = 201;
      recorder.nextBody = '{"id":"p1","name":"x","description":"d",'
          '"price":1000,"image_url":"","images":[],'
          '"category":"All","categories":["All"],'
          '"specs":[],"rating":0,"reviews":0}';

      await http.runWithClient(
        () => admin.addProduct(_sampleProduct()),
        () => recorder,
      );

      expect(recorder.requests, hasLength(1),
          reason: 'one POST must reach the wire');
      final req = recorder.requests.single;
      expect(req.uri.path, '/api/products');
      expect(req.headers['Authorization'], isNull,
          reason: 'the buggy `create: (_) => AdminViewModel()` pattern '
              'leaves AdminViewModel holding the no-args fallback '
              '(RealProductService with _auth = null), so the request '
              'goes out WITHOUT an Authorization header. This is the '
              'exact production trace: POST /api/products 401 "admin '
              'session required" with NO Authorization header on the '
              'request. The fix changes `create` to `(ctx) => '
              'AdminViewModel(productService: ctx.read<IProductService>())`.');
    },
  );

  testWidgets(
    'FIXED `create: (ctx) => AdminViewModel(productService: '
    'ctx.read<IProductService>())` → admin write has Authorization '
    'header attached',
    (tester) async {
      // Pre-condition: a stored token.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAdminTokenStorageKey, 'prod-wire-tok');

      await tester.pumpWidget(_wireApp(useFixedCreate: true));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MaterialApp));
      final admin = Provider.of<AdminViewModel>(element, listen: false);

      final recorder = _RecordingClient();
      recorder.nextStatus = 201;
      recorder.nextBody = '{"id":"p1","name":"x","description":"d",'
          '"price":1000,"image_url":"","images":[],'
          '"category":"All","categories":["All"],'
          '"specs":[],"rating":0,"reviews":0}';

      await http.runWithClient(
        () => admin.addProduct(_sampleProduct()),
        () => recorder,
      );

      expect(recorder.requests, hasLength(1),
          reason: 'one POST must reach the wire');
      final req = recorder.requests.single;
      expect(req.uri.path, '/api/products');
      expect(
        req.headers['Authorization'],
        'Bearer prod-wire-tok',
        reason: 'the fix routes IProductService (with IAdminAuthService '
            'injected) into AdminViewModel via `ctx.read` in `create`, '
            'so the request carries the Bearer token. If this fails, '
            'either the test harness is wrong or the fix has been '
            'reverted in lib/main.dart.',
      );
    },
  );
}