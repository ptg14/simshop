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
  Widget build(BuildContext context) => Consumer<AdminViewModel>(
      builder: (context, viewModel, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Quản lý sản phẩm'),
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          actions: [
            ElevatedButton.icon(
              onPressed: () => _openAddDialog(context, viewModel),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: Stack(
          children: [
            _buildBody(context, viewModel),
            if (viewModel.isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x88000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );

  Widget _buildBody(BuildContext context, AdminViewModel viewModel) {
    if (viewModel.error != null) {
      return Center(
        child: Text(
          viewModel.error!,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (viewModel.products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Chưa có sản phẩm nào'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _openAddDialog(context, viewModel),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm đầu tiên'),
            ),
          ],
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