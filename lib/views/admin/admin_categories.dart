import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/category.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/admin_viewmodel.dart';

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
                            _LargeCategoryCard(
                              name: large,
                              subs: subs
                                  .where((c) => c.largeCategory == large)
                                  .toList(growable: false),
                            ),
                          if (orphans.isNotEmpty)
                            _OrphanSubCategoriesCard(subs: orphans),
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
            hintText: 'VD: Thời trang, Điện tử, ...',
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

// ---------------------------------------------------------------------------
// ExpansionTile card for a single Large category + its sub-categories.
// ---------------------------------------------------------------------------

class _LargeCategoryCard extends StatefulWidget {
  const _LargeCategoryCard({required this.name, required this.subs});

  final String name;
  final List<Category> subs;

  @override
  State<_LargeCategoryCard> createState() => _LargeCategoryCardState();
}

class _LargeCategoryCardState extends State<_LargeCategoryCard> {
  final _newSubController = TextEditingController();
  bool _addingSub = false;

  @override
  void dispose() {
    _newSubController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewModel = context.read<AdminViewModel>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(Icons.folder, color: scheme.primary),
        title: Text(
          widget.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${widget.subs.length} danh mục con'),
        trailing: IconButton(
          tooltip: 'Xóa danh mục lớn',
          icon: Icon(Icons.delete_outline, color: scheme.error),
          onPressed: () =>
              _confirmDeleteLarge(context, viewModel, widget.name),
        ),
        children: [
          if (widget.subs.isEmpty && !_addingSub)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Chưa có danh mục con nào',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          for (final sub in widget.subs)
            ListTile(
              leading: Icon(Icons.label_outline, color: scheme.onSurfaceVariant),
              title: Text(sub.name),
              dense: true,
              trailing: IconButton(
                tooltip: 'Xóa danh mục con',
                icon: Icon(Icons.delete, color: scheme.error, size: 20),
                onPressed: () =>
                    _confirmDeleteSub(context, viewModel, sub.name),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _addingSub
                ? _buildInlineSubInput(viewModel)
                : Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _addingSub = true),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm danh mục con'),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineSubInput(AdminViewModel viewModel) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _newSubController,
            autofocus: true,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Tên danh mục con',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onSubmitted: (_) => _confirmAddSub(viewModel),
          ),
        ),
        IconButton(
          tooltip: 'Tạo',
          icon: Icon(Icons.check, color: scheme.primary),
          onPressed: () => _confirmAddSub(viewModel),
        ),
        IconButton(
          tooltip: 'Hủy',
          icon: Icon(Icons.close, color: scheme.error),
          onPressed: () => setState(() {
            _newSubController.clear();
            _addingSub = false;
          }),
        ),
      ],
    );
  }

  Future<void> _confirmAddSub(AdminViewModel viewModel) async {
    final name = _newSubController.text.trim();
    if (name.isEmpty) return;
    final ok = await viewModel.addCategoryWithParent(name, widget.name);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _newSubController.clear();
        _addingSub = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm danh mục con "$name"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể thêm danh mục con')),
      );
    }
  }

  void _confirmDeleteLarge(
      BuildContext context, AdminViewModel viewModel, String name) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa danh mục lớn'),
        content: Text(
          'Bạn có chắc muốn xóa danh mục lớn "$name"? '
          'Các danh mục con sẽ trở thành danh mục mồ côi (hiển thị ở nhóm "Khác").',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await viewModel.deleteLargeCategory(name);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Đã xóa danh mục lớn "$name"'
                      : 'Không thể xóa danh mục lớn "$name"'),
                ),
              );
            },
            child: Text('Xóa', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSub(
      BuildContext context, AdminViewModel viewModel, String name) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa danh mục con'),
        content: Text('Bạn có chắc muốn xóa danh mục con "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await viewModel.deleteSubCategory(name);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Đã xóa danh mục con "$name"'
                      : 'Không thể xóa danh mục con "$name"'),
                ),
              );
            },
            child: Text('Xóa', style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card for orphan sub-categories (sub whose Large has been deleted).
// ---------------------------------------------------------------------------

class _OrphanSubCategoriesCard extends StatelessWidget {
  const _OrphanSubCategoriesCard({required this.subs});

  final List<Category> subs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewModel = context.read<AdminViewModel>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(Icons.help_outline, color: scheme.tertiary),
        title: const Text(
          'Khác',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${subs.length} danh mục con mồ côi'),
        children: [
          for (final sub in subs)
            ListTile(
              leading: Icon(Icons.label_outline, color: scheme.onSurfaceVariant),
              title: Text(sub.name),
              dense: true,
              trailing: IconButton(
                tooltip: 'Xóa danh mục con',
                icon: Icon(Icons.delete, color: scheme.error, size: 20),
                onPressed: () async {
                  final ok = await viewModel.deleteSubCategory(sub.name);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Đã xóa danh mục con "${sub.name}"'
                          : 'Không thể xóa danh mục con "${sub.name}"'),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
