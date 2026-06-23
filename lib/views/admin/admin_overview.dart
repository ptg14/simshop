import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive.dart';
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
            padding: EdgeInsets.all(context.horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thống kê nhanh',
                  style: TextStyle(
                    fontSize: context.responsive<double>(
                        mobile: 18, tablet: 19, desktop: 20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(
                    height: context.responsive<double>(
                        mobile: 12, tablet: 14, desktop: 16)),
                GridView.count(
                  crossAxisCount: context.adminStatColumns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: context.responsive<double>(
                      mobile: 12, tablet: 14, desktop: 16),
                  mainAxisSpacing: context.responsive<double>(
                      mobile: 12, tablet: 14, desktop: 16),
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
