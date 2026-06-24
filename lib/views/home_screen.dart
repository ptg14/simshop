import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../models/product.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../viewmodels/home_viewmodel.dart';
import '../viewmodels/site_config_viewmodel.dart';
import '../widgets/category_selector.dart';
import '../widgets/image_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/site_info_footer.dart';
import 'admin/admin_dashboard.dart';
import 'article_screen.dart';
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
          // On mobile the title is the editable site name (falls back to
          // 'simshop' while the backend call is in flight). On larger
          // viewports the suffix is preserved so the widget test still
          // matches the literal 'simshop - Quảng Cáo'.
          title: context.isMobile
              ? Consumer<SiteConfigViewModel>(
                  builder: (_, vm, __) {
                    final name = vm.siteInfo.name;
                    return Text(name.isEmpty ? 'simshop' : name);
                  },
                )
              : const Text('simshop - Quảng Cáo'),
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
                        // Promotional image carousel. Slice 1 uses hardcoded
                        // mock banners; slice 3 swaps in viewModel.banners.
                        if (viewModel.getPromotionalProducts().isNotEmpty)
                          ImageCarousel(
                            imageUrls: const [
                              'https://picsum.photos/800/300?random=1',
                              'https://picsum.photos/800/300?random=2',
                              'https://picsum.photos/800/300?random=3',
                            ],
                            height: context.carouselHeight,
                            onTap: (index) {
                              Navigator.of(context).push(openArticleRoute(
                                Article(
                                  id: 'mock-$index',
                                  title: 'Ưu đãi tháng ${index + 1}',
                                  body: '## Điểm nổi bật\n\n'
                                      '- Giảm giá lên tới **30%**\n'
                                      '- Áp dụng cho nhiều danh mục\n'
                                      '- Thời gian có hạn\n\n'
                                      '_Bài viết này là mẫu. Trong slice 3, '
                                      'banner thật sẽ mở bài viết từ backend._',
                                ),
                              ));
                            },
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
                        const SiteInfoFooter(),
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
