import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/admin_viewmodel.dart';

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
                    _StatCard(
                      title: 'Tổng sản phẩm',
                      value: '${stats['totalProducts']}',
                      icon: Icons.inventory_2,
                      color: Colors.blue,
                    ),
                    _StatCard(
                      title: 'Danh mục',
                      value: '${stats['totalCategories']}',
                      icon: Icons.category,
                      color: Colors.green,
                    ),
                    _StatCard(
                      title: 'Khuyến mãi',
                      value: '${stats['productsOnSale']}',
                      icon: Icons.local_offer,
                      color: Colors.orange,
                    ),
                    _StatCard(
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

/// A small card widget used in the admin overview grid.
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
