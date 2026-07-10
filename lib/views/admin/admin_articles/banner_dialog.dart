import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/article.dart';
import '../../../models/banner.dart';
import '../../../services/product_service.dart';
import '../banner_image_preview.dart';

// ---------------------------------------------------------------------------
// Banner dialog
// ---------------------------------------------------------------------------

class BannerDialog extends StatefulWidget {
  const BannerDialog({
    super.key,
    required this.existing,
    required this.articles,
    required this.onSave,
  });

  final BannerSlide? existing;
  final List<Article> articles;
  /// [onSave] receives the resolved [BannerSlide] plus [oldImageURL] —
  /// the URL the row held before this edit. The caller forwards it as
  /// `old_image_url` so the backend can best-effort delete the
  /// replaced file from /uploads/. Empty string when there's nothing
  /// to clean up (create flow, or admin re-saved the same image).
  final Future<void> Function(BannerSlide slide, String oldImageURL) onSave;

  @override
  State<BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends State<BannerDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _ordCtrl;
  String _imageUrl = '';
  XFile? _imageFile;
  Uint8List? _imageBytes;
  String? _articleId;
  bool _uploading = false;
  // When the admin clears the existing banner image (via the
  // "Xóa ảnh" button — visible only when there's a saved image
  // and no replacement file staged), we snapshot the prior URL so
  // [_save] can forward it as `old_image_url`. The replacement-file
  // path snapshots it too, but only after upload succeeds — see
  // [_save] for the snapshot logic.
  String? _removedImageUrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _subtitleCtrl = TextEditingController(text: e?.subtitle ?? '');
    _ordCtrl = TextEditingController(text: (e?.ord ?? 0).toString());
    _imageUrl = e?.imageUrl ?? '';
    _articleId = e?.articleId;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _ordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _imageFile = picked;
      _imageBytes = null;
    });
    if (kIsWeb) {
      _imageBytes = await picked.readAsBytes();
    }
    if (mounted) setState(() {});
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return _imageUrl;
    setState(() => _uploading = true);
    try {
      final svc = context.read<IProductService>();
      if (kIsWeb) {
        final bytes = _imageBytes ?? await _imageFile!.readAsBytes();
        return await svc.uploadImage(bytes, productName: 'banner-image');
      }
      return await svc.uploadImage(File(_imageFile!.path),
          productName: 'banner-image');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final url = await _uploadImage();
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ảnh banner')),
      );
      return;
    }
    final ord = int.tryParse(_ordCtrl.text.trim()) ?? 0;
    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final slide = BannerSlide(
      id: id,
      imageUrl: url,
      title: _titleCtrl.text.trim(),
      subtitle: _subtitleCtrl.text.trim(),
      ord: ord,
      articleId: _articleId,
    );
    // Resolve the URL to forward as `old_image_url`:
    //  - explicit clear button path: [_removedImageUrl] is set,
    //    the new image is empty (admin removed without replacing).
    //  - replacement path: [_uploadImage] returns a new URL while
    //    [_imageUrl] still holds the prior value — snapshot the
    //    prior URL once for the diff.
    //  - first-time create / no-op re-save: both empty — pass "" so
    //    the backend skips cleanup (back-compat behavior).
    String oldImageURL = '';
    if (_removedImageUrl != null && url != _removedImageUrl) {
      oldImageURL = _removedImageUrl!;
    } else if (url != _imageUrl && _imageUrl.isNotEmpty) {
      oldImageURL = _imageUrl;
    }
    await widget.onSave(slide, oldImageURL);
  }

  /// Clear the currently-saved banner image (the "Xóa ảnh" button).
  /// Snapshots the prior URL into [_removedImageUrl] so [_save] can
  /// forward it to the backend, which best-effort deletes the file
  /// after the PUT commits. Without this, every banner removal left
  /// its file on disk.
  void _clearImage() {
    setState(() {
      if (_imageUrl.isNotEmpty) {
        _removedImageUrl = _imageUrl;
      }
      _imageUrl = '';
      _imageFile = null;
      _imageBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: AlertDialog(
        title: Text(widget.existing == null ? 'Thêm banner' : 'Sửa banner'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image preview + pick button.
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
                      bytes: _imageBytes,
                      file: _imageFile,
                      existingUrl: _imageUrl,
                      isWeb: kIsWeb,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _uploading ? null : _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                          _imageUrl.isEmpty && _imageFile == null
                              ? 'Chọn ảnh'
                              : 'Đổi ảnh'),
                    ),
                  ),
                  // "Xóa ảnh" only makes sense when there's a saved
                  // image AND no replacement file staged (the
                  // replacement path snapshots the old URL into
                  // [_removedImageUrl] separately inside [_save]).
                  if (_imageUrl.isNotEmpty && _imageFile == null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _uploading ? null : _clearImage,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Xóa ảnh banner',
                      color: scheme.error,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Tiêu đề (tuỳ chọn)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subtitleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Phụ đề (tuỳ chọn)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ordCtrl,
                decoration: const InputDecoration(labelText: 'Thứ tự (ord)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              if (widget.articles.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: _articleId,
                  decoration: const InputDecoration(
                      labelText: 'Bài viết liên kết (tuỳ chọn)'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Không liên kết —'),
                    ),
                    for (final a in widget.articles)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(
                          a.title.isEmpty ? a.id : a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _articleId = v),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: _uploading ? null : _save,
              child: const Text('Lưu')),
        ],
      ),
    );
  }
}