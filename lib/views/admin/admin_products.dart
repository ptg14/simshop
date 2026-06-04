import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../models/product.dart';

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
    // Delay initialization until after the first frame to ensure context is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_initialized) {
        final vm = Provider.of<AdminViewModel>(context, listen: false);
        await vm.initialize();
        setState(() => _initialized = true);
      }
    });
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
                onPressed: () => _showAddProductDialog(context, viewModel),
                icon: const Icon(Icons.add),
                label: const Text('Thêm sản phẩm'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: Stack(
            children: [
              // Main content
              viewModel.products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 80, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('Chưa có sản phẩm nào'),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showAddProductDialog(context, viewModel),
                            icon: const Icon(Icons.add),
                            label: const Text('Thêm sản phẩm đầu tiên'),
                          ),
                        ],
                      ),
                    )
                  : viewModel.error != null
                      ? Center(
                          child: Text(
                            viewModel.error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: viewModel.products.length,
                          itemBuilder: (context, index) {
                            final product = viewModel.products[index];
                            return _ProductListTile(
                                product: product, viewModel: viewModel);
                          },
                        ),
              // Loading overlay
              if (viewModel.isLoading)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x88000000),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  void _showAddProductDialog(BuildContext context, AdminViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => _AddProductDialog(viewModel: viewModel),
    );
  }
  // NOTE: The edit dialog is now provided via a top‑level helper function.
}

// Edit product dialog similar to add dialog but pre‑filled and calls update.
class _EditProductDialog extends StatefulWidget {
  const _EditProductDialog({required this.viewModel, required this.product});
  final AdminViewModel viewModel;
  final Product product;

  @override
  State<_EditProductDialog> createState() => _EditProductDialogState();
}

// Helper to show the edit dialog from anywhere in this file.
void _showEditProductDialog(
    BuildContext context, AdminViewModel viewModel, Product product) {
  showDialog(
    context: context,
    builder: (context) =>
        _EditProductDialog(viewModel: viewModel, product: product),
  );
}

class _EditProductDialogState extends State<_EditProductDialog> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _originalPriceController;
  late TextEditingController _descriptionController;
  late TextEditingController _stockController;
  File? _imageFile;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    _priceController =
        TextEditingController(text: widget.product.price.toStringAsFixed(0));
    _originalPriceController = TextEditingController(
        text: widget.product.originalPrice?.toStringAsFixed(0) ?? '');
    _descriptionController =
        TextEditingController(text: widget.product.description);
    _stockController =
        TextEditingController(text: widget.product.stock?.toString() ?? '0');
    _selectedCategory = widget.product.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _originalPriceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Use image_picker to select an image from the gallery.
    final imagePicker = ImagePicker();
    final XFile? picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cập nhật sản phẩm'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image picker button
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[200],
                        border: Border.all(color: Colors.grey),
                      ),
                      child: _imageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(_imageFile!, fit: BoxFit.cover),
                            )
                          : widget.product.imageUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    widget.product.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.image),
                                  ),
                                )
                              : const Icon(Icons.add_photo_alternate),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _imageFile != null
                          ? 'Đã chọn ảnh mới'
                          : 'Chạm để đổi ảnh',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Giá (đ)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _originalPriceController,
                decoration:
                    const InputDecoration(labelText: 'Giá gốc (đ) (tùy chọn)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              // Category dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Danh mục'),
                items: widget.viewModel.categories
                    .where((c) => c != 'All')
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Tồn kho'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Mô tả'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              final priceText = _priceController.text.trim();
              final description = _descriptionController.text.trim();
              if (name.isEmpty || priceText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Vui lòng nhập tên và giá sản phẩm')),
                );
                return;
              }
              final price = double.tryParse(priceText);
              if (price == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Giá sản phẩm không hợp lệ')),
                );
                return;
              }
              final originalPriceText = _originalPriceController.text.trim();
              final originalPrice = originalPriceText.isNotEmpty
                  ? double.tryParse(originalPriceText)
                  : null;
              final stock = int.tryParse(_stockController.text.trim()) ?? 0;

              final updated = widget.product.copyWith(
                name: name,
                price: price,
                originalPrice: originalPrice,
                description: description,
                category: _selectedCategory ?? widget.product.category,
                stock: stock,
              );
              await widget.viewModel.updateProduct(
                widget.product.id,
                updated,
                imageFile: _imageFile,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cập nhật sản phẩm thành công')),
              );
            },
            child: const Text('Cập nhật'),
          ),
        ],
      );
}

