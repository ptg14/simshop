import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive.dart';
import '../../viewmodels/articles_viewmodel.dart';
import 'admin_articles/article_section.dart';
import 'admin_articles/banner_section.dart';

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

              BannerSection(banners: vm.banners, vm: vm),
              const SizedBox(height: 32),
              ArticleSection(articles: vm.articles, vm: vm, banners: vm.banners),

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
