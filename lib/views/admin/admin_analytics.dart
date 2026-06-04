import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../widgets/stat_card.dart';

/// Admin analytics screen.
class AdminAnalyticsScreen extends StatelessWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AdminViewModel>(
        builder: (context, viewModel, _) {
          final stats = viewModel.getDashboardStats();

          return Scaffold(
            appBar: AppBar(
              title: const Text('Thống kê'),
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.black,
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Dashboard stats cards
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
                        title: 'Sản phẩm khuyến mãi',
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

                  const SizedBox(height: 32),

                  /// Recent products section
                  const Text(
                    'Sản phẩm gần đây',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (viewModel.products.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      alignment: Alignment.center,
                      child: const Text(
                        'Chưa có sản phẩm',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...viewModel.products.take(5).map((product) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(product.name),
                            subtitle: Text(
                              '${product.price}đ | Stock: ${product.stock ?? 0}',
                            ),
                            trailing: product.isOnSale
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '-${product.discountPercentage}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        )),

                  const SizedBox(height: 32),

                  /// Chart placeholder
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Biểu đồ doanh số',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'Biểu đồ sẽ được cập nhật',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}
