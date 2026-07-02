import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/admin_viewmodel.dart';
import 'admin_articles.dart';
import 'admin_auth_gate.dart';
import 'admin_categories.dart';
import 'admin_events.dart';
import 'admin_product/admin_product_screen.dart';
import 'admin_settings.dart';

/// App shell for the admin section. Hosts the responsive
/// navigation (NavigationRail on tablet/desktop, Drawer on mobile)
/// and renders the active admin tab in [body].
///
/// The shell is opened directly from the home screen — there is no
/// separate "dashboard" landing tab. [AdminProductsScreen] is the
/// default destination (`_selectedTab` defaults to `'products'`
/// in [AdminViewModel]).
///
/// StatefulWidget (instead of plain `StatelessWidget`) so the shell
/// can react to [AdminViewModel.adminSessionExpired] transitions:
/// when the cached Bearer token is rejected by the server (e.g. after
/// a restart) every write returns 401, the view-model sets the flag,
/// and this shell pops back to [AdminAuthGate] so the user can
/// re-authenticate.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool _redirecting = false;

  @override
  Widget build(BuildContext context) => Consumer<AdminViewModel>(
        builder: (context, viewModel, _) {
          // Route back to the auth gate when a write failed because
          // the cached token is no longer valid. Done in a post-frame
          // callback so the [Navigator] push happens outside the
          // build pass — calling `push` from inside `build` throws
          // "Navigator is currently locked".
          if (viewModel.adminSessionExpired && !_redirecting) {
            _redirecting = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Guard against the widget being unmounted before the
              // post-frame callback fires (e.g. user already pressed
              // back). Without `mounted` the [Navigator] lookup can
              // hit a disposed State.
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                fadeSlideRoute(const AdminAuthGate()),
                // Keep the home screen underneath; everything above
                // it (the now-dead admin shell) is removed.
                (route) => route.isFirst,
              );
            });
          }

          final bool useRail = context.useNavigationRail;
          final scheme = Theme.of(context).colorScheme;

          final Widget navigation = useRail
              ? NavigationRail(
                  selectedIndex: _getTabIndex(viewModel.selectedTab),
                  onDestinationSelected: (index) {
                    const tabs = [
                      'products',
                      'categories',
                      'articles',
                      'events',
                      'settings',
                    ];
                    viewModel.selectTab(tabs[index]);
                  },
                  labelType: context.useFullNavigationRail
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Sản phẩm'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.category_outlined),
                      selectedIcon: Icon(Icons.category),
                      label: Text('Danh mục'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.article_outlined),
                      selectedIcon: Icon(Icons.article),
                      label: Text('Bài viết'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.local_offer_outlined),
                      selectedIcon: Icon(Icons.local_offer),
                      label: Text('Sự kiện'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Cài đặt'),
                    ),
                  ],
                )
              : Drawer(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      DrawerHeader(
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.admin_panel_settings,
                                size: 48,
                                color: scheme.onPrimaryContainer,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Admin',
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ...[
                        (tab: 'products', label: 'Sản phẩm', icon: Icons.inventory_2_outlined),
                        (tab: 'categories', label: 'Danh mục', icon: Icons.category_outlined),
                        (tab: 'articles', label: 'Bài viết', icon: Icons.article_outlined),
                        (tab: 'events', label: 'Sự kiện', icon: Icons.local_offer_outlined),
                        (tab: 'settings', label: 'Cài đặt', icon: Icons.settings_outlined),
                      ].map(
                        (t) => ListTile(
                          leading: Icon(t.icon),
                          title: Text(t.label),
                          selected: viewModel.selectedTab == t.tab,
                          onTap: () {
                            viewModel.selectTab(t.tab);
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    ],
                  ),
                );

          return Scaffold(
            appBar: AppBar(
              title: const Text('Quản trị'),
              centerTitle: true,
              // Always render an explicit back button — admins need a
              // clear way to return to the home screen regardless of
              // viewport (rail mode on tablet/desktop hides the auto-
              // implied leading arrow).
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Quay lại menu',
                onPressed: () => Navigator.of(context).pop(),
              ),
              // On mobile the existing explicit `leading` suppresses
              // Material's auto-implied hamburger, so the admin would
              // otherwise be unable to open the Drawer and switch tabs.
              // Add a top-right menu button gated on `!useRail` so it
              // only appears when the Drawer is actually present.
              //
              // The [Builder] is required because `Scaffold.of`
              // must be called from a context that is a descendant of
              // the Scaffold. The outer `context` here belongs to the
              // `Consumer<AdminViewModel>`, which is a sibling of the
              // Scaffold — `Scaffold.of(context)` from there would
              // throw. `innerContext` from the Builder sits under the
              // Scaffold, so the lookup succeeds.
              actions: [
                if (!useRail)
                  Builder(
                    builder: (innerContext) => IconButton(
                      icon: const Icon(Icons.menu),
                      tooltip: 'Menu quản trị',
                      onPressed: () => Scaffold.of(innerContext).openDrawer(),
                    ),
                  ),
              ],
            ),
            drawer: useRail ? null : (navigation as Drawer),
            body: Row(
              children: [
                if (useRail)
                  SizedBox(width: context.adminRailWidth, child: navigation),
                Expanded(child: _buildTabContent(viewModel.selectedTab)),
              ],
            ),
          );
        },
      );

  int _getTabIndex(String tab) {
    switch (tab) {
      case 'products':
        return 0;
      case 'categories':
        return 1;
      case 'articles':
        return 2;
      case 'events':
        return 3;
      case 'settings':
        return 4;
      default:
        return 0;
    }
  }

  Widget _buildTabContent(String tab) {
    switch (tab) {
      case 'products':
        return const AdminProductsScreen();
      case 'categories':
        return const AdminCategoriesScreen();
      case 'articles':
        return const AdminArticlesScreen();
      case 'events':
        return const AdminEventsScreen();
      case 'settings':
        return const AdminSettingsScreen();
      default:
        return const AdminProductsScreen();
    }
  }
}
