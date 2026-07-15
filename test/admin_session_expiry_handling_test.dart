// Regression tests covering the `detectAdminSessionExpiry` contract
// on every admin write path.
//
// The bug pattern: an admin write method (product upload, article
// CRUD, banner CRUD, event CRUD) calls `http.post`/`_client.post`
// with the Bearer token attached. If the server returns
// `401 {"error":"admin session required"}` — either because the
// session TTL elapsed or because the server restarted and lost the
// in-memory SessionStore — the method MUST:
//
//   1. Call `await detectAdminSessionExpiry(_auth, response)` so the
//      dead token is cleared from SharedPreferences.
//   2. Throw `AdminSessionExpiredException` so the calling
//      viewmodel / AdminShell can route the user back to
//      AdminAuthGate for re-auth.
//
// Without this contract, the user is stuck: the dead token stays
// in SharedPreferences, every subsequent write keeps failing with
// the same generic `Exception('Failed to ...: 401')`, and there's
// no path back to the auth gate without manual app-data clearing.
//
// `admin_auth_header_integration_test.dart` pins the same pattern
// for `createProduct`. This file extends that coverage to every
// admin write path that currently has the gap.
//
// Each test stages a 401 with the canonical body and asserts:
//   a) `AdminSessionExpiredException` is thrown.
//   b) The stored token is cleared (next write wouldn't carry a
//      stale credential).
//   c) The request reached the wire with `Authorization: Bearer
//      <stored-token>` (proves the path is exercised, not short-
//      circuited).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/models/banner.dart';
import 'package:simshop/models/event.dart';
import 'package:simshop/models/product.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/_http_with_admin_token.dart';
import 'package:simshop/services/admin_auth_service.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/services/event_service.dart';
import 'package:simshop/services/product_service.dart';
import 'package:simshop/services/store_service.dart';

class _RecordedRequest {
  _RecordedRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

class _RecordingClient extends http.BaseClient {
  final List<_RecordedRequest> requests = [];
  int nextStatus = 200;
  String nextBody = '{"error":"admin session required"}';
  // Two-stage body queue: tests can stage a 401 then a 200 to verify
  // the token is actually cleared (the second request should NOT
  // carry the stale credential).
  final List<int> statusQueue = [];
  final List<String> bodyQueue = [];

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
    final status =
        statusQueue.isNotEmpty ? statusQueue.removeAt(0) : nextStatus;
    final respBody =
        bodyQueue.isNotEmpty ? bodyQueue.removeAt(0) : nextBody;
    return http.StreamedResponse(
      Stream.value(utf8.encode(respBody)),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

Product _sampleProduct() => Product(
      id: '',
      name: 'SP test',
      description: 'desc',
      price: 50000,
      imageUrl: '',
      category: 'All',
      categories: const ['All'],
      rating: 0,
      stock: 0,
      specs: const [],
    );

Article _sampleArticle() => const Article(
      id: '',
      title: 'Bài viết test',
      body: '',
    );

Event _sampleEvent() => const Event(
      id: '',
      name: 'Sự kiện test',
      discountType: DiscountType.percent,
      discountValue: 10,
    );

BannerSlide _sampleBanner() => const BannerSlide(
      id: '',
      ord: 1,
      title: 'Banner test',
      subtitle: '',
      imageUrl: '',
    );

StoreInfo _sampleStoreInfo() => const StoreInfo(
      name: 'Cửa hàng test',
      description: '',
      bannerUrl: '',
      phone: '',
      email: '',
      address: '',
      googleMapsUrl: '',
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> seedToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAdminTokenStorageKey, token);
  }

