import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../widgets/stat_card.dart';

/// Admin overview/dashboard screen.
class AdminOverviewScreen extends StatelessWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AdminViewModel>(
        builder: (context, viewModel, _) {
          final stats = viewModel.getDashboardStats();
          // This screen is displayed inside the AdminDashboard's Scaffold, so we
          // provide only the scrollable content.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Thống kê nhanh',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    StatCard(
                      title: 'Tổng sản phẩm',
                      value: '${stats['totalProducts']}',
                      icon: Icons.inventory_2,
                      color: Colors.blue,
                    ),
                    StatCard(
                      title: 'Danh mục',
                      value: '${stats['totalCategories']}',
                      icon: Icons.category,
                      color: Colors.green,
                    ),
                    StatCard(
                      title: 'Khuyến mãi',
                      value: '${stats['productsOnSale']}',
                      icon: Icons.local_offer,
                      color: Colors.orange,
                    ),
                    StatCard(
                      title: 'Sắp hết hàng',
                      value: '${stats['lowStockProducts']}',
                      icon: Icons.warning,
                      color: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
}
