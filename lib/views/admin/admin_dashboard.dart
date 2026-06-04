import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/admin_viewmodel.dart';
import 'admin_overview.dart';
import 'admin_products.dart';
import 'admin_categories.dart';
import 'admin_analytics.dart';
import 'admin_settings.dart';

/// Admin dashboard screen that provides navigation (Rail or Drawer) and
/// displays the selected admin tab.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // Use a Consumer to obtain the AdminViewModel.
    return Consumer<AdminViewModel>(
      builder: (context, viewModel, _) {
        // Determine whether to use a NavigationRail (wide screens) or a Drawer.
        final bool useRail = MediaQuery.of(context).size.width > 600;

        // Build the navigation widget based on the layout choice.
        final Widget navigation = useRail
            ? NavigationRail(
                selectedIndex: _getTabIndex(viewModel.selectedTab),
                onDestinationSelected: (index) {
                  const tabs = [
                    'overview',
                    'products',
                    // upload tab removed – merged into products
                    'categories',
                    'analytics',
                    'settings',
                  ];
                  viewModel.selectTab(tabs[index]);
                },
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Tổng quan'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.inventory_2),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: Text('Sản phẩm'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.category),
                    selectedIcon: Icon(Icons.category),
                    label: Text('Danh mục'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.analytics),
                    selectedIcon: Icon(Icons.analytics),
                    label: Text('Thống kê'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    selectedIcon: Icon(Icons.settings),
                    label: Text('Cài đặt'),
                  ),
                ],
              )
            : Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    const DrawerHeader(
                      decoration: BoxDecoration(color: Color(0xFF1E88E5)),
                      child: Center(
                        child: Text(
                          'Admin',
                          style: TextStyle(color: Colors.white, fontSize: 24),
                        ),
                      ),
                    ),
                    // Build a ListTile for each tab.
                    ...[
                      'overview',
                      'products',
                      // 'upload' removed
                      'categories',
                      'analytics',
                      'settings',
                    ]
                        .asMap()
                        .entries
                        .map(
                          (e) => ListTile(
                            leading: Icon(
                              e.key == 0
                                  ? Icons.dashboard
                                  : e.key == 1
                                      ? Icons.inventory_2
                                      : e.key == 2
                                          ? Icons.category
                                          : e.key == 3
                                              ? Icons.analytics
                                              : Icons.settings,
                            ),
                            title: Text(
                              e.value == 'overview'
                                  ? 'Tổng quan'
                                  : e.value == 'products'
                                      ? 'Sản phẩm'
                                      : e.value == 'categories'
                                          ? 'Danh mục'
                                          : e.value == 'analytics'
                                              ? 'Thống kê'
                                              : 'Cài đặt',
                            ),
                            selected: viewModel.selectedTab == e.value,
                            onTap: () {
                              viewModel.selectTab(e.value);
                              Navigator.pop(context);
                            },
                          ),
                        )
                        .toList(),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Đăng xuất'),
                      onTap: () {
                        viewModel.logout();
                        Navigator.pushReplacementNamed(context, '/home');
                      },
                    ),
                  ],
                ),
              );

        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard'),
            centerTitle: true,
            actions: [
              if (!useRail)
                IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              const SizedBox(width: 8),
            ],
          ),
          // Show navigation as a rail or drawer.
          drawer: useRail ? null : (navigation as Drawer),
          // For rail layout, place the rail in the leading slot.
          body: Row(
            children: [
              if (useRail) SizedBox(width: 250, child: navigation),
              Expanded(child: _buildTabContent(viewModel.selectedTab)),
            ],
          ),
        );
      },
    );
  }

  // Helper to map a tab identifier to the rail index.
  int _getTabIndex(String tab) {
    switch (tab) {
      case 'overview':
        return 0;
      case 'products':
        return 1;
      case 'categories':
        return 2;
      case 'analytics':
        return 3;
      case 'settings':
        return 4;
      default:
        return 0;
    }
  }

  // Returns the widget for the selected tab.
  Widget _buildTabContent(String tab) {
    switch (tab) {
      case 'overview':
        return const AdminOverviewScreen();
      case 'products':
        return const AdminProductsScreen();
      case 'categories':
        return const AdminCategoriesScreen();
      case 'analytics':
        return const AdminAnalyticsScreen();
      case 'settings':
        return const AdminSettingsScreen();
      default:
        return const AdminProductsScreen();
    }
  }
}