  Future<String?> currentStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kAdminTokenStorageKey);
  }

  group('Product uploads clear dead token + throw AdminSessionExpired', () {
    test(
      'uploadImage → 401 clears token + throws '
      'AdminSessionExpiredException',
      () async {
        await seedToken('prod-upload-tok');

        final recorder = _RecordingClient();
        recorder.nextStatus = 401;
        recorder.nextBody = '{"error":"admin session required"}';

        final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
        final svc = RealProductService(
          baseUrl: 'http://localhost:8080',
          authService: auth,
        );

        await expectLater(
          http.runWithClient(
            () => svc.uploadImage(Uint8List.fromList(List.filled(8, 0xFF))),
            () => recorder,
          ),
          throwsA(isA<AdminSessionExpiredException>()),
        );

        // Token must be cleared.
        final tokenAfter = await currentStoredToken();
        expect(tokenAfter, isNull,
            reason: 'uploadImage must call detectAdminSessionExpiry so '
                'the dead token is cleared from SharedPreferences.');

        // Wire level: Authorization was attached (the server
        // rejected it — that's what the 401 was for).
        expect(recorder.requests, hasLength(1));
        final req = recorder.requests.single;
        expect(req.method, 'POST');
        expect(req.uri.path, '/api/upload');
        expect(req.headers['Authorization'], 'Bearer prod-upload-tok');
      },
    );

    test(
      'uploadImages → 401 also clears token + throws',
      () async {
        await seedToken('prod-uploads-tok');

        final recorder = _RecordingClient();
        recorder.nextStatus = 401;
        recorder.nextBody = '{"error":"admin session required"}';

        final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
        final svc = RealProductService(
          baseUrl: 'http://localhost:8080',
          authService: auth,
        );

        await expectLater(
          http.runWithClient(
            () => svc.uploadImages([
              Uint8List.fromList(List.filled(8, 0xFF)),
            ]),
            () => recorder,
          ),
          throwsA(isA<AdminSessionExpiredException>()),
        );

        final tokenAfter = await currentStoredToken();
        expect(tokenAfter, isNull);

        expect(recorder.requests, hasLength(1));
        expect(recorder.requests.single.uri.path, '/api/upload');
        expect(
          recorder.requests.single.headers['Authorization'],
          'Bearer prod-uploads-tok',
        );
      },
    );
  });

  group('Article write paths clear dead token + throw', () {
    test('createArticle → 401 clears token + throws', () async {
      await seedToken('article-c-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealArticleService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.createArticle(_sampleArticle()),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/articles');
      expect(req.headers['Authorization'], 'Bearer article-c-tok');
    });

    test('updateArticle → 401 clears token + throws', () async {
      await seedToken('article-u-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealArticleService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.updateArticle(_sampleArticle()),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/api/articles/');
      expect(req.headers['Authorization'], 'Bearer article-u-tok');
    });

    test('deleteArticle → 401 clears token + throws', () async {
      await seedToken('article-d-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealArticleService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.deleteArticle('a-9'),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/api/articles/a-9');
      expect(req.headers['Authorization'], 'Bearer article-d-tok');
    });

    test('createBanner → 401 clears token + throws', () async {
      await seedToken('banner-c-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealArticleService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.createBanner(_sampleBanner()),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/banners');
      expect(req.headers['Authorization'], 'Bearer banner-c-tok');
    });

    test('updateBanner → 401 clears token + throws', () async {
      await seedToken('banner-u-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealArticleService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.updateBanner(_sampleBanner()),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/api/banners/');
      expect(req.headers['Authorization'], 'Bearer banner-u-tok');
    });

    test('deleteBanner → 401 clears token + throws', () async {
      await seedToken('banner-d-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealArticleService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.deleteBanner('b-9'),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/api/banners/b-9');
      expect(req.headers['Authorization'], 'Bearer banner-d-tok');
    });
  });

  group('Event write paths clear dead token + throw', () {
    test('createEvent → 401 clears token + throws', () async {
      await seedToken('event-c-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealEventService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.createEvent(_sampleEvent()),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/events');
      expect(req.headers['Authorization'], 'Bearer event-c-tok');
    });

    test('updateEvent → 401 clears token + throws', () async {
      await seedToken('event-u-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealEventService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.updateEvent(_sampleEvent()),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/api/events/');
      expect(req.headers['Authorization'], 'Bearer event-u-tok');
    });

    test('deleteEvent → 401 clears token + throws', () async {
      await seedToken('event-d-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealEventService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
        client: recorder,
      );

      await expectLater(
        svc.deleteEvent('e-9'),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/api/events/e-9');
      expect(req.headers['Authorization'], 'Bearer event-d-tok');
    });
  });

  group('Category write paths clear dead token + throw', () {
    test('createLargeCategory → 401 clears token + throws', () async {
      await seedToken('lc-c-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealProductService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
      );

      await expectLater(
        http.runWithClient(
          () => svc.createLargeCategory('Ao'),
          () => recorder,
        ),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/large-categories');
      expect(req.headers['Authorization'], 'Bearer lc-c-tok');
    });

    test('deleteLargeCategory → 401 clears token + throws', () async {
      await seedToken('lc-d-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealProductService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
      );

      await expectLater(
        http.runWithClient(
          () => svc.deleteLargeCategory('Ao'),
          () => recorder,
        ),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/api/large-categories/Ao');
      expect(req.headers['Authorization'], 'Bearer lc-d-tok');
    });

    test('createCategoryWithParent → 401 clears token + throws', () async {
      await seedToken('cat-c-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealProductService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
      );

      await expectLater(
        http.runWithClient(
          () => svc.createCategoryWithParent('Ao', 'ThoiTrang'),
          () => recorder,
        ),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/categories');
      expect(req.headers['Authorization'], 'Bearer cat-c-tok');
    });

    test('deleteCategory → 401 clears token + throws', () async {
      await seedToken('cat-d-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealProductService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
      );

      await expectLater(
        http.runWithClient(
          () => svc.deleteCategory('Ao'),
          () => recorder,
        ),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      expect(await currentStoredToken(), isNull);
      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/api/categories/Ao');
      expect(req.headers['Authorization'], 'Bearer cat-d-tok');
    });
  });

  group('End-to-end: cleared token means no Authorization on next write', () {
    test(
      'after a 401, the second createProduct call does NOT carry '
      'the dead credential (round-trip pin)',
      () async {
        await seedToken('round-trip-tok');

        final recorder = _RecordingClient();
        recorder.statusQueue.addAll([401, 200]);
        recorder.bodyQueue.addAll([
          '{"error":"admin session required"}',
          '{"id":"p1","name":"x","description":"d","price":1,'
              '"image_url":"","images":[],"category":"All",'
              '"categories":["All"],"specs":[],"rating":0,"reviews":0}',
        ]);

        final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
        final svc = RealProductService(
          baseUrl: 'http://localhost:8080',
          authService: auth,
        );

        // First call → must throw and clear the token.
        await expectLater(
          http.runWithClient(
            () => svc.createProduct(_sampleProduct()),
            () => recorder,
          ),
          throwsA(isA<AdminSessionExpiredException>()),
        );

        // Token should be gone.
        final tokenAfter = await currentStoredToken();
        expect(tokenAfter, isNull,
            reason: 'detectAdminSessionExpiry must clear the stored '
                'token on 401 "admin session required" — otherwise the '
                'next write keeps carrying a dead credential.');

        // Second call → must NOT carry Authorization.
        await http.runWithClient(
          () async {
            try {
              await svc.createProduct(_sampleProduct());
            } catch (_) {
              // We don't care if the second call's response is a
              // failure — only that the request went out without
              // the now-dead bearer.
            }
          },
          () => recorder,
        );

        expect(recorder.requests, hasLength(2));
        final secondReq = recorder.requests[1];
        expect(
          secondReq.headers.containsKey('Authorization'),
          isFalse,
          reason: 'after clearStoredToken, no token means no '
              'Authorization header — same contract as the no-token '
              'precondition case.',
        );
      },
    );
  });

  group('Sanity pin: store service helper still works', () {
    // The store service was already wired with
    // detectAdminSessionExpiry on its updateStoreInfo. Pinning it
    // here so we know the helper itself behaves as expected.
    test('updateStoreInfo → 401 clears token + throws', () async {
      await seedToken('store-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 401;
      recorder.nextBody = '{"error":"admin session required"}';

      final auth = RealAdminAuthService(baseUrl: 'http://localhost:8080');
      final svc = RealStoreService(
        baseUrl: 'http://localhost:8080',
        authService: auth,
      );

      await expectLater(
        http.runWithClient(
          () => svc.updateStoreInfo(_sampleStoreInfo()),
          () => recorder,
        ),
        throwsA(isA<AdminSessionExpiredException>()),
      );

      final tokenAfter = await currentStoredToken();
      expect(tokenAfter, isNull);

      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.single.headers['Authorization'],
          'Bearer store-tok');
    });
  });
}
