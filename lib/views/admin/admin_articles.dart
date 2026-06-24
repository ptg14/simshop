import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/banner.dart';
import '../../services/product_service.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/articles_viewmodel.dart';
import '../../widgets/markdown_split_editor.dart';
import '../../widgets/network_image.dart';
import 'banner_image_preview.dart';

/// Admin "Bài viết" tab. Manages banner slides (carousel) and the
/// articles that open when a slide is tapped.
///
/// Slice 3 ships a plain TextField for the article body. Slice 4
/// replaces it with a split-pane Markdown editor.
class AdminArticlesScreen extends StatefulWidget {
  const AdminArticlesScreen({super.key});

  @override
  State<AdminArticlesScreen> createState() => _AdminArticlesScreenState();
}

class _AdminArticlesScreenState extends State<AdminArticlesScreen> {
  @override
  void initState() {
    super.initState();
    // Pull the article list on first render so the table is populated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ArticlesViewModel>().loadArticles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<ArticlesViewModel>(
      builder: (context, vm, _) {
        return RefreshIndicator(
          color: scheme.primary,
          onRefresh: () async {
            await vm.load();
            await vm.loadArticles();
          },
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: context.horizontalPadding,
              vertical: 16,
            ),
            children: [
              Text(
                'Quản lý bài viết',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Banner trên trang chủ và bài viết tương ứng khi bấm vào banner',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),

              _BannerSection(banners: vm.banners, vm: vm),
              const SizedBox(height: 32),
              _ArticleSection(articles: vm.articles, vm: vm, banners: vm.banners),

              if (vm.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(vm.error!,
                      style: TextStyle(color: scheme.onErrorContainer)),
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Banner section
// ---------------------------------------------------------------------------

class _BannerSection extends StatelessWidget {
  const _BannerSection({required this.banners, required this.vm});

  final List<BannerSlide> banners;
  final ArticlesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Banner (${banners.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showBannerDialog(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Thêm banner'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (banners.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chưa có banner nào. Bấm "Thêm banner" để tạo slide đầu tiên.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ...banners.map(
            (b) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: SizedBox(
                  width: 64,
                  height: 40,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AppNetworkImage(
                      url: b.imageUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                title: Text(b.title.isEmpty ? '(không tiêu đề)' : b.title),
                subtitle: Text(
                  [
                    if (b.subtitle.isNotEmpty) b.subtitle,
                    if (b.articleId != null) '→ bài viết ${b.articleId}',
                    'ord=${b.ord}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showBannerDialog(context, b),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDeleteBanner(context, b),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showBannerDialog(BuildContext context, BannerSlide? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _BannerDialog(
        existing: existing,
        articles: vm.articles,
        onSave: (slide) async {
          final ok = existing == null
              ? await vm.createBanner(slide)
              : await vm.updateBanner(slide);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(ok ? 'Đã lưu banner' : (vm.error ?? 'Lỗi')),
          ));
        },
      ),
    );
  }

  Future<void> _confirmDeleteBanner(BuildContext context, BannerSlide b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa banner?'),
        content: Text('Banner "${b.title.isEmpty ? b.id : b.title}" sẽ bị xóa.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await vm.deleteBanner(b.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xóa banner' : (vm.error ?? 'Lỗi')),
    ));
  }
}

class _BannerDialog extends StatefulWidget {
  const _BannerDialog({
    required this.existing,
    required this.articles,
    required this.onSave,
  });

  final BannerSlide? existing;
  final List<Article> articles;
  final Future<void> Function(BannerSlide) onSave;

  @override
  State<_BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends State<_BannerDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _ordCtrl;
  String _imageUrl = '';
  XFile? _imageFile;
  Uint8List? _imageBytes;
  String? _articleId;
  bool _uploading = false;

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
    await widget.onSave(slide);
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

// ---------------------------------------------------------------------------
// Article section
// ---------------------------------------------------------------------------

class _ArticleSection extends StatelessWidget {
  const _ArticleSection({
    required this.articles,
    required this.vm,
    required this.banners,
  });

  final List<Article> articles;
  final ArticlesViewModel vm;
  final List<BannerSlide> banners;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Bài viết (${articles.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showArticleDialog(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Thêm bài viết'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (articles.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chưa có bài viết nào. Bấm "Thêm bài viết" để tạo.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ...articles.map(
            (a) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(a.title.isEmpty ? '(không tiêu đề)' : a.title),
                subtitle: Text(
                  '${a.body.length} ký tự · ${a.productIds.length} sản phẩm',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showArticleDialog(context, a),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, a),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showArticleDialog(BuildContext context, Article? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _ArticleDialog(
        existing: existing,
        onSave: (article) async {
          final ok = existing == null
              ? await vm.createArticle(article)
              : await vm.updateArticle(article);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(ok ? 'Đã lưu bài viết' : (vm.error ?? 'Lỗi')),
          ));
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Article a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa bài viết?'),
        content: const Text(
            'Bài viết sẽ bị xóa. Banner liên kết sẽ giữ nhưng không mở được bài.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await vm.deleteArticle(a.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xóa bài viết' : (vm.error ?? 'Lỗi')),
    ));
  }
}

class _ArticleDialog extends StatefulWidget {
  const _ArticleDialog({required this.existing, required this.onSave});

  final Article? existing;
  final Future<void> Function(Article) onSave;

  @override
  State<_ArticleDialog> createState() => _ArticleDialogState();
}

class _ArticleDialogState extends State<_ArticleDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _coverCtrl;
  late final TextEditingController _productIdsCtrl;
  final GlobalKey<MarkdownSplitEditorState> _bodyKey =
      GlobalKey<MarkdownSplitEditorState>();

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _coverCtrl = TextEditingController(text: a?.coverImageUrl ?? '');
    _productIdsCtrl = TextEditingController(text: (a?.productIds ?? []).join(', '));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _coverCtrl.dispose();
    _productIdsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tiêu đề')),
      );
      return;
    }
    final productIds = _productIdsCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final id = widget.existing?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final body = _bodyKey.currentState?.text ?? widget.existing?.body ?? '';
    await widget.onSave(Article(
      id: id,
      title: title,
      body: body,
      coverImageUrl: _coverCtrl.text.trim(),
      productIds: productIds,
    ));
  }

  @override
  Widget build(BuildContext context) {
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
              TextField(
                controller: _coverCtrl,
                decoration:
                    const InputDecoration(labelText: 'Ảnh bìa (URL)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _productIdsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Sản phẩm nhắc đến (ID, phân cách dấu phẩy)',
                ),
              ),
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