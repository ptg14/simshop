import 'dart:async';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'config/api_config.dart';
import 'services/admin_auth_service.dart';
import 'services/article_service.dart';
import 'services/event_service.dart';
import 'services/product_service.dart';
import 'services/store_service.dart';
import 'theme/app_theme.dart';
import 'utils/browser_title_manager.dart';
import 'viewmodels/admin_auth_viewmodel.dart';
import 'viewmodels/admin_viewmodel.dart';
import 'viewmodels/articles_viewmodel.dart';
import 'viewmodels/events_viewmodel.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/site_config_viewmodel.dart';
import 'views/home_screen.dart';

final ValueNotifier<String?> _globalError = ValueNotifier(null);

void _setGlobalError(String text) {
  // Defer to the next frame so we never mutate [ValueNotifier] state
  // from inside a build pass. Without this, a throw during build
  // re-enters [FlutterError.onError], which set [value], which
  // triggered a rebuild via [ValueListenableBuilder], which threw
  // again — an infinite "setState() called during build" loop that
  // manifested as a flash of red error screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _globalError.value = text;
  });
}

void main() {
  // `ensureInitialized()` + `runApp()` MUST run in the same zone —
  // otherwise the Flutter framework throws "Zone mismatch" because
  // bindings are stashed on the Zone they're created in. The previous
  // version called `ensureInitialized` outside `runZonedGuarded` and
  // `runApp` inside it, which produced exactly that warning at every
  // cold start.
  //
  // Inside this single zone we:
  //   1. Initialize the binding (required before any Flutter API).
  //   2. Load `.env` so [ApiConfig.apiBaseUrl] returns the real URL.
  //   3. Print the resolved URL to the dev console (the first place
  //      to look when the home page can't reach the backend).
  //   4. Install the on-screen error reporter.
  //   5. runApp.
  //
  // `isOptional: true` lets the app boot even when the asset
  // bundle doesn't contain `.env` — e.g. a release Docker build
  // that no longer ships the asset. [ApiConfig.apiBaseUrl]
  // resolves to the compile-time `--dart-define` value when
  // dotenv has nothing to read, so a missing `.env` is harmless
  // as long as the build arg was passed.
  //
  // In release mode we SKIP the `dotenv.load()` call entirely:
  // `rootBundle.loadString('.env')` always fires an HTTP request
  // for `assets/.env` before reporting "not found" — even when
  // the asset is absent — and that request manifests as a 404 in
  // the browser console + an "Error while trying to load an
  // asset" log line from the Flutter engine. There's no value in
  // paying that cost in production where compile-time is the
  // single source of truth. Dev builds still call `dotenv.load()`
  // so a `flutter run` session picking up `.env` from the repo
  // root keeps working.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!kReleaseMode) {
      await dotenv.load(fileName: '.env', isOptional: true);
    }
    debugPrint('simshop: API_BASE_URL = ${ApiConfig.apiBaseUrl}');

    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details);
      _setGlobalError('${details.exceptionAsString()}\n${details.stack ?? ''}');
    };

    runApp(const GuardedApp());
  }, (error, stack) {
    // Catch all other errors
    _setGlobalError('$error\n$stack');
    // Also print to console
    Zone.current.handleUncaughtError(error, stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  // Block body on purpose — the inline comments above explain why
  // every service is `lazy: true` and how the dependency chain
  // (AdminViewModel → IProductService → IAdminAuthService) still
  // carries the Bearer token once admin opens. Collapsing to
  // `=> MultiProvider(...)` would silently drop the explanation.
  // ignore: prefer_expression_function_bodies
  Widget build(BuildContext context) {
    // Services are registered as **lazy** Providers below. None of
    // them is constructed at this level — `Provider<I*Service>.value`
    // with eager instances used to live here, which meant every cold
    // start allocated five service instances (and pulled in
    // `package:cryptography` via `RealAdminAuthService` plus
    // `package:image_picker` via `RealProductService`) regardless of
    // whether the user ever opens the admin dashboard.
    //
    // With `lazy: true` the constructor only runs when the first
    // widget does `context.read<I*Service>()`. The dependency chain
    // (e.g. `AdminViewModel` → `IProductService` → `IAdminAuthService`)
    // resolves through Provider's normal lookup, so admin write
    // requests still carry `Authorization: Bearer ...` once the user
    // actually opens admin.
    return MultiProvider(
      providers: [
        // Service providers. All `lazy: true` so cold-start users
        // (who never `context.read` any of these) don't pay for
        // their construction. Order doesn't matter — they're pure
        // value providers and the dependency tree resolves on first
        // `read`, not on registration.
        Provider<IAdminAuthService>(
          create: (_) => RealAdminAuthService(),
          lazy: true,
        ),
        Provider<IProductService>(
          // Wire the shared [IAdminAuthService] so admin write
          // requests carry `Authorization: Bearer`. The `read` inside
          // `create` is safe here because Provider's own machinery
          // resolves the dependency before constructing us — even
          // though `IAdminAuthService` is itself lazy.
          create: (ctx) =>
              RealProductService(authService: ctx.read<IAdminAuthService>()),
          lazy: true,
        ),
        Provider<IArticleService>(
          create: (ctx) =>
              RealArticleService(authService: ctx.read<IAdminAuthService>()),
          lazy: true,
        ),
        Provider<IEventService>(
          create: (ctx) =>
              RealEventService(authService: ctx.read<IAdminAuthService>()),
          lazy: true,
        ),
        Provider<IStoreService>(
          create: (ctx) =>
              RealStoreService(authService: ctx.read<IAdminAuthService>()),
          lazy: true,
        ),

        // HomeViewModel is now lazy as well — the home screen
        // paints its skeleton on the very first frame without ever
        // reading from a ChangeNotifier (see [HomeScreen] /
        // [HomeSkeleton]), so we don't construct this VM at
        // `MyApp.build` time any more. The VM gets built later,
        // inside the post-frame callback in [HomeScreen.initState],
        // which is the moment the screen actually starts caring
        // about products + categories.
        ChangeNotifierProvider(
          create: (_) => HomeViewModel(),
          lazy: true,
        ),
        // AdminViewModel owns the entire admin product catalogue
        // (CRUD state, image upload buffers, options editor draft).
        // It is heavy and used only when the admin dashboard is
        // opened — lazy so we don't pay its constructor + initial
        // state on cold start for the 99% of visitors who never
        // open admin.
        //
        // [ChangeNotifierProxyProvider] resolves `IProductService`
        // through the Provider chain and hands it to AdminViewModel
        // so admin writes carry `Authorization: Bearer`.
        //
        // `create` reads `IProductService` via `ctx.read` so the
        // first instance is constructed WITH the wired service —
        // critically, the service that has `IAdminAuthService`
        // injected. The naïve pattern `create: (_) =>
        // AdminViewModel()` looks tempting because AdminViewModel's
        // own constructor accepts an optional service, but it falls
        // back to `RealProductService()` (no auth) and the
        // subsequent `update` callback's `prev ?? newInstance`
        // traps that fallback instance forever. The result is admin
        // writes going out with no Authorization header → backend
        // 401 → user sees "phiên đã hết hạn". Regression test:
        // test/admin_viewmodel_wiring_test.dart pins the wire
        // shape after this provider chain.
        ChangeNotifierProxyProvider<IProductService, AdminViewModel>(
          create: (ctx) =>
              AdminViewModel(productService: ctx.read<IProductService>()),
          update: (_, productService, prev) =>
              prev ?? AdminViewModel(productService: productService),
          lazy: true,
        ),
        // SiteConfigViewModel backs the home footer + browser title
        // AND the admin settings tab. The admin-side update goes
        // through `PUT /api/store-info` which requires the Bearer
        // token — so the proxy pattern (same one used for
        // AdminViewModel above) threads the wired IStoreService
        // (with IAdminAuthService already injected) into the VM.
        // Without this, the no-arg constructor falls back to
        // `RealStoreService()` (no auth) and PUT goes out with no
        // `Authorization` header → backend 401. Same bug as the
        // original AdminViewModel wiring — pinned by
        // test/site_config_wiring_test.dart.
        ChangeNotifierProxyProvider<IStoreService, SiteConfigViewModel>(
          create: (ctx) =>
              SiteConfigViewModel(service: ctx.read<IStoreService>()),
          update: (_, service, prev) =>
              prev ?? SiteConfigViewModel(service: service),
          lazy: true,
        ),
        // ArticlesViewModel backs the home carousel (read-only path)
        // AND the admin "Bài viết" tab (writes articles + banners).
        // Same proxy pattern — without the wired IArticleService,
        // admin article/banner writes go out without `Authorization`.
        // Pinned by test/site_config_wiring_test.dart.
        ChangeNotifierProxyProvider<IArticleService, ArticlesViewModel>(
          create: (ctx) =>
              ArticlesViewModel(service: ctx.read<IArticleService>()),
          update: (_, service, prev) =>
              prev ?? ArticlesViewModel(service: service),
          lazy: true,
        ),
        // Admin "Sự kiện" tab. Same proxy pattern. Without the
        // wired IEventService, admin event writes go out without
        // `Authorization` → backend 401.
        // Pinned by test/site_config_wiring_test.dart.
        ChangeNotifierProxyProvider<IEventService, EventsViewModel>(
          create: (ctx) =>
              EventsViewModel(service: ctx.read<IEventService>()),
          update: (_, service, prev) =>
              prev ?? EventsViewModel(service: service),
          lazy: true,
        ),
        // Admin auth: a [ChangeNotifier] so the gate UI can listen
        // for state transitions (idle / loading / success / error).
        // Lazy for the same reason as the services above — only the
        // auth gate ever reads it.
        ChangeNotifierProvider(
          create: (_) => AdminAuthViewModel(),
          lazy: true,
        ),
      ],
      child: const _AppShell(),
    );
  }
}

/// Root chrome: wraps a [MaterialApp] whose title defaults to the
/// placeholder `"simshop"`.
///
/// We previously built a `Consumer<SiteConfigViewModel>` here so the
/// title could update from the admin-saved store name. Two reasons
/// that was wasteful:
///
///   * `Consumer` rebuilt the whole `MaterialApp` (and therefore the
///     underlying [Navigator]) every time the site info changed,
///     which happens at most twice in the app's lifetime — once when
///     the load finishes, once when the admin saves an edit.
///   * `MaterialApp.title` is only used as a *fallback* by the OS
///     (Android task label, iOS app-switcher label) and by
///     `Navigator` cleanup. The browser tab title on web is driven
///     directly by [BrowserTitleManager] via `document.title` and
///     doesn't even read `MaterialApp.title`.
///
/// [_BrowserTitleSyncer] still mounts at the root so title updates
/// survive navigation push/pop.
class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) => MaterialApp(
        // Static title. The runtime value comes from
        // [BrowserTitleManager] which writes `document.title`
        // directly on web; this string only matters for the OS
        // task-switcher / accessibility — keeping it static avoids
        // rebuilding the Navigator when the store name loads.
        title: 'simshop',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.light,
        // Keep document.title in sync on the web build. The
        // [BrowserTitleSyncer] is a no-op on mobile/desktop where
        // `document.title` is unused.
        home: const _BrowserTitleSyncer(child: HomeScreen()),
      );
}

