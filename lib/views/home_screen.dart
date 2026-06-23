import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../utils/responsive.dart';
import '../viewmodels/home_viewmodel.dart';
import '../widgets/category_selector.dart';
import '../widgets/image_carousel.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';

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
    Navigator.pushNamed(context, '/product-detail', arguments: product);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.isMobile ? 'simshop' : 'simshop - Quảng Cáo'),
          centerTitle: context.isMobile,
          actions: [
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Quản trị',
              onPressed: () => Navigator.pushNamed(context, '/admin'),
            ),
          ],
        ),
        body: Consumer<HomeViewModel>(
          builder: (context, viewModel, _) {
            if (viewModel.isLoading && viewModel.products.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (viewModel.error != null && viewModel.products.isEmpty) {
              return Center(child: Text(viewModel.error!));
            }
            return RefreshIndicator(
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
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: context.horizontalPadding,
                            vertical: 8,
                          ),
                          child: ProductSearchBar(
                            onSearch: viewModel.searchProducts,
                            onClear: viewModel.resetSearch,
                          ),
                        ),
                        // Promotional image carousel
                        if (viewModel.getPromotionalProducts().isNotEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: context.horizontalPadding,
                            ),
                            child: ImageCarousel(
                              imageUrls: const [
                                'https://picsum.photos/800/300?random=1',
                                'https://picsum.photos/800/300?random=2',
                                'https://picsum.photos/800/300?random=3',
                              ],
                              height: context.carouselHeight,
                            ),
                          ),
                        // Category selector
                        CategorySelector(
                          categories: viewModel.categories,
                          selectedCategory: viewModel.selectedCategory,
                          onCategorySelected: viewModel.selectCategory,
                        ),
                        // Product grid or empty state
                        if (viewModel.products.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 64),
                              child: Column(
                                children: [
                                  const Icon(Icons.inventory_2_outlined,
                                      size: 80, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Không tìm thấy sản phẩm nào',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    onPressed: () => viewModel.resetSearch(),
                                    child: const Text('Xóa bộ lọc'),
                                  ),
                                ],
                              ),
                            ),
                          )
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
