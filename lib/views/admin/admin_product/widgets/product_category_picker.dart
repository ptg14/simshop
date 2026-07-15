import 'package:flutter/material.dart';
import '../../../../models/category.dart';
import '../../../../utils/responsive.dart';
import '../../../../viewmodels/admin_viewmodel.dart';

/// Two-level category picker for the admin product form.
///
/// Row 1: DropdownButton to select a Large category, with an inline "+" to add
/// a new Large category on the fly.
/// Row 2: ChoiceChips for sub-categories of the selected Large, with an
/// inline "+" to add a new sub-category under that Large. When no Large is
/// selected the row is hidden and replaced with a hint.
class ProductCategoryPicker extends StatefulWidget {
  const ProductCategoryPicker({
    super.key,
    required this.viewModel,
    required this.selectedCategories,
    required this.onChanged,
  });

  final AdminViewModel viewModel;
  final List<String> selectedCategories;
  final ValueChanged<List<String>> onChanged;

  @override
  State<ProductCategoryPicker> createState() => _ProductCategoryPickerState();
}

class _ProductCategoryPickerState extends State<ProductCategoryPicker> {
  final _newLargeController = TextEditingController();
  final _newSubController = TextEditingController();
  bool _addingLarge = false;
  bool _addingSub = false;
  String? _selectedLarge;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    // Defer the prefilling until the first frame so we can read sub-categories
    // populated by the view-model.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePrefillLarge();
  }

  @override
  void didUpdateWidget(covariant ProductCategoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the view-model loaded more data after this widget mounted, try once
    // again to prefill from the now-known subs.
    _maybePrefillLarge();
  }

  void _maybePrefillLarge() {
    if (_prefilled) return;
    if (widget.selectedCategories.isEmpty) {
      _prefilled = true;
      return;
    }
    final subs = widget.viewModel.subCategories;
    for (final name in widget.selectedCategories) {
      for (final c in subs) {
        if (c.name == name && c.largeCategory != null) {
          setState(() {
            _selectedLarge = c.largeCategory;
            _prefilled = true;
          });
          return;
        }
      }
    }
    // If we got here, every selected sub is either unknown or an
    // orphan (largeCategory == null). Either way, leaving
    // [_selectedLarge] null lets [_buildSubRow] surface the orphan
    // chips — the "-- Chọn danh mục lớn --" bucket. Done as one
    // shot so we don't re-run on every rebuild.
    _prefilled = true;
  }

  @override
  void dispose() {
    _newLargeController.dispose();
    _newSubController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _toggleSub(String subName, bool selected) {
    final updated = List<String>.from(widget.selectedCategories);
    if (selected) {
      if (!updated.contains(subName)) updated.add(subName);
    } else {
      updated.remove(subName);
    }
    widget.onChanged(updated);
  }

  void _onLargeChanged(String? newLarge) {
    setState(() => _selectedLarge = newLarge);
    if (newLarge == null) {
      // "-- Chọn danh mục lớn --" selected. Keep orphan subs in the
      // selection (largeCategory == null) — they live under the
      // same UI bucket the dropdown now represents — and drop the
      // ones that belonged to a real Large. Previously this branch
      // wiped the entire selection, which meant switching to
      // "Chọn..." always cleared the picker.
      final orphanNames = widget.viewModel.subCategories
          .where((c) => c.largeCategory == null)
          .map((c) => c.name)
          .toSet();
      final kept = widget.selectedCategories
          .where(orphanNames.contains)
          .toList(growable: false);
      if (kept.length != widget.selectedCategories.length) {
        widget.onChanged(kept);
      }
      return;
    }
    // Drop subs that don't belong to the new Large.
    final allowed = widget.viewModel.subCategories
        .where((c) => c.largeCategory == newLarge)
        .map((c) => c.name)
        .toSet();
    final kept =
        widget.selectedCategories.where(allowed.contains).toList(growable: false);
    if (kept.length != widget.selectedCategories.length) {
      widget.onChanged(kept);
    }
  }

  Future<void> _confirmAddLarge() async {
    final name = _newLargeController.text.trim();
    if (name.isEmpty) return;
    final ok = await widget.viewModel.addLargeCategory(name);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _newLargeController.clear();
        _addingLarge = false;
        _selectedLarge = name;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm danh mục lớn "$name"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể thêm danh mục lớn')),
      );
    }
  }

  Future<void> _confirmAddSub() async {
    final name = _newSubController.text.trim();
    if (name.isEmpty) return;
    // Empty parent string creates an orphan sub on the backend;
    // _selectedLarge == null corresponds to the "-- Chọn danh mục
    // lớn --" bucket the picker now exposes.
    final ok = await widget.viewModel.addCategoryWithParent(name,
        _selectedLarge ?? '');
    if (!mounted) return;
    if (ok) {
      final updated = List<String>.from(widget.selectedCategories)..add(name);
      widget.onChanged(updated);
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.dialogWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel('Danh mục lớn'),
            const SizedBox(height: 6),
            _buildLargeRow(),
            if (_addingLarge) _buildInlineLargeInput(),
            const SizedBox(height: 14),
            _buildLabel('Danh mục con'),
            const SizedBox(height: 6),
            _buildSubRow(),
          ],
        ),
      );

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      );

  Widget _buildLargeRow() => Row(
        children: [
          Expanded(
            child: DropdownButton<String?>(
              value: _selectedLarge,
              isExpanded: true,
              hint: const Text('-- Chọn danh mục lớn --'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('-- Chọn danh mục lớn --'),
                ),
                ...widget.viewModel.largeCategories.map(
                  (n) => DropdownMenuItem<String?>(
                    value: n,
                    child: Text(n),
                  ),
                ),
              ],
              onChanged: _onLargeChanged,
            ),
          ),
          IconButton(
            tooltip: 'Thêm danh mục lớn',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => setState(() {
              _addingLarge = !_addingLarge;
              if (!_addingLarge) _newLargeController.clear();
            }),
          ),
        ],
      );

  Widget _buildInlineLargeInput() => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newLargeController,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Tên danh mục lớn',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                onSubmitted: (_) => _confirmAddLarge(),
              ),
            ),
            IconButton(
              tooltip: 'Tạo',
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: _confirmAddLarge,
            ),
            IconButton(
              tooltip: 'Hủy',
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => setState(() {
                _newLargeController.clear();
                _addingLarge = false;
              }),
            ),
          ],
        ),
      );

  Widget _buildSubRow() {
    // "_selectedLarge == null" now means the user picked the
    // "-- Chọn danh mục lớn --" option, which is the UI bucket for
    // orphan subs (largeCategory == null). Render those as
    // ChoiceChips so admins can tag a product with an unparented
    // sub. Previously the same null value produced a "please pick
    // a large" hint, which forced every product into a parent
    // before any sub could be chosen.
    final bool isOrphanBucket = _selectedLarge == null;
    final List<Category> visibleSubs = (isOrphanBucket
            ? widget.viewModel.subCategories
                .where((c) => c.largeCategory == null)
            : widget.viewModel.subCategories
                .where((c) => c.largeCategory == _selectedLarge))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (visibleSubs.isEmpty && !_addingSub) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOrphanBucket
                ? 'Chưa có danh mục con mồ côi nào'
                : 'Chưa có danh mục con nào thuộc "$_selectedLarge"',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 6),
          _buildAddSubChip(),
          if (_addingSub) _buildInlineSubInput(),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...visibleSubs.map(
          (c) => ChoiceChip(
            label: Text(c.name),
            selected: widget.selectedCategories.contains(c.name),
            onSelected: (sel) => _toggleSub(c.name, sel),
          ),
        ),
        if (_addingSub) _buildInlineSubInput() else _buildAddSubChip(),
      ],
    );
  }

  Widget _buildAddSubChip() => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _addingSub = true),
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

  Widget _buildInlineSubInput() => Container(
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
                controller: _newSubController,
                decoration: const InputDecoration(
                  hintText: 'Danh mục con mới',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
                onSubmitted: (_) => _confirmAddSub(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              tooltip: 'Tạo',
              onPressed: _confirmAddSub,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: 'Hủy',
              onPressed: () => setState(() {
                _newSubController.clear();
                _addingSub = false;
              }),
            ),
          ],
        ),
      );
}
