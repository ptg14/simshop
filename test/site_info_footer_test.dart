import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:simshop/models/store_info.dart';
import 'package:simshop/services/admin_auth_service.dart';
import 'package:simshop/services/store_service.dart';
import 'package:simshop/viewmodels/admin_auth_viewmodel.dart';
import 'package:simshop/viewmodels/site_config_viewmodel.dart';
import 'package:simshop/views/admin/admin_auth_gate.dart';
import 'package:simshop/widgets/admin_banner_trigger.dart';
import 'package:simshop/widgets/home_skeleton.dart';
import 'package:simshop/widgets/network_image.dart';
import 'package:simshop/widgets/site_info_footer.dart';

/// In-memory [IStoreService] — same shape as the fake in
/// `test/site_config_viewmodel_test.dart`. Lets the test seed the
/// footer with any [StoreInfo] without touching the network.
class _FakeStoreService implements IStoreService {
  _FakeStoreService([StoreInfo? initial]) : _info = initial ?? const StoreInfo();

  StoreInfo _info;

  set info(StoreInfo value) => _info = value;

  @override
  Future<StoreInfo> getStoreInfo() async => _info;

  @override
  Future<StoreInfo> updateStoreInfo(
    StoreInfo info, {
    String? oldBannerUrl,
  }) async {
    _info = info;
    return _info;
  }
}

/// Minimal [IAdminAuthService] so [AdminAuthGate]'s `initState`
/// post-frame `hasStoredToken()` check resolves cleanly without
/// spinning up `SharedPreferences` or hitting the network. Returning
/// `null` from [getStoredToken] makes the gate stay on the file-picker
/// screen — exactly what the gesture-navigation tests need to assert
/// that the push happened (the gate would otherwise auto-replace to
/// the admin shell).
class _FakeAdminAuthService implements IAdminAuthService {
  String? _storedToken;

  @override
  Future<String> requestChallenge() async => 'nonce';

  @override
  Future<String> verify({
    required String nonce,
    required String signatureHex,
    required Uint8List secretKeyBytes,
  }) async =>
      'tok';

  @override
  Future<void> logout() async => _storedToken = null;

  @override
  Future<String?> getStoredToken() async => _storedToken;

  @override
  Future<void> clearStoredToken() async => _storedToken = null;
}

