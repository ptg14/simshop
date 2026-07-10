import 'package:flutter/material.dart';

import '../../../models/article.dart';
import '../../../models/banner.dart';
import '../../../viewmodels/articles_viewmodel.dart';
import 'article_dialog.dart';

// ---------------------------------------------------------------------------
// Article section
// ---------------------------------------------------------------------------

class ArticleSection extends StatelessWidget {
  const ArticleSection({
    super.key,
    required this.articles,
    required this.vm,
    required this.banners,
  });

  final List<Article> articles;
  final ArticlesViewModel vm;
  // The [banners] param is currently unused at this layer but kept
  // on the public API so the AdminArticlesScreen can pass it without
  // a custom wrapper — and so future banner-related affordances
  // (e.g. an article→banner cross-link display) have a hook.
  // ignore: unused_element
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
      builder: (ctx) => ArticleDialog(
        existing: existing,
        onSave: (article, oldCoverURL) async {
          final ok = existing == null
              ? await vm.createArticle(article, oldCoverURL: oldCoverURL)
              : await vm.updateArticle(article, oldCoverURL: oldCoverURL);
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