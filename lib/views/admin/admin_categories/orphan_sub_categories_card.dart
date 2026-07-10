import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/category.dart';
import '../../../viewmodels/admin_viewmodel.dart';

// ---------------------------------------------------------------------------
// Card for orphan sub-categories (sub whose Large has been deleted).
// ---------------------------------------------------------------------------

class OrphanSubCategoriesCard extends StatelessWidget {
  const OrphanSubCategoriesCard({super.key, required this.subs});

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
