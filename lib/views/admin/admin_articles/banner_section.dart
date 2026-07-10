import 'package:flutter/material.dart';

import '../../../models/banner.dart';
import '../../../viewmodels/articles_viewmodel.dart';
import '../../../widgets/network_image.dart';
import 'banner_dialog.dart';

// ---------------------------------------------------------------------------
// Banner section
// ---------------------------------------------------------------------------

class BannerSection extends StatelessWidget {
  const BannerSection({required this.banners, required this.vm});

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
      builder: (ctx) => BannerDialog(
        existing: existing,
        articles: vm.articles,
        onSave: (slide, oldImageURL) async {
          final ok = existing == null
              ? await vm.createBanner(slide, oldImageURL: oldImageURL)
              : await vm.updateBanner(slide, oldImageURL: oldImageURL);
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