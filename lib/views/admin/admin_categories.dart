import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive.dart';
import '../../viewmodels/admin_viewmodel.dart';
import 'admin_categories/large_category_card.dart';
import 'admin_categories/orphan_sub_categories_card.dart';

/// Admin categories management screen.
///
/// Shows each Large category as an ExpansionTile with its sub-categories inside.
/// An "Khác" tile at the bottom groups orphan sub-categories
/// (those with no parent Large).
class AdminCategoriesScreen extends StatelessWidget {
  const AdminCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<AdminViewModel>(
      builder: (context, viewModel, _) {
        final larges = viewModel.largeCategories;
        final subs = viewModel.subCategories;
        final orphans =
            subs.where((c) => c.largeCategory == null).toList(growable: false);

        return Column(
          children: [
            // Section header.
            Padding(
              padding: EdgeInsets.all(context.horizontalPadding),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Quản lý danh mục',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onSurface,
                          ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddLargeDialog(context, viewModel),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm danh mục lớn'),
                  ),
                ],
              ),
            ),

            // Body.
            Expanded(
              child: RefreshIndicator(
                color: scheme.primary,
                onRefresh: () async {
                  await viewModel.loadLargeCategories();
                  await viewModel.loadSubCategories();
                },
                child: larges.isEmpty && orphans.isEmpty
                    ? _buildEmpty(context, viewModel)
                    : ListView(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.horizontalPadding,
                          vertical: 8,
                        ),
                        children: [
                          for (final large in larges)
                            LargeCategoryCard(
                              name: large,
                              subs: subs
                                  .where((c) => c.largeCategory == large)
                                  .toList(growable: false),
                            ),
                          if (orphans.isNotEmpty)
                            OrphanSubCategoriesCard(subs: orphans),
                          const SizedBox(height: 24),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, AdminViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 80, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'Chưa có danh mục lớn nào',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Thêm danh mục lớn đầu tiên để bắt đầu',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _showAddLargeDialog(context, viewModel),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm danh mục lớn đầu tiên'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddLargeDialog(BuildContext context, AdminViewModel viewModel) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm danh mục lớn'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên danh mục lớn',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final ok = await viewModel.addLargeCategory(name);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                        ? 'Đã thêm danh mục lớn "$name"'
                        : 'Không thể thêm danh mục lớn "$name"',
                  ),
                ),
              );
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }
}
