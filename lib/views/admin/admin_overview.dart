import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/analytics_service.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../widgets/network_image.dart';
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
                  StatCard(
                    title: 'Tổng lượt truy cập',
                    value: '${viewModel.totalVisits}',
                    icon: Icons.visibility,
                    variant: CardVariant.analytics,
                  ),
                ],
              ),
              SizedBox(
                  height: context.responsive<double>(
                      mobile: 24, tablet: 28, desktop: 32)),

              // Top-viewed products table.
              _TopProductsCard(topProducts: viewModel.topProducts),
            ],
          ),
        );
      },
    );
  }
}

/// Card listing the top-N most-viewed products from the analytics
/// summary. Renders an empty-state hint when the list is empty
/// (server has no events yet) so the UI doesn't look broken.
class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.topProducts});

  final List<TopProductView> topProducts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sản phẩm xem nhiều nhất',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Top sản phẩm được khách truy cập xem nhiều nhất',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (topProducts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Chưa có dữ liệu truy cập. Hãy mở sản phẩm để ghi nhận lượt xem.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ...topProducts.asMap().entries.map(
                    (e) => _TopProductTile(rank: e.key + 1, product: e.value),
                  ),
          ],
        ),
      ),
    );
  }
}

/// One row in the top-products card. Shows rank, thumbnail, name, and
/// view count. The whole row is tappable — future use case would be
/// "jump to product".
class _TopProductTile extends StatelessWidget {
  const _TopProductTile({required this.rank, required this.product});

  final int rank;
  final TopProductView product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          '$rank',
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        '${product.viewCount} lượt xem',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: product.imageUrl.isEmpty
          ? const Icon(Icons.image_not_supported_outlined)
          : SizedBox(
              width: 48,
              height: 48,
              child: AppNetworkImage(
                url: product.imageUrl,
                fit: BoxFit.cover,
                radius: 6,
              ),
            ),
    );
  }
}
