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

/// Helper to show the edit dialog from any widget in the admin feature.
void showEditProductDialog(
  BuildContext context,
  AdminViewModel viewModel,
  Product product,
) {
  showDialog(
    context: context,
    builder: (_) => EditProductDialog(viewModel: viewModel, product: product),
  );
}

/// Dialog for editing an existing product.
class EditProductDialog extends StatefulWidget {
  const EditProductDialog({
    super.key,
    required this.viewModel,
    required this.product,
  });

  final AdminViewModel viewModel;
  final Product product;

  @override
  State<EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<EditProductDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _stockController;

  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImagesBytes = [];
  late List<String> _existingImages;
  late List<String> _selectedCategories;
  late List<Option> _options;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p.name);
    _priceController =
        TextEditingController(text: p.price.toStringAsFixed(0));
    _descriptionController = TextEditingController(text: p.description);
    _stockController =
        TextEditingController(text: p.stock?.toString() ?? '0');

    _existingImages = List<String>.from(p.images);
    _selectedCategories = p.categories.isNotEmpty
        ? List<String>.from(p.categories)
        : (p.category.isNotEmpty ? [p.category] : []);
    _options = p.options.isNotEmpty ? List<Option>.from(p.options) : [];
  }

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
      } else {
        // Mobile: bytes stay empty; File path used at upload time
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

    dynamic imageFile;
    if (_selectedImages.isNotEmpty) {
      imageFile = kIsWeb
          ? _selectedImagesBytes
          : _selectedImages.map((e) => File(e.path)).toList();
    }

    final productWithImages = updated.copyWith(
      images: _existingImages,
      imageUrl:
          _existingImages.isNotEmpty ? _existingImages.first : updated.imageUrl,
      options: _options,
    );

    await widget.viewModel.updateProduct(
      widget.product.id,
      productWithImages,
      imageFile: imageFile,
    );

    if (context.mounted) await context.read<HomeViewModel>().initialize();
    if (!context.mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cập nhật sản phẩm thành công')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Cập nhật sản phẩm'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image picker (new + existing)
            ImagePickerGrid(
              newImagesBytes: _selectedImagesBytes,
              existingImages: _existingImages,
              onPickImages: _pickImages,
              onRemoveNewImage: (i) => setState(() {
                _selectedImages.removeAt(i);
                _selectedImagesBytes.removeAt(i);
              }),
              onRemoveExistingImage: (j) =>
                  setState(() => _existingImages.removeAt(j)),
            ),
            const SizedBox(height: 12),

            // Options with image assignment from existing images
            _OptionsEditorWithImages(
              options: _options,
              existingImages: _existingImages,
              onChanged: (opts) => setState(() => _options = opts),
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
          onPressed: _submit,
          child: const Text('Cập nhật'),
        ),
      ],
    );
}

// ---------------------------------------------------------------------------
// Options editor that also lets you assign existing images to each option
// ---------------------------------------------------------------------------

class _OptionsEditorWithImages extends StatelessWidget {
  const _OptionsEditorWithImages({
    required this.options,
    required this.existingImages,
    required this.onChanged,
  });

  final List<Option> options;
  final List<String> existingImages;
  final ValueChanged<List<Option>> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: context.dialogWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Options', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < options.length; i++)
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: options[i].name,
                    decoration:
                        const InputDecoration(labelText: 'Tên option'),
                    onChanged: (v) {
                      final updated = List<Option>.from(options);
                      updated[i] = Option(
                        id: options[i].id,
                        name: v,
                        imageUrls: List<String>.from(options[i].imageUrls),
                      );
                      onChanged(updated);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ảnh', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 6),
                      _OptionImageRow(
                        option: options[i],
                        existingImages: existingImages,
                        onChanged: (updated) {
                          final list = List<Option>.from(options);
                          list[i] = updated;
                          onChanged(list);
                        },
                      ),
                    ],
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
          const SizedBox(height: 12),
        ],
      ),
    );
}

/// Horizontal scroll row showing existing images as selectable thumbnails
/// for a single option.
class _OptionImageRow extends StatelessWidget {
  const _OptionImageRow({
    required this.option,
    required this.existingImages,
    required this.onChanged,
  });

  final Option option;
  final List<String> existingImages;
  final ValueChanged<Option> onChanged;

  void _toggle(String url) {
    final imgs = List<String>.from(option.imageUrls);
    imgs.contains(url) ? imgs.remove(url) : imgs.add(url);
    onChanged(Option(id: option.id, name: option.name, imageUrls: imgs));
  }

  @override
  Widget build(BuildContext context) {
    if (existingImages.isEmpty) {
      return TextButton(
        onPressed: () =>
            onChanged(Option(id: option.id, name: option.name, imageUrls: [])),
        child: const Text('Không'),
      );
    }

    return SizedBox(
      height: 56,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(existingImages.length, (idx) {
            final url = existingImages[idx];
            final selected = option.imageUrls.contains(url);
            return Padding(
              padding: EdgeInsets.only(
                  right: idx == existingImages.length - 1 ? 0 : 8),
              child: GestureDetector(
                onTap: () => _toggle(url),
                child: Stack(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.blue : Colors.transparent,
                          width: selected ? 2 : 0,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          url,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: Colors.grey[200]),
                        ),
                      ),
                    ),
                    if (selected)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: GestureDetector(
                          onTap: () => _toggle(url),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}