class _ProductListTile extends StatelessWidget {
  const _ProductListTile({
    required this.product,
    required this.viewModel,
  });
  final Product product;
  final AdminViewModel viewModel;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[200],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              // Show a loading indicator while the product image is being fetched.
              child: Image.network(
                product.imageUrl,
                fit: BoxFit.cover,
                // Placeholder while loading.
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey[200],
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.image_not_supported),
              ),
            ),
          ),
          title: Text(product.name),
          subtitle: Text(
            '${product.price}đ | Stock: ${product.stock ?? 0}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () =>
                      _showEditProductDialog(context, viewModel, product),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _showDeleteConfirm(context),
                ),
              ],
            ),
          ),
        ),
      );

  void _showDeleteConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa sản phẩm'),
        content: Text('Bạn có chắc muốn xóa "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await viewModel.deleteProduct(product.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  // Show feedback after deletion.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Xóa sản phẩm thành công')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi khi xóa sản phẩm: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({required this.viewModel});
  final AdminViewModel viewModel;

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _originalPriceController;
  late TextEditingController _descriptionController;
  late TextEditingController _stockController;
  File? _imageFile;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _priceController = TextEditingController();
    _originalPriceController = TextEditingController();
    _descriptionController = TextEditingController();
    _stockController = TextEditingController(text: '0');
    // Default to first non-'All' category if available.
    final cats = widget.viewModel.categories.where((c) => c != 'All').toList();
    _selectedCategory = cats.isNotEmpty ? cats.first : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _originalPriceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Use image_picker to select an image from the gallery.
    final imagePicker = ImagePicker();
    final XFile? picked = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Thêm sản phẩm mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image picker
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                    border: Border.all(color: Colors.grey),
                  ),
                  child: _imageFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_imageFile!, fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate,
                                size: 40, color: Colors.grey[600]),
                            const SizedBox(height: 4),
                            Text('Chọn ảnh sản phẩm',
                                style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên sản phẩm',
                  hintText: 'VD: PC Gaming',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Giá (đ)',
                  hintText: 'VD: 25000000',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _originalPriceController,
                decoration: const InputDecoration(
                  labelText: 'Giá gốc (đ) (tùy chọn)',
                  hintText: 'VD: 30000000',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              // Category dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Danh mục'),
                items: widget.viewModel.categories
                    .where((c) => c != 'All')
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCategory = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Tồn kho'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  hintText: 'Mô tả sản phẩm',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              final priceText = _priceController.text.trim();
              final description = _descriptionController.text.trim();

              if (name.isEmpty || priceText.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Vui lòng nhập tên và giá sản phẩm')),
                );
                return;
              }

              final price = double.tryParse(priceText);
              if (price == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Giá sản phẩm không hợp lệ')),
                );
                return;
              }

              final originalPriceText = _originalPriceController.text.trim();
              final originalPrice = originalPriceText.isNotEmpty
                  ? double.tryParse(originalPriceText)
                  : null;
              final stock = int.tryParse(_stockController.text.trim()) ?? 0;

              // Create product with empty id – backend will generate one.
              final newProduct = Product(
                id: '', // backend will assign real ID
                name: name,
                description: description,
                price: price,
                originalPrice: originalPrice,
                imageUrl: '', // will be set after upload
                category: _selectedCategory ?? 'All',
                rating: 0,
                reviews: 0,
                stock: stock,
                specs: [],
              );

              await widget.viewModel
                  .addProduct(newProduct, imageFile: _imageFile);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Thêm sản phẩm thành công')),
              );
            },
            child: const Text('Thêm'),
          ),
        ],
      );
}
