import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/home_viewmodel.dart';
import '../viewmodels/cart_viewmodel.dart';
import '../widgets/search_bar.dart' show ProductSearchBar;
import '../widgets/product_card.dart';
import '../widgets/promo_banner.dart';
import '../widgets/category_selector.dart';

/// Home screen displaying products and promotions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TTSHOP',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Color(0xFF1E88E5),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black),
            onPressed: () => Navigator.pushNamed(context, '/cart'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Consumer<CartViewModel>(
                builder: (context, cartViewModel, _) {
                  return cartViewModel.itemCount > 0
                      ? Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${cartViewModel.itemCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
        ],
      ),
      body: Consumer<HomeViewModel>(
        builder: (context, viewModel, _) {
          return RefreshIndicator(
            onRefresh: () => viewModel.loadProducts(),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  /// Search bar
                  ProductSearchBar(
                    onSearch: (query) {
                      if (query.isEmpty) {
                        viewModel.resetSearch();
                      } else {
                        viewModel.searchProducts(query);
                      }
                    },
                    onClear: viewModel.resetSearch,
                    hintText: 'Tìm kiếm sản phẩm...',
                  ),

                  /// Top banner
                  PromoBanner(
                    title: 'Đổi PC\ntrong 10 ngày',
                    subtitle:
                        'Không ứng hoàn tiền 100% - Hoàc đổi sáng cấu hình khác',
                    actionText: 'XEM THÊM',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Xem chương trình khuyến mãi')),
                      );
                    },
                    backgroundColor: const Color(0xFF1E88E5),
                  ),

                  /// Section: Deal hot
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🔥 DEAL HỌC MỖI NGÀY',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        TextButton(
                          onPressed: () {},
                          child: const Text('Xem tất cả →'),
                        ),
                      ],
                    ),
                  ),

                  /// Featured products (on sale)
                  SizedBox(
                    height: 320,
                    child: viewModel.isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: viewModel.getFeaturedProducts().length,
                            itemBuilder: (context, index) {
                              final product = viewModel.getFeaturedProducts()[index];
                              return Container(
                                width: 160,
                                margin: const EdgeInsets.only(right: 12),
                                child: ProductCard(
                                  product: product,
                                  onTap: () {
                                    Navigator.pushNamed(context, '/product-detail',
                                        arguments: product);
                                  },
                                  onAddToCart: () {
                                    context.read<CartViewModel>().addToCart(product);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Đã thêm ${product.name} vào giỏ'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),

                  /// Section: Promotional banner
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.withOpacity(0.8),
                            Colors.blue.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'GIỚI THIỆU BẠN MỚI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'NHẬN QUÀ CÁ ĐÓI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                  ),
                                  child: const Text(
                                    'CHIA SẺ',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.card_giftcard,
                              size: 60, color: Colors.white),
                        ],
                      ),
                    ),
                  ),

                  /// Category selector
                  CategorySelector(
                    categories: viewModel.categories,
                    selectedCategory: viewModel.selectedCategory,
                    onCategorySelected: (category) {
                      viewModel.selectCategory(category);
                    },
                  ),

                  /// Products grid
                  viewModel.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        )
                      : viewModel.products.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                children: [
                                  const Icon(Icons.shopping_bag_outlined,
                                      size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Không tìm thấy sản phẩm',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.55,
                              ),
                              itemCount: viewModel.products.length,
                              itemBuilder: (context, index) {
                                final product = viewModel.products[index];
                                return ProductCard(
                                  product: product,
                                  onTap: () {
                                    Navigator.pushNamed(context, '/product-detail',
                                        arguments: product);
                                  },
                                  onAddToCart: () {
                                    context.read<CartViewModel>().addToCart(product);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('Đã thêm ${product.name} vào giỏ'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
