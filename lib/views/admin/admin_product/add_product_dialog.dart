import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  /// Ordered list of newly-picked images. There are no existing
  /// images on the create path, so every entry is a
  /// [GalleryNewImage]. Kept as a list (rather than separate
  /// `XFile` + `Uint8List` arrays) so the same drag-reorder UX as
  /// the Edit dialog works without branching on the data shape.
  /// `final` because every mutation goes through setState with a
  /// freshly-allocated list, keeping the widget consistent with
  /// the standard "immutable state" rule.
  final List<GalleryItem> _gallery = <GalleryItem>[];

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
      final added = [
        for (var i = 0; i < images.length; i++)
          GalleryNewImage(xfile: images[i], bytes: bytes[i]),
      ];
      // Allocate a fresh list so the `final _gallery` field stays
      // immutable across rebuilds.
      _gallery
        ..clear()
        ..addAll(added);
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // Standard `List.move` semantics matching the
      // `onReorderItem` contract: `newIndex` is already the
      // post-removal slot.
      final moved = _gallery.removeAt(oldIndex);
      _gallery.insert(newIndex, moved);
    });
  }

  void _onRemoveAt(int index) {
    setState(() {
      _gallery.removeAt(index);
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

    // Pre-upload every new image in the order the admin arranged
    // them, then build an [imageOrder] that mirrors the gallery
    // slots. Index 0 becomes the cover image.
    final imageOrder = <String>[];
    for (final item in _gallery) {
      if (item is! GalleryNewImage) continue;
      final url = await widget.viewModel.uploadImage(
        kIsWeb ? item.bytes : File(item.xfile.path),
        productName: name,
      );
      if (url == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi tải ảnh lên máy chủ')),
        );
        return;
      }
      imageOrder.add(url);
    }

    final newProduct = Product(
      id: '',
      name: name,
      description: description,
      price: price,
      originalPrice: null,
      imageUrl: imageOrder.isNotEmpty ? imageOrder.first : '',
      category:
          _selectedCategories.isNotEmpty ? _selectedCategories.first : 'All',
      categories: _selectedCategories,
      rating: 0,
      reviews: 0,
      stock: stock,
      specs: _specs,
      options: _options,
      images: imageOrder,
    );

    // `imageOrder` is already authoritative on the create path —
    // every image was just uploaded by us. Pass `null` for
    // [imageFile] so the VM doesn't try to upload a second time.
    await widget.viewModel.addProduct(
      newProduct,
      imageFile: null,
      imageOrder: imageOrder,
    );

    if (!mounted) return;
    await context.read<HomeViewModel>().initialize();
    if (!mounted) return;

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thêm sản phẩm thành công')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm sản phẩm mới'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dialogWidth),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image picker — single ordered list so the admin can
              // drag-reorder before submit, and the first slot
              // becomes the cover.
              ImagePickerGrid(
                items: _gallery,
                onPickImages: _pickImages,
                onRemoveAt: _onRemoveAt,
                onReorder: _onReorder,
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

              // Options (variants) — shared editor with Edit so the
              // layout (IntrinsicHeight alignment, image strip)
              // matches. The "available" pool is the freshly-picked
              // bytes only — there are no existing URLs on the
              // create path.
              OptionsEditorWithImages(
                options: _options,
                existingImages: const [],
                newImageBytes: _gallery
                    .whereType<GalleryNewImage>()
                    .map((e) => e.bytes)
                    .toList(),
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
}