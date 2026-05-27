import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/home_viewmodel.dart';
import '../widgets/product_card.dart';
import '../widgets/search_bar.dart';
import '../widgets/category_selector.dart';
import '../widgets/image_carousel.dart';
import '../models/product.dart';

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
    // Initialize the home view model after the first frame.
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
          title: const Text('TTSHOP - Quảng Cáo'),
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
            if (viewModel.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (viewModel.error != null) {
              return Center(child: Text(viewModel.error!));
            }
            return RefreshIndicator(
              onRefresh: viewModel.initialize,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search bar
                    ProductSearchBar(
                      onSearch: viewModel.searchProducts,
                      onClear: viewModel.resetSearch,
                    ),
                    // Promotional image carousel (replaces special promo banner)
                    if (viewModel.getPromotionalProducts().isNotEmpty)
                      ImageCarousel(
                        // Example placeholder images; replace with real URLs as needed
                        imageUrls: [
                          'https://picsum.photos/800/300?random=1',
                          'https://picsum.photos/800/300?random=2',
                          'https://picsum.photos/800/300?random=3',
                        ],
                        height: 200,
                      ),
                    // Category selector
                    CategorySelector(
                      categories: viewModel.categories,
                      selectedCategory: viewModel.selectedCategory,
                      onCategorySelected: viewModel.selectCategory,
                    ),
                    // Product grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.6,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: viewModel.products.length,
                      itemBuilder: (context, index) {
                        final product = viewModel.products[index];
                        return ProductCard(
                          product: product,
                          onTap: () => _navigateToProductDetail(product),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

// Removed cart functionality as this is an advertising site.