/// Drives [BrowserTitleManager] from the widget tree. Mounted once
/// at the app root so it persists across navigation push/pop, and
/// cleanly releases its listener on disposal.
class _BrowserTitleSyncer extends StatefulWidget {
  const _BrowserTitleSyncer({required this.child});
  final Widget child;

  @override
  State<_BrowserTitleSyncer> createState() => _BrowserTitleSyncerState();
}

class _BrowserTitleSyncerState extends State<_BrowserTitleSyncer> {
  BrowserTitleManager? _manager;
  bool _kickedOffLoads = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lazy-init the manager once. [SiteConfigViewModel] lives at the
    // root [MultiProvider] and never gets swapped, so a single
    // construction is enough for the lifetime of this [State].
    //
    // The `context.read` call also forces [SiteConfigViewModel] to
    // construct (it's lazy). This is the *aux* wave of HTTP — the
    // critical wave (products + Large categories) is fired by
    // [HomeScreen.initState] one frame later via
    // `HomeViewModel.loadCriticalData`. Here we kick off the polish
    // endpoints that don't gate the first useful paint:
    //   • site config (browser tab title + footer card),
    //   • article banners (carousel at the top of the home grid).
    //
    // Doing the read here (instead of in `MyApp.build` with
    // `..load()`) means the underlying services are only allocated
    // when the app actually mounts the home screen, never during a
    // synchronous eager path.
    final siteConfig = context.read<SiteConfigViewModel>();
    _manager ??= BrowserTitleManager(siteConfig: siteConfig);

    if (!_kickedOffLoads) {
      _kickedOffLoads = true;
      // Post-frame so we never fire HTTP from inside a build pass.
      // Also resolves [ArticlesViewModel] lazily — only the home
      // screen's banner carousel reads it, so triggering the load
      // here is enough.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        siteConfig.load();
        context.read<ArticlesViewModel>().load();
      });
    }
  }

  @override
  void dispose() {
    _manager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class GuardedApp extends StatelessWidget {
  const GuardedApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
        valueListenable: _globalError,
        builder: (context, error, _) {
          if (error != null) {
            return MaterialApp(
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: ThemeMode.light,
              home: Scaffold(
                appBar: AppBar(title: const Text('Runtime Error')),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(error,
                      style: const TextStyle(color: Colors.red)),
                ),
              ),
            );
          }
          return const MyApp();
        },
      );
}
