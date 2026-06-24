import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../viewmodels/home_viewmodel.dart';
import '../widgets/category_selector.dart';
import '../widgets/image_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import 'admin/admin_dashboard.dart';
import 'product_detail_screen.dart';

/// Home screen displaying products and promotions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().initialize();
    });
  }

  void _navigateToProductDetail(Product product) {
    Navigator.of(context).push(
      fadeSlideRoute(ProductDetailScreen(product: product)),
    );
  }

  void _navigateToAdmin() {
    Navigator.of(context).push(fadeSlideRoute(const AdminDashboard()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
        appBar: AppBar(
          title: Text(context.isMobile ? 'simshop' : 'simshop - Quảng Cáo'),
          centerTitle: context.isMobile,
          actions: [
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Quản trị',
              onPressed: _navigateToAdmin,
            ),
          ],
        ),
        body: Consumer<HomeViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading && viewModel.products.isEmpty) {
              return Center(
                child: CircularProgressIndicator(color: scheme.primary),
              );
            }
            if (viewModel.error != null && viewModel.products.isEmpty) {
              return _buildError(context, viewModel);
            }
            return RefreshIndicator(
              color: scheme.primary,
              onRefresh: viewModel.initialize,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: context.maxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar
                        ProductSearchBar(
                          onSearch: viewModel.searchProducts,
                          onClear: viewModel.resetSearch,
                        ),
                        // Promotional image carousel
                        if (viewModel.getPromotionalProducts().isNotEmpty)
                          ImageCarousel(
                            imageUrls: const [
                              'https://picsum.photos/800/300?random=1',
                              'https://picsum.photos/800/300?random=2',
                              'https://picsum.photos/800/300?random=3',
                            ],
                            height: context.carouselHeight,
                          ),
                        // Category selector (Large + sub rows).
                        CategorySelector(
                          largeCategories: viewModel.largeCategories,
                          selectedLarge: viewModel.selectedLarge,
                          onLargeSelected: viewModel.selectLarge,
                          subCategories: viewModel.visibleSubCategories,
                          selectedSub: viewModel.selectedCategory,
                          onSubSelected: viewModel.selectCategory,
                        ),
                        // Product grid or empty state
                        if (viewModel.products.isEmpty)
                          _buildEmpty(context, viewModel)
                        else
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.horizontalPadding,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final crossAxisCount = context.gridColumns;
                                final spacing = context.gridSpacing;
                                final aspect = context.responsive<double>(
                                  mobile: 0.58,
                                  tablet: 0.62,
                                  desktop: 0.65,
                                );

                                return GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    top: context.gridSpacing,
                                    bottom: 16,
                                  ),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    childAspectRatio: aspect,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                  ),
                                  itemCount: viewModel.products.length,
                                  itemBuilder: (context, index) {
                                    final product = viewModel.products[index];
                                    return ProductCard(
                                      product: product,
                                      onTap: () =>
                                          _navigateToProductDetail(product),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
  }

  Widget _buildEmpty(BuildContext context, HomeViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 80, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Không tìm thấy sản phẩm nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy thử bỏ bộ lọc hoặc tìm với từ khoá khác',
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => viewModel.resetSearch(),
              icon: const Icon(Icons.refresh),
              label: const Text('Xóa bộ lọc'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, HomeViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'Không thể tải sản phẩm',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              viewModel.error!,
              style: TextStyle(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: viewModel.initialize,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}
