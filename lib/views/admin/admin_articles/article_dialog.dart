import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/article.dart';
import '../../../models/product.dart';
import '../../../services/product_service.dart';
import '../../../widgets/markdown_split_editor.dart';
import '../banner_image_preview.dart';
import 'product_picker_dialog.dart';

// ---------------------------------------------------------------------------
// Article dialog
// ---------------------------------------------------------------------------

class ArticleDialog extends StatefulWidget {
  const ArticleDialog({super.key, required this.existing, required this.onSave});

  final Article? existing;

  /// [onSave] receives the resolved [Article] plus [oldCoverURL] —
  /// the cover_image_url the row held before this edit. The caller
  /// forwards it as `old_cover_url` so the backend can best-effort
  /// delete the replaced file from /uploads/. Empty string when
  /// there's nothing to clean up.
  final Future<void> Function(Article article, String oldCoverURL) onSave;

  @override
  State<ArticleDialog> createState() => _ArticleDialogState();
}

class _ArticleDialogState extends State<ArticleDialog> {
  late final TextEditingController _titleCtrl;
  final GlobalKey<MarkdownSplitEditorState> _bodyKey =
      GlobalKey<MarkdownSplitEditorState>();

  // Cover image picker state — mirrors the banner dialog's pattern.
  // _coverImageUrl holds the URL of an already-uploaded cover (existing
  // article) or the URL returned after we upload the picked file. On
  // Web the picked bytes are stored in _coverBytes; on mobile the
  // picked XFile path is used at upload time.
  String _coverImageUrl = '';
  XFile? _coverFile;  Uint8List? _coverBytes;
  bool _uploadingCover = false;
  // When the admin clears the existing cover (via the "Xóa ảnh"
  // button — visible only when there's a saved cover and no
  // replacement file staged), we snapshot the prior URL so [_save]
  // can forward it as `old_cover_url`. The replacement path
  // snapshots it too, but only after upload succeeds.
  String? _removedCoverUrl;

  // Selected products for the article. We keep IDs (not full Product
  // objects) so the chip state stays cheap and never goes stale if
  // the product catalog changes between admin edits.
  final List<String> _selectedProductIds = [];
  final List<Product> _selectedProducts = [];

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _coverImageUrl = a?.coverImageUrl ?? '';
    if (a != null && a.productIds.isNotEmpty) {
      _selectedProductIds.addAll(a.productIds);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _coverFile = picked;
      _coverBytes = null;
    });
    if (kIsWeb) {
      _coverBytes = await picked.readAsBytes();
    }
    if (mounted) setState(() {});
  }

  Future<String?> _uploadCover() async {
    if (_coverFile == null) return _coverImageUrl;
    setState(() => _uploadingCover = true);
    try {
      final svc = context.read<IProductService>();
      if (kIsWeb) {
        final bytes = _coverBytes ?? await _coverFile!.readAsBytes();
        return await svc.uploadImage(bytes, productName: 'article-cover');
      }
      return await svc.uploadImage(File(_coverFile!.path),
          productName: 'article-cover');
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _pickProduct() async {
    final result = await showDialog<Product?>(
      context: context,
      builder: (_) => ProductPickerDialog(
        existingIds: List<String>.from(_selectedProductIds),
      ),
    );
    if (result == null || !mounted) return;
    final picked = result;
    if (_selectedProductIds.contains(picked.id)) return;
    setState(() {
      _selectedProductIds.add(picked.id);
      _selectedProducts.add(picked);
    });
  }

  void _removeProduct(String id) {
    setState(() {
      _selectedProductIds.remove(id);
      _selectedProducts.removeWhere((p) => p.id == id);
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tiêu đề')),
      );
      return;
    }
    final coverUrl = await _uploadCover();
    if (!mounted) return;
    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final body = _bodyKey.currentState?.text ?? widget.existing?.body ?? '';
    // Resolve the URL to forward as `old_cover_url`:
    //  - explicit clear path: [_removedCoverUrl] is set, no new
    //    cover was staged.
    //  - replacement path: [_uploadCover] returned a new URL while
    //    [_coverImageUrl] still holds the prior value.
    //  - no-op / first-time create: both empty.
    String oldCoverURL = '';
    final resolved = coverUrl ?? '';
    if (_removedCoverUrl != null && resolved != _removedCoverUrl) {
      oldCoverURL = _removedCoverUrl!;
    } else if (resolved.isNotEmpty && resolved != _coverImageUrl) {
      oldCoverURL = _coverImageUrl;
    }
    await widget.onSave(
      Article(
        id: id,
        title: title,
        body: body,
        coverImageUrl: resolved,
        productIds: List<String>.from(_selectedProductIds),
      ),
      oldCoverURL,
    );
  }

  /// Clear the currently-saved cover image (the "Xóa ảnh" button).
  /// Snapshots the prior URL into [_removedCoverUrl] so [_save] can
  /// forward it to the backend, which best-effort deletes the file
  /// after the PUT commits.
  void _clearCover() {
    setState(() {
      if (_coverImageUrl.isNotEmpty) {
        _removedCoverUrl = _coverImageUrl;
      }
      _coverImageUrl = '';
      _coverFile = null;
      _coverBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
      child: AlertDialog(
        title:
            Text(widget.existing == null ? 'Thêm bài viết' : 'Sửa bài viết'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Tiêu đề *'),
              ),
              const SizedBox(height: 12),
              MarkdownSplitEditor(
                key: _bodyKey,
                initialValue: widget.existing?.body ?? '',
              ),
              const SizedBox(height: 12),
              // Cover image picker — preview thumb + Chọn/Đổi button.
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 50,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: bannerImagePreview(
                      bytes: _coverBytes,
                      file: _coverFile,
                      existingUrl: _coverImageUrl,
                      isWeb: kIsWeb,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _uploadingCover ? null : _pickCover,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                          _coverImageUrl.isEmpty && _coverFile == null
                              ? 'Chọn ảnh bìa'
                              : 'Đổi ảnh bìa'),
                    ),
                  ),
                  // "Xóa ảnh" mirrors the banner dialog — only
                  // visible when there's a saved cover and no
                  // replacement staged.
                  if (_coverImageUrl.isNotEmpty && _coverFile == null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _uploadingCover ? null : _clearCover,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Xóa ảnh bìa',
                      color: scheme.error,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Product picker — click-to-pick dialog with search-as-you-type,
              // backed by IProductService.searchProducts. Selected products
              // render as removable chips below.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _pickProduct,
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text('Chọn sản phẩm'),
                    ),
                  ),
                ],
              ),
              if (_selectedProducts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedProducts
                      .map((p) => InputChip(
                            label: Text(p.name.isEmpty ? p.id : p.name),
                            onDeleted: () => _removeProduct(p.id),
                          ))
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy')),
          FilledButton(onPressed: _save, child: const Text('Lưu')),
        ],
      ),
    );
  }
}
