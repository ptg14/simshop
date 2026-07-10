import 'package:flutter/material.dart';

import '../../../models/event.dart';
import 'product_multi_select_dialog.dart';

// ---------------------------------------------------------------------------
// Event dialog (create/edit form)
// ---------------------------------------------------------------------------

class EventDialog extends StatefulWidget {
  const EventDialog({super.key, required this.existing, required this.onSave});

  final Event? existing;
  final Future<void> Function(Event) onSave;

  @override
  State<EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<EventDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valueCtrl;
  DiscountType _type = DiscountType.percent;
  DateTime? _endTime;
  final List<String> _selectedProductIds = [];

  // 7 days from now default — admin picks the actual time below.
  static final _defaultEnd = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _valueCtrl = TextEditingController(
      text: e != null ? _formatValueText(e) : '',
    );
    if (e != null) {
      _type = e.discountType;
      _endTime = e.endTime;
      _selectedProductIds.addAll(e.productIds);
    } else {
      _endTime = _defaultEnd;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  String _formatValueText(Event e) {
    if (e.discountValue == 0) return '';
    if (e.discountType == DiscountType.percent) {
      return e.discountValue.toStringAsFixed(0);
    }
    return e.discountValue.toStringAsFixed(0);
  }

  Future<void> _pickEndTime() async {
    final initial = _endTime ?? _defaultEnd;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    setState(() => _endTime = combined);
  }

  Future<void> _pickProducts() async {
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => ProductMultiSelectDialog(
        existingIds: List<String>.from(_selectedProductIds),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedProductIds
      ..clear()
      ..addAll(picked));
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final value = double.tryParse(_valueCtrl.text.trim()) ?? 0;
    if (value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giá trị giảm phải > 0')),
      );
      return;
    }
    if (_endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn thời gian kết thúc')),
      );
      return;
    }
    final id = widget.existing?.id ??
        'evt-${DateTime.now().microsecondsSinceEpoch}';
    await widget.onSave(Event(
      id: id,
      name: name,
      endTime: _endTime,
      discountType: _type,
      discountValue: value,
      productIds: List<String>.from(_selectedProductIds),
    ));
  }

  String _formatEndTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
      child: AlertDialog(
        title: Text(widget.existing == null ? 'Thêm sự kiện' : 'Sửa sự kiện'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên sự kiện',
                ),
              ),
              const SizedBox(height: 16),
              Text('Loại giảm giá',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<DiscountType>(
                segments: DiscountType.values
                    .map((t) => ButtonSegment<DiscountType>(
                          value: t,
                          label: Text(t.displayLabel),
                        ))
                    .toList(),
                selected: {_type},
                onSelectionChanged: (s) =>
                    setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _valueCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                decoration: InputDecoration(
                  labelText: 'Giá trị giảm',
                  suffixText:
                      _type == DiscountType.percent ? '%' : 'đ',
                ),
              ),
              const SizedBox(height: 16),
              // End-time picker.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickEndTime,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(_endTime == null
                          ? 'Chọn thời gian kết thúc *'
                          : 'Kết thúc: ${_formatEndTime(_endTime!)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Product multi-select.
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _pickProducts,
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: Text(
                        _selectedProductIds.isEmpty
                            ? 'Chọn sản phẩm áp dụng'
                            : 'Sửa danh sách (${_selectedProductIds.length})',
                      ),
                    ),
                  ),
                ],
              ),
              if (_selectedProductIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${_selectedProductIds.length} sản phẩm đã chọn',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy')),
          FilledButton(onPressed: _save, child: const Text('Lưu')),
        ],
      ),
    );
  }
}
