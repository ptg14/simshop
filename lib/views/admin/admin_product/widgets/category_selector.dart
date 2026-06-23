import 'package:flutter/material.dart';
import '../../../../utils/responsive.dart';
import '../../../../viewmodels/admin_viewmodel.dart';

/// Multi-select category chip row with inline "add new category" support.
class CategorySelector extends StatefulWidget {
  const CategorySelector({
    super.key,
    required this.viewModel,
    required this.selectedCategories,
    required this.onChanged,
  });

  final AdminViewModel viewModel;
  final List<String> selectedCategories;
  final ValueChanged<List<String>> onChanged;

  @override
  State<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<CategorySelector> {
  final _newCategoryController = TextEditingController();
  bool _addingCategory = false;

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  void _toggle(String category, bool selected) {
    final updated = List<String>.from(widget.selectedCategories);
    selected ? updated.add(category) : updated.remove(category);
    widget.onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: context.dialogWidth),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...widget.viewModel.categories
              .where((c) => c != 'All')
              .map((c) => ChoiceChip(
                    label: Text(c),
                    selected: widget.selectedCategories.contains(c),
                    onSelected: (sel) => _toggle(c, sel),
                  )),
          if (_addingCategory) _buildInlineInput() else _buildAddChip(),
        ],
      ),
    );

  Widget _buildInlineInput() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _newCategoryController,
              decoration: const InputDecoration(
                hintText: 'Danh mục mới',
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Colors.green),
            tooltip: 'Tạo',
            onPressed: () async {
              final name = _newCategoryController.text.trim();
              if (name.isEmpty) return;
              try {
                await widget.viewModel.addCategory(name);
                final updated = List<String>.from(widget.selectedCategories)
                  ..add(name);
                widget.onChanged(updated);
                setState(() {
                  _newCategoryController.clear();
                  _addingCategory = false;
                });
              } catch (_) {}
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: 'Hủy',
            onPressed: () => setState(() {
              _newCategoryController.clear();
              _addingCategory = false;
            }),
          ),
        ],
      ),
    );

  Widget _buildAddChip() => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _addingCategory = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade400),
          ),
          child: const Icon(Icons.add, size: 20),
        ),
      ),
    );
}