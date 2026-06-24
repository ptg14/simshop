import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';

import '../models/article.dart';
import '../services/article_service.dart';
import '../services/product_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import 'product_detail_screen.dart';

/// Article detail screen.
///
/// Loads the article (and joined products) by [articleId] via
/// [IArticleService.getArticle]. Shows a loading spinner while the
/// request is in flight and a friendly "Bài viết đã bị xóa" empty
/// state when the server returns 404 (the typical case for a banner
/// whose linked article was deleted — the FK cascades to NULL on the
/// server but the home cache may still hold a stale id).
class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.articleId});

  final String articleId;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late Future<ArticleWithProducts?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ArticleWithProducts?> _load() {
    return context.read<IArticleService>().getArticle(widget.articleId);
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bài viết'),
        centerTitle: true,
      ),
      body: FutureBuilder<ArticleWithProducts?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          final data = snapshot.data;
          if (data == null) {
            return const _DeletedView();
          }
          return _ArticleBody(
            article: data.article,
            products: data.products,
          );
        },
      ),
    );
  }
}

class _ArticleBody extends StatelessWidget {
  const _ArticleBody({required this.article, required this.products});

  final Article article;
  final List<ProductStub> products;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: context.maxContentWidth),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.coverImageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    article.coverImageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 200,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.image_not_supported_outlined,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                article.title.isEmpty ? 'Bài viết' : article.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 12),
              MarkdownBody(
                data: article.body.isEmpty
                    ? '_(Bài viết chưa có nội dung)_'
                    : article.body,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
              ),
              if (products.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Sản phẩm nhắc đến',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                ),
                const SizedBox(height: 12),
                // Vertical list of products (one per row), not a
                // chip wrap. User feedback: chips read as a tag cloud
                // and obscured the article's CTA; a list surfaces each
                // product as a tappable card with image + name.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final stub in products)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ProductRow(stub: stub),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single product row inside the article body. Renders as a
/// tappable Card with a leading thumbnail, the product name, and a
/// chevron hint so the row reads as "tap to open the product".
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.stub});
  final ProductStub stub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openProduct(context),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Thumbnail (or placeholder icon).
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: stub.imageUrl.isEmpty
                    ? Icon(Icons.shopping_bag_outlined,
                        color: scheme.onSurfaceVariant)
                    : Image.network(
                        stub.imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.shopping_bag_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Name (left-aligned, ellipsized).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stub.name.isEmpty ? stub.id : stub.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Xem chi tiết',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProduct(BuildContext context) async {
    final productService = context.read<IProductService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final product = await productService.getProductById(stub.id);
      if (!context.mounted) return;
      Navigator.of(context).push(
        fadeSlideRoute(ProductDetailScreen(product: product)),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Không thể mở sản phẩm: $e')),
      );
    }
  }
}

class _DeletedView extends StatelessWidget {
  const _DeletedView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 80, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Bài viết đã bị xóa',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bài viết gắn với banner này không còn tồn tại.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'Không thể tải bài viết',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper kept for callers that still hold an [Article] (kept for
/// backwards compatibility in the slice 1 widget test). Prefer
/// [openArticleIdRoute] in production code.
Route<void> openArticleRoute(Article article) =>
    fadeSlideRoute(ArticleScreen(articleId: article.id));

/// Preferred helper: build the screen with a fade + slide transition
/// for an article id.
Route<void> openArticleIdRoute(String articleId) =>
    fadeSlideRoute(ArticleScreen(articleId: articleId));
