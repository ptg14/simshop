import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/article.dart';
import '../../models/banner.dart';
import '../../models/product.dart';
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
  final GlobalKey<MarkdownSplitEditorState> _bodyKey =
      GlobalKey<MarkdownSplitEditorState>();

  // Cover image picker state — mirrors the banner dialog's pattern.
  // _coverImageUrl holds the URL of an already-uploaded cover (existing
  // article) or the URL returned after we upload the picked file. On
  // Web the picked bytes are stored in _coverBytes; on mobile the
  // picked XFile path is used at upload time.
  String _coverImageUrl = '';
  XFile? _coverFile;
  Uint8List? _coverBytes;
  bool _uploadingCover = false;

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
      builder: (_) => _ProductPickerDialog(
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
    await widget.onSave(Article(
      id: id,
      title: title,
      body: body,
      coverImageUrl: coverUrl ?? '',
      productIds: List<String>.from(_selectedProductIds),
    ));
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

/// Click-to-pick product dialog backed by [IProductService.searchProducts].
/// Filters out products whose ids are already in [existingIds]. Pops with
/// the picked [Product] (or null if the user cancels).
class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.existingIds});

  final List<String> existingIds;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  Timer? _debounce;
  List<Product> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    // Run an empty search on open so the dialog isn't blank.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _search(v));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lastQuery = query;
    });
    try {
      final svc = context.read<IProductService>();
      final results = await svc.searchProducts(query);
      if (!mounted || query != _lastQuery) return;
      setState(() {
        _results = results
            .where((p) => !widget.existingIds.contains(p.id))
            .toList(growable: false);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
      title: const Text('Chọn sản phẩm'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _queryCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tìm kiếm',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(
                          child: Text('Không tìm thấy sản phẩm'),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, i) {
                            final p = _results[i];
                            return ListTile(
                              leading: p.imageUrl.isEmpty
                                  ? const Icon(Icons.shopping_bag_outlined)
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        p.imageUrl,
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(
                                            Icons.shopping_bag_outlined),
                                      ),
                                    ),
                              title: Text(
                                p.name.isEmpty ? p.id : p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: p.category.isEmpty
                                  ? null
                                  : Text(p.category),
                              onTap: () => Navigator.pop(context, p),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
      ],
    );
}