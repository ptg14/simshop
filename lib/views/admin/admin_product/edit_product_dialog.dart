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

  /// Single ordered list of every image in the gallery — already-uploaded
  /// URLs first, then freshly-picked bytes the admin added this session.
  /// Order is preserved through any drag-reorder; the parent builds
  /// `images` (for the backend) and `imageFile` (for upload) from this
  /// list at submit time.
  late List<GalleryItem> _gallery;

  /// URLs the admin removed from the existing gallery during this
  /// edit session. Forwarded to the backend on submit, which
  /// best-effort deletes the underlying files from /uploads/ after
  /// the DB UPDATE commits (see RealProductService.updateProduct).
  /// We snapshot the URL at removal time so the dialog can drop the
  /// entry from [_gallery] and still hand the backend the original
  /// (post-rename, post-CDN) URL.
  final List<String> _removedImageUrls = [];

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

    // Seed the gallery with every existing image, in order. The
    // product's `images` list is the source of truth on entry; if
    // the server only filled in `image_url` (legacy / no gallery),
    // synthesise a one-item list so the admin can still reorder.
    _gallery = p.images.isNotEmpty
        ? p.images.map(GalleryExistingImage.new).toList()
        : (p.imageUrl.isNotEmpty
            ? [GalleryExistingImage(p.imageUrl)]
            : <GalleryItem>[]);

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
      for (var i = 0; i < images.length; i++) {
        _gallery.add(GalleryNewImage(xfile: images[i], bytes: bytes[i]));
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      // Standard `List.move` semantics matching the
      // `onReorderItem` contract: the `newIndex` we receive is the
      // post-removal slot, so a direct insert works.
      final moved = _gallery.removeAt(oldIndex);
      _gallery.insert(newIndex, moved);
    });
  }

  void _onRemoveAt(int index) {
    setState(() {
      final removed = _gallery.removeAt(index);
      // Track removed URL for backend cleanup. Only
      // [GalleryExistingImage] carries a server-side URL —
      // [GalleryNewImage] hasn't been uploaded yet, so there is
      // nothing for the backend to delete.
      if (removed is GalleryExistingImage) {
        _removedImageUrls.add(removed.url);
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

    // Pre-upload any new bytes so we can build a single ordered
    // `imageOrder` that the VM will write to `images` verbatim.
    // Without this the VM appends new URLs to the end of
    // `existingUrls`, losing the order the admin set on the dialog.
    final imageOrder = List<String>.filled(_gallery.length, '');
    for (var i = 0; i < _gallery.length; i++) {
      final item = _gallery[i];
      if (item is GalleryExistingImage) {
        imageOrder[i] = item.url;
      }
    }
    for (final newImg in _gallery.whereType<GalleryNewImage>()) {
      final url = await widget.viewModel.uploadImage(
        kIsWeb ? newImg.bytes : File(newImg.xfile.path),
        productName: widget.product.name.isNotEmpty
            ? widget.product.name
            : name,
        productId: widget.product.id,
      );
      if (url == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi tải ảnh lên máy chủ')),
        );
        return;
      }
      // Fill the slot of the matching new image. The first match
      // wins because each new image is unique by xfile+bytes.
      final slot = _gallery.indexOf(newImg);
      if (slot >= 0 && slot < imageOrder.length) {
        imageOrder[slot] = url;
      }
    }

    // Safety net: any slot the upload loop missed (shouldn't
    // happen, but a null URL could land us here) gets dropped
    // instead of producing a `null` in the URL list.
    final cleanOrder = imageOrder.where((u) => u.isNotEmpty).toList();

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

    // The admin can drop an image from the gallery (which adds
    // the URL to [_removedImageUrls] for backend cleanup) without
    // explicitly un-toggling that URL inside every option that
    // references it — the option's row loses the thumb, so the toggle
    // UI disappears, but the URL is still inside `option.imageUrls`.
    // If we forwarded [_options] as-is, the backend would still write
    // those URLs into `product_options.image_urls` while the file is
    // deleted from /uploads/, leaving the option's gallery showing a
    // broken image. Strip every removed URL from each option's
    // `imageUrls` before submit so the option tracks the cleaned-up
    // gallery.
    final prunedOptions = _removedImageUrls.isEmpty
        ? _options
        : _options
            .map((o) => Option(
                  id: o.id,
                  name: o.name,
                  imageUrls: o.imageUrls
                      .where((u) => !_removedImageUrls.contains(u))
                      .toList(),
                ))
            .toList();

    // Cover image: the first slot of [imageOrder] (which we just
    // built in gallery order). When the admin has removed every
    // image we deliberately send an empty string so the backend
    // clears `image_url` — falling back to `updated.imageUrl`
    // would leave a stale URL on a product whose gallery is
    // empty, and the backend has already deleted the file from
    // /uploads/ (per [removedImageUrls]), so the leftover
    // `image_url` would point at a 404.
    final coverUrl = cleanOrder.isNotEmpty ? cleanOrder.first : '';

    final productWithImages = updated.copyWith(
      images: cleanOrder,
      imageUrl: coverUrl,
      options: prunedOptions,
    );

    // `imageFile` is plumbed through for any caller that still
    // needs the raw bytes (e.g. the new-product flow). For an
    // update we pre-uploaded everything above, so we pass `null`
    // to skip the VM's append logic and use `imageOrder` instead.
    await widget.viewModel.updateProduct(
      widget.product.id,
      productWithImages,
      imageFile: null,
      removedImageUrls: _removedImageUrls,
      imageOrder: cleanOrder,
    );

    if (!mounted) return;
    await context.read<HomeViewModel>().initialize();
    if (!mounted) return;

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
              // Image picker (new + existing, single ordered list)
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
                initialValue: widget.product.description,
                labelText: 'Mô tả sản phẩm',
                minLines: 6,
                maxLines: 12,
              ),
              const SizedBox(height: 12),

              // Specs editor — seeded from product.specs in
              // initState, emitted back via copyWith on submit.
              SpecsEditor(
                specs: _specs,
                onChanged: (v) => setState(() => _specs = v),
              ),

              // Categories
              ProductCategoryPicker(
                viewModel: widget.viewModel,
                selectedCategories: _selectedCategories,
                onChanged: (cats) =>
                    setState(() => _selectedCategories = cats),
              ),
              const SizedBox(height: 12),

              // Options with image assignment from existing + new
              // (shared editor so Add and Edit share one layout).
              OptionsEditorWithImages(
                options: _options,
                existingImages: _gallery
                    .whereType<GalleryExistingImage>()
                    .map((e) => e.url)
                    .toList(),
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
          child: const Text('Cập nhật'),
        ),
      ],
    );
}
