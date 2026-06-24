import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../utils/responsive.dart';
import '../../../viewmodels/admin_viewmodel.dart';
import 'add_product_dialog.dart';
import 'product_list_tile.dart';

/// Admin products management screen.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_initialized) {
        final vm = Provider.of<AdminViewModel>(context, listen: false);
        await vm.initialize();
        setState(() => _initialized = true);
      }
    });
  }

  void _openAddDialog(BuildContext context, AdminViewModel vm) {
    showDialog(
      context: context,
      builder: (_) => AddProductDialog(viewModel: vm),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<AdminViewModel>(
      builder: (context, viewModel, _) => Column(
        children: [
          // Section header.
          Padding(
            padding: EdgeInsets.all(context.horizontalPadding),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Quản lý sản phẩm',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openAddDialog(context, viewModel),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm sản phẩm'),
                ),
              ],
            ),
          ),

          // Loading progress.
          if (viewModel.isLoading) const LinearProgressIndicator(),

          // Body.
          Expanded(
            child: _buildBody(context, viewModel),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AdminViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    if (viewModel.error != null) {
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
                onPressed: () => viewModel.initialize(),
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    if (viewModel.products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 80, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Chưa có sản phẩm nào',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bắt đầu bằng cách thêm sản phẩm đầu tiên',
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _openAddDialog(context, viewModel),
                icon: const Icon(Icons.add),
                label: const Text('Thêm sản phẩm đầu tiên'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(context.horizontalPadding),
      itemCount: viewModel.products.length,
      itemBuilder: (context, index) => ProductListTile(
        product: viewModel.products[index],
        viewModel: viewModel,
      ),
    );
  }
}
