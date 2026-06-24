import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/article.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';

/// Article detail screen.
///
/// Slice 1: takes the full [Article] object directly (no fetch). Slice 4
/// changes the constructor to accept an `articleId` and fetches via
/// `IArticleService.getArticle`.
class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          article.title.isEmpty ? 'Bài viết' : article.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: Center(
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
                  article.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                ),
                const SizedBox(height: 12),
                MarkdownBody(
                  data: article.body.isEmpty ? '_(Bài viết chưa có nội dung)_' : article.body,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper kept for the slice-4 refactor: build the screen with a fade
/// + slide transition so callers can `Navigator.push(_openArticle(a))`.
Route<void> openArticleRoute(Article article) =>
    fadeSlideRoute(ArticleScreen(article: article));
