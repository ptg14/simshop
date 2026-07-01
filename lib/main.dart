import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/analytics_service.dart';
import 'services/article_service.dart';
import 'services/event_service.dart';
import 'services/product_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/admin_viewmodel.dart';
import 'viewmodels/articles_viewmodel.dart';
import 'viewmodels/events_viewmodel.dart';
import 'viewmodels/home_viewmodel.dart';
import 'viewmodels/site_config_viewmodel.dart';
import 'views/home_screen.dart';

final ValueNotifier<String?> _globalError = ValueNotifier(null);

void main() {
  // Surface uncaught Flutter errors and async errors on-screen for debugging
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    _globalError.value = '${details.exceptionAsString()}\n${details.stack ?? ''}';
  };

  runZonedGuarded(() {
    runApp(const GuardedApp());
  }, (error, stack) {
    // Catch all other errors
    _globalError.value = '$error\n$stack';
    // Also print to console
    Zone.current.handleUncaughtError(error, stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => HomeViewModel()),
          // AdminViewModel owns the entire admin product catalogue
          // (CRUD state, image upload buffers, options editor draft).
          // It is heavy and used only when the admin dashboard is
          // opened — lazy so we don't pay its constructor + initial
          // state on cold start for the 99% of visitors who never
          // open admin.
          ChangeNotifierProvider(
            create: (_) => AdminViewModel(),
            lazy: true,
          ),
          ChangeNotifierProvider(create: (_) => SiteConfigViewModel()..load()),
          ChangeNotifierProvider(create: (_) => ArticlesViewModel()..load()),
          // Admin "Sự kiện" tab. Lazy so cold-start customers don't
          // pay for the initial GET unless the admin dashboard opens.
          ChangeNotifierProvider(
            create: (_) => EventsViewModel(),
            lazy: true,
          ),
          // Service providers — required by widgets that
          // context.read<IProductService>() / IArticleService().
          // 78f3492 added the ArticlesViewModel provider but the
          // banner dialog still crashed on Flutter Web because the
          // underlying services were not in the tree.
          Provider<IProductService>(create: (_) => RealProductService()),
          Provider<IArticleService>(create: (_) => RealArticleService()),
          Provider<IEventService>(create: (_) => RealEventService()),
          // Pageview tracking — fire-and-forget; called from
          // HomeViewModel.initialize and ProductDetailScreen.initState.
          Provider<IAnalyticsService>(create: (_) => RealAnalyticsService()),
        ],
        child: MaterialApp(
          title: 'Sample E-commerce App',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.light,
          home: const HomeScreen(),
        ),
      );
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
