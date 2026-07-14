// Regression tests for the wiring of admin-write viewmodels in
// lib/main.dart other than AdminViewModel (which has its own file —
// test/admin_viewmodel_wiring_test.dart).
//
// The bug: lib/main.dart registers SiteConfigViewModel,
// ArticlesViewModel, and EventsViewModel as plain
// `ChangeNotifierProvider`s with `create: (_) => VM()`. Each VM's
// no-arg constructor falls back to `Real*Service()` (no authService),
// so any write from those VMs sends requests without `Authorization`
// → backend 401 → user sees "phiên đã hết hạn". The diagnostic match
// the user reported for store-info (PUT /api/store-info 401 with no
// Authorization header) and would match the same shape for create /
// update article and create / update event.
//
// The fix pattern is the same one already applied to AdminViewModel:
// convert each VM to `ChangeNotifierProxyProvider<TDep, TVM>` with
// `create: (ctx) => VM(service: ctx.read<TDep>())`, so the wired
// service (with IAdminAuthService already injected) reaches the VM.
//
// Each test below pumps a small MultiProvider subtree that mirrors
// the *fixed* wiring for the VM under test and asserts that an
// admin write reaches the wire with `Authorization: Bearer <token>`
// attached. The negative half (no `Authorization` when the buggy
// wiring is used) is covered by AdminViewModel's own test file; the
// goal here is to lock each additional VM's wire shape so the same
// fix lands for all of them.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simshop/models/article.dart';
import 'package:simshop/models/event.dart';
import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/admin_auth_service.dart';
import 'package:simshop/services/article_service.dart';
import 'package:simshop/services/event_service.dart';
import 'package:simshop/services/store_service.dart';
import 'package:simshop/viewmodels/articles_viewmodel.dart';
import 'package:simshop/viewmodels/events_viewmodel.dart';
import 'package:simshop/viewmodels/site_config_viewmodel.dart';

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

