import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../models/product.dart';
import '../../../utils/responsive.dart';
import '../../../viewmodels/admin_viewmodel.dart';
import '../../../viewmodels/home_viewmodel.dart';
import '../../../widgets/markdown_split_editor.dart';
import 'widgets/image_picker_grid.dart';
import 'widgets/options_editor_with_images.dart';
import 'widgets/product_category_picker.dart';
import 'widgets/specs_editor.dart';

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
  late final TextEditingController _stockController;

  // MarkdownSplitEditor owns its own TextEditingController; the parent
  // reads the live text via this key at submit time (mirrors the
  // pattern in admin_articles.dart).
  final GlobalKey<MarkdownSplitEditorState> _descriptionKey =
      GlobalKey<MarkdownSplitEditorState>();

  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImagesBytes = [];
  late List<String> _existingImages;
  late List<String> _selectedCategories;
  late List<Option> _options;
  // Specs editor state. Seeded from product.specs in initState so a
  // re-open preserves whatever the admin previously typed (the
  // bug the old copyWith-skipping path produced: edit, save, all
  // specs silently wiped).
  late List<String> _specs;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p.name);
    _priceController =
        TextEditingController(text: p.price.toStringAsFixed(0));
    _stockController =
        TextEditingController(text: p.stock?.toString() ?? '0');

    _existingImages = List<String>.from(p.images);
    _selectedCategories = p.categories.isNotEmpty
        ? List<String>.from(p.categories)
        : (p.category.isNotEmpty ? [p.category] : []);
    _options = p.options.isNotEmpty ? List<Option>.from(p.options) : [];
    _specs = List<String>.from(p.specs);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
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
    final description = _descriptionKey.currentState?.text.trim() ?? '';

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
      // Primary category string (the legacy single-value field).
      // Fall back to `''` when the admin removed every category —
      // keeping the previous value would re-attach the dropped
      // category on save.
      category:
          _selectedCategories.isNotEmpty ? _selectedCategories.first : '',
      // Plural `categories` list. When the admin has cleared
      // every selection we send `const []` so the backend overwrites
      // the old list (previously this fell back to
      // `widget.product.categories`, which kept the dropped
      // categories on the product).
      categories: List<String>.from(_selectedCategories),
      stock: stock,
      specs: _specs,
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
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dialogWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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

              // Stock
              TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Tồn kho'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),

              // Description
              MarkdownSplitEditor(
                key: _descriptionKey,
                initialValue: widget.product.description,
                labelText: 'Mô tả sản phẩm',
                minLines: 6,
                maxLines: 12,
              ),
              const SizedBox(height: 12),

              // Specs editor — seeded from product.specs in
              // initState, emitted back via copyWith on submit. Same
              // slot as the Add dialog so the two layouts line up.
              SpecsEditor(
                specs: _specs,
                onChanged: (v) => setState(() => _specs = v),
              ),

              // Categories
              ProductCategoryPicker(
                viewModel: widget.viewModel,
                selectedCategories: _selectedCategories,
                onChanged: (cats) => setState(() => _selectedCategories = cats),
              ),
              const SizedBox(height: 12),

              // Options with image assignment from existing + new
              // (shared editor so Add and Edit share one layout).
              OptionsEditorWithImages(
                options: _options,
                existingImages: _existingImages,
                newImageBytes: _selectedImagesBytes,
                onChanged: (opts) => setState(() => _options = opts),
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
        FilledButton(
          onPressed: _submit,
          child: const Text('Cập nhật'),
        ),
      ],
    );
}
