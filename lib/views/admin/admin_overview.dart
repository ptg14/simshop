import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../widgets/stat_card.dart';

/// Admin overview/dashboard screen.
class AdminOverviewScreen extends StatelessWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<AdminViewModel>(
      builder: (context, viewModel, _) {
        final stats = viewModel.getDashboardStats();
        return SingleChildScrollView(
          padding: EdgeInsets.all(context.horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header.
              Text(
                'Xin chào, Admin!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tổng quan nhanh về cửa hàng của bạn',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              SizedBox(
                  height: context.responsive<double>(
                      mobile: 16, tablet: 18, desktop: 20)),

              // Stats grid.
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
                    variant: CardVariant.primary,
                  ),
                  StatCard(
                    title: 'Danh mục',
                    value: '${stats['totalCategories']}',
                    icon: Icons.category,
                    variant: CardVariant.secondary,
                  ),
                  StatCard(
                    title: 'Khuyến mãi',
                    value: '${stats['productsOnSale']}',
                    icon: Icons.local_offer,
                    variant: CardVariant.tertiary,
                  ),
                  StatCard(
                    title: 'Sắp hết hàng',
                    value: '${stats['lowStockProducts']}',
                    icon: Icons.warning,
                    variant: CardVariant.error,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