StoreInfo _sampleStoreInfo() => const StoreInfo(
      name: 'Cửa hàng test',
      description: 'desc',
      bannerUrl: '',
      phone: '',
      email: '',
      address: '',
      googleMapsUrl: '',
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
      productIds: const [],
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'SiteConfigViewModel (fixed wiring) → PUT /api/store-info '
    'attaches Authorization: Bearer <token>',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAdminTokenStorageKey, 'sitecfg-tok');

      // Mirror lib/main.dart's wiring for SiteConfigViewModel after
      // the fix (ChangeNotifierProxyProvider reading IStoreService).
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<IAdminAuthService>(
              create: (_) => RealAdminAuthService(),
              lazy: true,
            ),
            Provider<IStoreService>(
              create: (ctx) => RealStoreService(
                authService: ctx.read<IAdminAuthService>(),
              ),
              lazy: true,
            ),
            ChangeNotifierProxyProvider<IStoreService, SiteConfigViewModel>(
              create: (ctx) =>
                  SiteConfigViewModel(service: ctx.read<IStoreService>()),
              update: (_, service, prev) =>
                  prev ?? SiteConfigViewModel(service: service),
              lazy: true,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MaterialApp));
      final vm = Provider.of<SiteConfigViewModel>(element, listen: false);
      expect(vm, isNotNull);

      final recorder = _RecordingClient();
      recorder.nextStatus = 200;
      // Stage a response body that the real StoreService can decode.
      // The PUT round-trip returns the persisted StoreInfo as JSON
      // with the snake_case keys the backend uses.
      recorder.nextBody = json.encode({
        'name': 'Cửa hàng test',
        'description': 'desc',
        'banner_url': '',
        'phone': '',
        'email': '',
        'address': '',
        'google_maps_url': '',
      });

      await http.runWithClient(
        () => vm.update(_sampleStoreInfo()),
        () => recorder,
      );

      expect(recorder.requests, hasLength(1),
          reason: 'one PUT must reach the wire');
      final req = recorder.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/api/store-info');
      expect(
        req.headers['Authorization'],
        'Bearer sitecfg-tok',
        reason:
            'SiteConfigViewModel must hold the wired IStoreService '
            '(with IAdminAuthService injected) so PUT /api/store-info '
            'carries the Bearer token. Production bug (turn 7) — the '
            'fix is to convert SiteConfigViewModel from a plain '
            'ChangeNotifierProvider with `create: (_) => '
            'SiteConfigViewModel()` into a ChangeNotifierProxyProvider '
            'with `create: (ctx) => SiteConfigViewModel(service: '
            'ctx.read<IStoreService>())`.',
      );
    },
  );

  testWidgets(
    'ArticlesViewModel (fixed wiring) → POST /api/articles attaches '
    'Authorization: Bearer <token>',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAdminTokenStorageKey, 'articles-tok');

      // [RealArticleService] uses its own `http.Client` field for
      // POST/PUT/DELETE — not `http.post` directly. `runWithClient`
      // only intercepts the global `http.post`/`http.get` static
      // helpers, so we have to inject the recorder into the service
      // directly via the `client` constructor arg.
      final recorder = _RecordingClient();
      recorder.nextStatus = 201;
      recorder.nextBody = '{"id":"a1","title":"Bài viết test","body":""}';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<IAdminAuthService>(
              create: (_) => RealAdminAuthService(),
              lazy: true,
            ),
            Provider<IArticleService>(
              create: (ctx) => RealArticleService(
                authService: ctx.read<IAdminAuthService>(),
                client: recorder,
              ),
              lazy: true,
            ),
            ChangeNotifierProxyProvider<IArticleService, ArticlesViewModel>(
              create: (ctx) =>
                  ArticlesViewModel(service: ctx.read<IArticleService>()),
              update: (_, service, prev) =>
                  prev ?? ArticlesViewModel(service: service),
              lazy: true,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MaterialApp));
      final vm = Provider.of<ArticlesViewModel>(element, listen: false);
      expect(vm, isNotNull);

      await vm.createArticle(_sampleArticle());

      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/articles');
      expect(
        req.headers['Authorization'],
        'Bearer articles-tok',
        reason:
            'ArticlesViewModel must hold the wired IArticleService '
            '(with IAdminAuthService injected). Fix matches the '
            'AdminViewModel pattern in test/admin_viewmodel_wiring_test.dart.',
      );
    },
  );

  testWidgets(
    'EventsViewModel (fixed wiring) → POST /api/events attaches '
    'Authorization: Bearer <token>',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAdminTokenStorageKey, 'events-tok');

      final recorder = _RecordingClient();
      recorder.nextStatus = 201;
      recorder.nextBody = json.encode({
        'id': 'e1',
        'name': 'Sự kiện test',
        'discount_type': 'percent',
        'discount_value': 10,
        'product_ids': <String>[],
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<IAdminAuthService>(
              create: (_) => RealAdminAuthService(),
              lazy: true,
            ),
            Provider<IEventService>(
              create: (ctx) => RealEventService(
                authService: ctx.read<IAdminAuthService>(),
                client: recorder,
              ),
              lazy: true,
            ),
            ChangeNotifierProxyProvider<IEventService, EventsViewModel>(
              create: (ctx) =>
                  EventsViewModel(service: ctx.read<IEventService>()),
              update: (_, service, prev) =>
                  prev ?? EventsViewModel(service: service),
              lazy: true,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MaterialApp));
      final vm = Provider.of<EventsViewModel>(element, listen: false);
      expect(vm, isNotNull);

      await vm.createEvent(_sampleEvent());

      expect(recorder.requests, hasLength(1));
      final req = recorder.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/events');
      expect(
        req.headers['Authorization'],
        'Bearer events-tok',
        reason:
            'EventsViewModel must hold the wired IEventService (with '
            'IAdminAuthService injected). Fix matches the '
            'AdminViewModel pattern in test/admin_viewmodel_wiring_test.dart.',
      );
    },
  );
}