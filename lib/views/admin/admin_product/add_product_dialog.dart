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
  final _stockController = TextEditingController(text: '0');

  // MarkdownSplitEditor owns its own TextEditingController; the parent
  // reads the live text via this key at submit time (mirrors the
  // pattern in admin_articles.dart).
  final GlobalKey<MarkdownSplitEditorState> _descriptionKey =
      GlobalKey<MarkdownSplitEditorState>();

  final List<XFile> _selectedImages = [];
  final List<Uint8List> _selectedImagesBytes = [];
  File? _imageFile;
  Uint8List? _imageFileBytes;

  List<String> _selectedCategories = [];
  List<Option> _options = [];
  // Specs editor state. Empty list = "Thông số kỹ thuật" section is
  // hidden on the public detail screen. The SpecsEditor widget owns
  // the per-row TextEditingControllers; we only hold the canonical
  // list of strings.
  List<String> _specs = [];

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
      specs: _specs,
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                initialValue: '',
                labelText: 'Mô tả sản phẩm',
                minLines: 6,
                maxLines: 12,
              ),
              const SizedBox(height: 12),

              // Specs editor (thông số kỹ thuật) — sits with the
              // other content fields so the dialog layout reads
              // top-to-bottom: visuals → identifying fields →
              // description → specs → taxonomy → variants.
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

              // Options (variants) — shared editor with Edit so the layout
              // (IntrinsicHeight alignment, image strip) matches.
              OptionsEditorWithImages(
                options: _options,
                existingImages: const [],
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
          child: const Text('Thêm'),
        ),
      ],
    );
}
