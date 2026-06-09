import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../viewmodels/admin_viewmodel.dart';
import '../../viewmodels/home_viewmodel.dart';

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
              if (viewModel.products.isEmpty)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),
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
              else if (viewModel.error != null)
                Center(
                  child: Text(
                    viewModel.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: viewModel.products.length,
                  itemBuilder: (context, index) {
                    final product = viewModel.products[index];
                    return _ProductListTile(
                      product: product,
                      viewModel: viewModel,
                    );
                  },
                ),
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
  late TextEditingController _descriptionController;
  late TextEditingController _stockController;
  // ignore: unused_field
  File? _imageFile;
  // ignore: unused_field
  Uint8List? _imageFileBytes;
  final List<XFile> _selectedImages = [];
  List<Uint8List> _selectedImagesBytes = [];
  List<String> _existingImages = [];
  // ignore: unused_field
  late String? _selectedCategory;
  List<String> _selectedCategories = [];
  final TextEditingController _newCategoryController = TextEditingController();
  bool _addingCategory = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    _priceController =
        TextEditingController(text: widget.product.price.toStringAsFixed(0));
    _descriptionController =
        TextEditingController(text: widget.product.description);
    _stockController =
        TextEditingController(text: widget.product.stock?.toString() ?? '0');
    _selectedCategory = widget.product.category;
    _selectedCategories = widget.product.categories.isNotEmpty
        ? List<String>.from(widget.product.categories)
        : (widget.product.category.isNotEmpty ? [widget.product.category] : []);
    _existingImages = List<String>.from(widget.product.images);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(imageQuality: 85);
    if (images.isNotEmpty) {
      if (kIsWeb) {
        final bytesList = await Future.wait(images.map((e) => e.readAsBytes()));
        setState(() {
          _selectedImages.addAll(images);
          _selectedImagesBytes.addAll(bytesList);
          _imageFile = null;
          _imageFileBytes = _selectedImagesBytes.isNotEmpty
              ? _selectedImagesBytes.first
              : null;
        });
      } else {
        setState(() {
          _selectedImages.addAll(images);
          _selectedImagesBytes = _selectedImagesBytes; // keep existing bytes
          _imageFile = File(_selectedImages.first.path);
          _imageFileBytes = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cập nhật sản phẩm'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnails grid only (square tiles) with delete overlay and add tile
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // new selected images
                    for (var i = 0; i < _selectedImagesBytes.length; i++)
                      Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[100],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _selectedImagesBytes[i],
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.removeAt(i);
                                  _selectedImagesBytes.removeAt(i);
                                });
                              },
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    // existing images
                    for (var j = 0; j < _existingImages.length; j++)
                      Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[100],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _existingImages[j],
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _existingImages.removeAt(j);
                                });
                              },
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    // Add tile
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey),
                        ),
                        child: const Center(child: Icon(Icons.add)),
                      ),
                    ),
                  ],
                ),
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
              // Category selector (multiple) with '+' chip that toggles inline input
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...widget.viewModel.categories
                        .where((c) => c != 'All')
                        .map((c) => ChoiceChip(
                              label: Text(c),
                              selected: _selectedCategories.contains(c),
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedCategories.add(c);
                                  } else {
                                    _selectedCategories.remove(c);
                                  }
                                });
                              },
                            ))
                        ,

                    // Add-category toggle: show '+' chip or inline input with confirm/cancel
                    if (_addingCategory)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: _newCategoryController,
                                decoration: const InputDecoration(
                                  hintText: 'Danh mục mới',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                ),
                              ),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.check, color: Colors.green),
                              onPressed: () async {
                                final name = _newCategoryController.text.trim();
                                if (name.isEmpty) return;
                                try {
                                  await widget.viewModel.addCategory(name);
                                  setState(() {
                                    _selectedCategories.add(name);
                                    _newCategoryController.clear();
                                    _addingCategory = false;
                                  });
                                } catch (_) {
                                  // ignore errors for now
                                }
                              },
                              tooltip: 'Tạo',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _newCategoryController.clear();
                                  _addingCategory = false;
                                });
                              },
                              tooltip: 'Hủy',
                            ),
                          ],
                        ),
                      )
                    else
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() => _addingCategory = true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ),
                      ),
                  ],
                ),
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
              final stock = int.tryParse(_stockController.text.trim()) ?? 0;

              final updated = widget.product.copyWith(
                name: name,
                price: price,
                description: description,
                category: _selectedCategories.isNotEmpty
                    ? _selectedCategories.first
                    : widget.product.category,
                categories: _selectedCategories.isNotEmpty
                    ? _selectedCategories
                    : widget.product.categories,
                stock: stock,
              );
              // Determine imageFile: if user selected new images, upload them; otherwise keep null.
              dynamic imageFile;
              if (_selectedImages.isNotEmpty) {
                imageFile = kIsWeb
                    ? _selectedImagesBytes
                    : _selectedImages.map((e) => File(e.path)).toList();
              } else {
                imageFile = null;
              }
              // Ensure updated product includes remaining existing images.
              final productWithImages = updated.copyWith(
                images: _existingImages,
                imageUrl: _existingImages.isNotEmpty
                    ? _existingImages.first
                    : updated.imageUrl,
              );

              await widget.viewModel.updateProduct(
                widget.product.id,
                productWithImages,
                imageFile: imageFile,
              );
              // Refresh home list
              if (context.mounted) {
                await context.read<HomeViewModel>().initialize();
              }
              if (!context.mounted) return;
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
  late TextEditingController _descriptionController;
  late TextEditingController _stockController;
  File? _imageFile;
  Uint8List? _imageFileBytes;
  // ignore: unused_field
  String? _selectedCategory;
  final List<XFile> _selectedImages = [];
  List<Uint8List> _selectedImagesBytes = [];
  final List<String> _selectedCategories = [];
  final TextEditingController _newCategoryController = TextEditingController();
  bool _addingCategory = false;
  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _priceController = TextEditingController();
    _descriptionController = TextEditingController();
    _stockController = TextEditingController(text: '0');
    final cats = widget.viewModel.categories.where((c) => c != 'All').toList();
    _selectedCategory = cats.isNotEmpty ? cats.first : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage(imageQuality: 85);
    if (images.isNotEmpty) {
      if (kIsWeb) {
        final bytesList = await Future.wait(images.map((e) => e.readAsBytes()));
        setState(() {
          _selectedImages.addAll(images);
          _selectedImagesBytes.addAll(bytesList);
          _imageFile = null;
          _imageFileBytes = _selectedImagesBytes.isNotEmpty
              ? _selectedImagesBytes.first
              : null;
        });
      } else {
        setState(() {
          _selectedImages.addAll(images);
          _selectedImagesBytes = _selectedImagesBytes; // keep existing bytes
          _imageFile = File(_selectedImages.first.path);
          _imageFileBytes = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Thêm sản phẩm mới'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnails grid with delete overlay and add tile
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _selectedImagesBytes.length; i++)
                      Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[100],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _selectedImagesBytes[i],
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.removeAt(i);
                                  _selectedImagesBytes.removeAt(i);
                                });
                              },
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                          border: Border.all(color: Colors.grey),
                        ),
                        child: const Center(child: Icon(Icons.add)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên sản phẩm',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Giá (đ)',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              // Category selector - FIXED: wrap entire selector with ConstrainedBox
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...widget.viewModel.categories
                        .where((c) => c != 'All')
                        .map((c) => ChoiceChip(
                              label: Text(c),
                              selected: _selectedCategories.contains(c),
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedCategories.add(c);
                                  } else {
                                    _selectedCategories.remove(c);
                                  }
                                });
                              },
                            ))
                        ,
                    // Add-category toggle - removed nested ConstrainedBox and Wrap
                    if (_addingCategory)
                      Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 140,
                              child: TextField(
                                controller: _newCategoryController,
                                decoration: const InputDecoration(
                                  hintText: 'Danh mục mới',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                ),
                              ),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.check, color: Colors.green),
                              onPressed: () async {
                                final name = _newCategoryController.text.trim();
                                if (name.isEmpty) return;
                                try {
                                  await widget.viewModel.addCategory(name);
                                  setState(() {
                                    _selectedCategories.add(name);
                                    _newCategoryController.clear();
                                    _addingCategory = false;
                                  });
                                } catch (_) {}
                              },
                              tooltip: 'Tạo',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _newCategoryController.clear();
                                  _addingCategory = false;
                                });
                              },
                              tooltip: 'Hủy',
                            ),
                          ],
                        ),
                      )
                    else
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => setState(() => _addingCategory = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ),
                      ),
                  ],
                ),
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

            final stock = int.tryParse(_stockController.text.trim()) ?? 0;

            final newProduct = Product(
              id: '',
              name: name,
              description: description,
              price: price,
              originalPrice: null,
              imageUrl: '',
              category: _selectedCategories.isNotEmpty
                  ? _selectedCategories.first
                  : 'All',
              categories: _selectedCategories,
              rating: 0,
              reviews: 0,
              stock: stock,
              specs: [],
            );

            await widget.viewModel.addProduct(newProduct,
                imageFile: _selectedImages.isNotEmpty
                    ? (kIsWeb
                        ? _selectedImagesBytes
                        : _selectedImages.map((e) => File(e.path)).toList())
                    : (_imageFile ?? _imageFileBytes));
            if (context.mounted) {
              await context.read<HomeViewModel>().initialize();
            }
            if (!context.mounted) return;
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
