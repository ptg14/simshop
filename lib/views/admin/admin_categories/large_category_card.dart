import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/category.dart';
import '../../../viewmodels/admin_viewmodel.dart';

// ---------------------------------------------------------------------------
// ExpansionTile card for a single Large category + its sub-categories.
// ---------------------------------------------------------------------------

class LargeCategoryCard extends StatefulWidget {
  const LargeCategoryCard({super.key, required this.name, required this.subs});

  final String name;
  final List<Category> subs;

  @override
  State<LargeCategoryCard> createState() => _LargeCategoryCardState();
}

class _LargeCategoryCardState extends State<LargeCategoryCard> {
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
