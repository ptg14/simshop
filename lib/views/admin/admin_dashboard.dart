import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive.dart';
import '../../viewmodels/admin_viewmodel.dart';
import 'admin_articles.dart';
import 'admin_categories.dart';
import 'admin_overview.dart';
import 'admin_product/admin_product_screen.dart';
import 'admin_settings.dart';

/// Admin dashboard screen that provides navigation (Rail or Drawer) and
/// displays the selected admin tab.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AdminViewModel>(
        builder: (context, viewModel, _) {
          final bool useRail = context.useNavigationRail;
          final scheme = Theme.of(context).colorScheme;

          final Widget navigation = useRail
              ? NavigationRail(
                  selectedIndex: _getTabIndex(viewModel.selectedTab),
                  onDestinationSelected: (index) {
                    const tabs = ['overview', 'products', 'categories', 'settings'];
                    viewModel.selectTab(tabs[index]);
                  },
                  labelType: context.useFullNavigationRail
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Tổng quan'),
                    ),
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
                        (tab: 'overview', label: 'Tổng quan', icon: Icons.dashboard_outlined),
                        (tab: 'products', label: 'Sản phẩm', icon: Icons.inventory_2_outlined),
                        (tab: 'categories', label: 'Danh mục', icon: Icons.category_outlined),
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
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Đăng xuất'),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );

          return Scaffold(
            appBar: AppBar(
              title: const Text('Admin Dashboard'),
              centerTitle: true,
              automaticallyImplyLeading: !useRail,
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
      case 'overview':
        return 0;
      case 'products':
        return 1;
      case 'categories':
        return 2;
      case 'settings':
        return 3;
      default:
        return 0;
    }
  }

  Widget _buildTabContent(String tab) {
    switch (tab) {
      case 'overview':
        return const AdminOverviewScreen();
      case 'products':
        return const AdminProductsScreen();
      case 'categories':
        return const AdminCategoriesScreen();
      case 'settings':
        return const AdminSettingsScreen();
      default:
        return const AdminProductsScreen();
    }
  }
}