// Block body on purpose — the inline comments inside explain the
// non-obvious choice to wrap MaterialApp in MultiProvider instead of
// nesting it under `home:`. Collapsing to `=> MultiProvider(...)`
// would silently drop the rationale.
// ignore: prefer_expression_function_bodies
Widget _wrap(Widget child, {StoreInfo? seed}) {
  // Providers MUST wrap MaterialApp (not just `home:`) so the new
  // AdminAuthGate route — pushed via `Navigator.of(context).push(...)`
  // — sits under the same MultiProvider. If they live below
  // `MaterialApp.home`, the pushed route resolves a new BuildContext
  // that can't `context.read<AdminAuthViewModel>()` and throws
  // ProviderNotFoundException in initState.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SiteConfigViewModel>(
        // `..load()` so the VM holds the seeded StoreInfo before
        // the first frame. The fake resolves synchronously, so a
        // single pumpAndSettle picks up the populated state.
        create: (_) =>
            SiteConfigViewModel(service: _FakeStoreService(seed))..load(),
      ),
      ChangeNotifierProvider<AdminAuthViewModel>(
        create: (_) => AdminAuthViewModel(service: _FakeAdminAuthService()),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  // ───────────────────────────── AdminBannerTrigger ──────────────────────

  testWidgets(
      'AdminBannerTrigger: 7 taps push AdminAuthGate, 6 taps do not',
      (tester) async {
    await tester.pumpWidget(_wrap(
      Scaffold(
        body: Center(
          child: AdminBannerTrigger(
            child: Container(
              width: 100,
              height: 100,
              color: Colors.grey,
              child: const Icon(Icons.image_outlined),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final banner = find.byIcon(Icons.image_outlined);

    // Six taps is below the threshold.
    for (var i = 0; i < 6; i++) {
      await tester.tap(banner);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byType(AdminAuthGate), findsNothing,
        reason: '6 taps is below the 7-tap threshold');

    // The 7th tap crosses the threshold.
    await tester.tap(banner);
    await tester.pumpAndSettle();
    expect(find.byType(AdminAuthGate), findsOneWidget,
        reason: 'the 7th tap crosses the threshold');
  });

  // ───────────────────────────── SiteInfoFooter ──────────────────────────

  testWidgets(
      'SiteInfoFooter renders a banner placeholder when StoreInfo is empty',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const SiteInfoFooter(), seed: const StoreInfo.empty()),
    );
    await tester.pumpAndSettle();

    // Card is now visible (regression: used to return SizedBox.shrink()).
    expect(find.byType(Card), findsOneWidget);
    // The banner slot is mounted and gesture-enabled.
    expect(find.byType(AdminBannerTrigger), findsOneWidget);
    // Placeholder icon present, the live-banner widget is not.
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(AppNetworkImage), findsNothing);
    // No store name on empty info — the card is banner-only.
    expect(find.text('simshop'), findsNothing);
  });

  testWidgets(
      'SiteInfoFooter renders the live banner when StoreInfo has a bannerUrl',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SiteInfoFooter(),
        seed: const StoreInfo(
          name: 'Cửa hàng ABC',
          bannerUrl: 'https://example.test/banner.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Real banner is mounted, placeholder is not.
    expect(find.byType(AppNetworkImage), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsNothing);
    // Gesture trigger still wraps the banner.
    expect(find.byType(AdminBannerTrigger), findsOneWidget);
    // Store name is visible.
    expect(find.text('Cửa hàng ABC'), findsOneWidget);
  });

  testWidgets(
      'SiteInfoFooter: 7 taps on the empty-banner placeholder push AdminAuthGate',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const SiteInfoFooter(), seed: const StoreInfo.empty()),
    );
    await tester.pumpAndSettle();

    final placeholder = find.byIcon(Icons.image_outlined);
    expect(placeholder, findsOneWidget);

    // Seven synchronous taps fit inside the 3 s window — `DateTime.now`
    // only advances on `tester.pump(Duration)` so without explicit
    // delays the difference between the first and last tap is
    // microseconds, well inside the threshold.
    for (var i = 0; i < 7; i++) {
      await tester.tap(placeholder);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.byType(AdminAuthGate), findsOneWidget);
  });

  // ───────────────────────────── HomeSkeleton ────────────────────────────

  // The store banner lives inside [SiteInfoFooter] (at the bottom
  // of the page) — not inline in the skeleton. [HomeSkeleton]
  // mounts the footer so the admin entry-point is reachable while
  // products are still loading. On a freshly-initialized DB
  // ([StoreInfo.empty]) the footer renders a banner-only
  // placeholder card; otherwise it shows the live banner plus the
  // store identity.

  testWidgets(
      'HomeSkeleton renders SiteInfoFooter with a banner placeholder so the '
      'admin entry-point is reachable during the loading state',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const HomeSkeleton(), seed: const StoreInfo.empty()),
    );
    // HomeSkeleton wraps the loading-state placeholders in a
    // ShimmerPlaceholder whose AnimationController runs
    // `..repeat()` forever, so `pumpAndSettle` would time out.
    // Pump a finite duration to let the first frame land — that's
    // enough to verify the widget tree is built. The footer lives
    // outside the shimmer so it doesn't get blended by the
    // gradient.
    await tester.pump(const Duration(milliseconds: 100));

    // The footer mounts at the bottom of the skeleton. Its
    // [AdminBannerTrigger] wrapper is gesture-enabled, and on the
    // empty-DB seed the banner slot is a placeholder icon.
    expect(find.byType(SiteInfoFooter), findsOneWidget);
    expect(find.byType(AdminBannerTrigger), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets(
      'HomeSkeleton: 7 taps on the footer banner placeholder push '
      'AdminAuthGate', (tester) async {
    await tester.pumpWidget(
      _wrap(const HomeSkeleton(), seed: const StoreInfo.empty()),
    );
    // HomeSkeleton wraps the loading-state placeholders in a
    // ShimmerPlaceholder whose AnimationController runs
    // `..repeat()` forever, so `pumpAndSettle` would time out.
    // Pump a finite duration to let the first frame land.
    await tester.pump(const Duration(milliseconds: 100));

    // The footer (with the placeholder banner) lives at the
    // bottom of the page — well below the 800×600 test viewport
    // on a fresh paint. Scroll it into view before tapping so
    // `tester.tap` resolves an offset inside the render tree.
    final placeholder = find.byIcon(Icons.image_outlined);
    expect(placeholder, findsOneWidget);
    await tester.scrollUntilVisible(placeholder, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 100));

    // Seven synchronous taps fit inside the 3 s window —
    // `DateTime.now` only advances on `tester.pump(Duration)` so
    // without explicit delays the difference between the first
    // and last tap is microseconds, well inside the threshold.
    for (var i = 0; i < 7; i++) {
      await tester.tap(placeholder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 1));
    }
    // One more finite pump (not pumpAndSettle — the
    // ShimmerPlaceholder still has an infinite repeat).
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AdminAuthGate), findsOneWidget);
  });
}