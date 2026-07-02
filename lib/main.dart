import 'dart:async';
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
  // bundle doesn't contain `.env` — e.g. a stale `flutter run`
  // session started before the asset was registered in
  // `pubspec.yaml`. [ApiConfig.apiBaseUrl] already falls back to
  // `http://localhost:8080` when dotenv has no value for the key,
  // so a missing file degrades to "use the local default" instead
  // of crashing the whole app. A `flutter clean && flutter pub
  // get` is still required to pick up the `.env` asset on the
  // next cold start.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: '.env', isOptional: true);
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
  Widget build(BuildContext context) {
    // Services are created at this level (not inside MultiProvider)
    // so we can pass them by reference into the [ChangeNotifierProvider]
    // constructors via closures. Doing `context.read<IStoreService>()`
    // inside a `create:` callback doesn't work — the provider isn't
    // registered yet at that point in MultiProvider's mount cycle,
    // and `context.read` throws [ProviderNotFoundException].
    final authService = RealAdminAuthService();
    final productService = RealProductService(authService: authService);
    final articleService = RealArticleService(authService: authService);
    final eventService = RealEventService(authService: authService);
    final storeService = RealStoreService(authService: authService);
    return MultiProvider(
      providers: [
        // The service providers expose the same instances above
        // so any widget in the tree can `context.read<IProductService>()`
        // and get the auth-wired one. Order doesn't matter — they're
        // pure value providers.
        Provider<IAdminAuthService>.value(value: authService),
        Provider<IProductService>.value(value: productService),
        Provider<IArticleService>.value(value: articleService),
        Provider<IEventService>.value(value: eventService),
        Provider<IStoreService>.value(value: storeService),

        ChangeNotifierProvider(create: (_) => HomeViewModel()),
        // AdminViewModel owns the entire admin product catalogue
        // (CRUD state, image upload buffers, options editor draft).
        // It is heavy and used only when the admin dashboard is
        // opened — lazy so we don't pay its constructor + initial
        // state on cold start for the 99% of visitors who never
        // open admin.
        ChangeNotifierProvider(
          // Wire the shared service (with auth) into AdminViewModel
          // so admin write requests carry `Authorization: Bearer`.
          // Without this the fallback `RealProductService()` would
          // skip auth and the backend returns 401.
          create: (_) => AdminViewModel(
            productService: productService,
          ),
          lazy: true,
        ),
        ChangeNotifierProvider(
          // Wire the shared [IStoreService] (with auth) so PUT
          // /api/store-info carries `Authorization: Bearer`. Without
          // this the fallback `RealStoreService()` would skip auth
          // and the backend returns 401.
          create: (_) => SiteConfigViewModel(service: storeService)..load(),
        ),
        ChangeNotifierProvider(create: (_) => ArticlesViewModel()..load()),
        // Admin "Sự kiện" tab. Lazy so cold-start customers don't
        // pay for the initial GET unless the admin dashboard opens.
        ChangeNotifierProvider(
          create: (_) => EventsViewModel(),
          lazy: true,
        ),
        // Admin auth: a [ChangeNotifier] so the gate UI can listen
        // for state transitions (idle / loading / success / error).
        ChangeNotifierProvider(create: (_) => AdminAuthViewModel()),
      ],
      child: const _AppShell(),
    );
  }
}

/// Root chrome: lives *inside* the Provider tree so it can
/// [Consumer] the [SiteConfigViewModel], and wraps a [MaterialApp]
/// whose [MaterialApp.title] is computed from the admin-saved store
/// name (falling back to a sane default while the load is still in
/// flight).
///
/// We also push the title into the browser tab via a
/// [_BrowserTitleSyncer] widget — that path survives navigation
/// push/pop because it sits in the root of the widget tree, not in
/// a per-screen [State].
class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) => Consumer<SiteConfigViewModel>(
        builder: (context, vm, _) {
          final name = vm.siteInfo.name.trim();
          // Fall back while the first load is still in flight so the
          // tab is never blank.
          final label = name.isEmpty ? 'simshop' : name;
          return MaterialApp(
            title: label,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.light,
            // Keep document.title in sync on the web build. The
            // [BrowserTitleSyncer] is a no-op on mobile/desktop where
            // `document.title` is unused.
            home: const _BrowserTitleSyncer(child: HomeScreen()),
          );
        },
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lazy-init the manager once. [SiteConfigViewModel] lives at the
    // root [MultiProvider] and never gets swapped, so a single
    // construction is enough for the lifetime of this [State].
    _manager ??= BrowserTitleManager(
      siteConfig: context.read<SiteConfigViewModel>(),
    );
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
