import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../models/product.dart';
import '../../../utils/responsive.dart';
import '../../../viewmodels/admin_viewmodel.dart';
import '../../../viewmodels/home_viewmodel.dart';
import 'widgets/category_selector.dart';
import 'widgets/image_picker_grid.dart';

/// Dialog for adding a new product.
class AddProductDialog extends StatefulWidget {
  const AddProductDialog({super.key, required this.viewModel});
  final AdminViewModel viewModel;

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImagesBytes = [];
  File? _imageFile;
  Uint8List? _imageFileBytes;

  List<String> _selectedCategories = [];
  List<Option> _options = [];

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final (images, bytes) = await pickMultipleImages();
    if (images.isEmpty) return;
    setState(() {
      _selectedImages.addAll(images);
      if (kIsWeb) {
        _selectedImagesBytes.addAll(bytes);
        _imageFile = null;
        _imageFileBytes =
            _selectedImagesBytes.isNotEmpty ? _selectedImagesBytes.first : null;
      } else {
        _imageFile = File(_selectedImages.first.path);
        _imageFileBytes = null;
      }
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final priceText = _priceController.text.trim();
    final description = _descriptionController.text.trim();

    if (name.isEmpty || priceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên và giá sản phẩm')),
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
      category:
          _selectedCategories.isNotEmpty ? _selectedCategories.first : 'All',
      categories: _selectedCategories,
      rating: 0,
      reviews: 0,
      stock: stock,
      specs: [],
      options: _options,
    );

    await widget.viewModel.addProduct(
      newProduct,
      imageFile: _selectedImages.isNotEmpty
          ? (kIsWeb
              ? _selectedImagesBytes
              : _selectedImages.map((e) => File(e.path)).toList())
          : (_imageFile ?? _imageFileBytes),
    );

    if (context.mounted) await context.read<HomeViewModel>().initialize();
    if (!context.mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thêm sản phẩm thành công')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Thêm sản phẩm mới'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dialogWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image picker
              ImagePickerGrid(
                newImagesBytes: _selectedImagesBytes,
                onPickImages: _pickImages,
                onRemoveNewImage: (i) => setState(() {
                  _selectedImages.removeAt(i);
                  _selectedImagesBytes.removeAt(i);
                }),
              ),
              const SizedBox(height: 12),

              // Name
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
              ),
              const SizedBox(height: 12),

              // Price
              TextField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Giá (đ)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              // Categories
              CategorySelector(
                viewModel: widget.viewModel,
                selectedCategories: _selectedCategories,
                onChanged: (cats) => setState(() => _selectedCategories = cats),
              ),
              const SizedBox(height: 12),

              // Options (variants)
              _OptionsEditor(
                options: _options,
                onChanged: (opts) => setState(() => _options = opts),
              ),
              const SizedBox(height: 12),

              // Stock
              TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Tồn kho'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              // Description
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
          onPressed: _submit,
          child: const Text('Thêm'),
        ),
      ],
    );
}

// ---------------------------------------------------------------------------
// Simple options (variants) editor — shared look between Add and Edit dialogs
// ---------------------------------------------------------------------------

class _OptionsEditor extends StatelessWidget {
  const _OptionsEditor({required this.options, required this.onChanged});

  final List<Option> options;
  final ValueChanged<List<Option>> onChanged;

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Options', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (var i = 0; i < options.length; i++)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: options[i].name,
                  decoration: const InputDecoration(labelText: 'Tên option'),
                  onChanged: (v) {
                    final updated = List<Option>.from(options);
                    updated[i] =
                        Option(id: options[i].id, name: v, imageUrls: []);
                    onChanged(updated);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  final updated = List<Option>.from(options)..removeAt(i);
                  onChanged(updated);
                },
              ),
            ],
          ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () {
            final updated = List<Option>.from(options)
              ..add(Option(id: '', name: 'Option', imageUrls: []));
            onChanged(updated);
          },
          icon: const Icon(Icons.add),
          label: const Text('Thêm option'),
        ),
      ],
    );
}