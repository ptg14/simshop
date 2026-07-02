import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/event.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../utils/responsive.dart';
import '../../viewmodels/events_viewmodel.dart';

/// Admin "Sự kiện" tab. CRUD for time-boxed promotional events.
///
/// Each event attaches a discount (percent or fixed) to a list of
/// products; the backend reads the active events on every product
/// query and decorates each product with `effective_price` +
/// `current_event`. Expired events stay in this list so the admin
/// can badge them as "Đã hết hạn" rather than having them vanish.
class AdminEventsScreen extends StatefulWidget {
  const AdminEventsScreen({super.key});

  @override
  State<AdminEventsScreen> createState() => _AdminEventsScreenState();
}

class _AdminEventsScreenState extends State<AdminEventsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<EventsViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Consumer<EventsViewModel>(
      builder: (context, vm, _) {
        return RefreshIndicator(
          color: scheme.primary,
          onRefresh: vm.load,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: context.horizontalPadding,
              vertical: 16,
            ),
            children: [
              Text(
                'Quản lý sự kiện',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tạo đợt khuyến mãi giảm giá cho nhiều sản phẩm. Sự kiện hết hạn sẽ tự động không áp dụng.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              _EventSection(vm: vm, events: vm.events),
              if (vm.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    vm.error!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
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

class _EventSection extends StatelessWidget {
  const _EventSection({required this.vm, required this.events});

  final EventsViewModel vm;
  final List<Event> events;

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
                'Sự kiện (${events.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showEventDialog(context, null),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sự kiện'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chưa có sự kiện nào. Bấm "Thêm sự kiện" để tạo đợt khuyến mãi đầu tiên.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
        else
          ...events.map((e) => _EventCard(
                event: e,
                onEdit: () => _showEventDialog(context, e),
                onDelete: () => _confirmDelete(context, e),
              )),
      ],
    );
  }

  void _showEventDialog(BuildContext context, Event? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _EventDialog(
        existing: existing,
        onSave: (event) async {
          final ok = existing == null
              ? await vm.createEvent(event)
              : await vm.updateEvent(event);
          if (!ctx.mounted) return;
          Navigator.pop(ctx);
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text(
                ok ? 'Đã lưu sự kiện' : (vm.error ?? 'Lỗi')),
          ));
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Event e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa sự kiện?'),
        content: Text(
          'Sự kiện "${e.name.isEmpty ? e.id : e.name}" sẽ bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await vm.deleteEvent(e.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xóa sự kiện' : (vm.error ?? 'Lỗi')),
    ));
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  final Event event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now().toUtc();
    final active = event.isActive(now);
    final remaining = event.endTime?.difference(now);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: active
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          foregroundColor: active
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
          child: const Icon(Icons.local_offer_outlined),
        ),
        title: Text(
          event.name.isEmpty ? '(không tên)' : event.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _Chip(
                  label: event.formatDiscount(),
                  color: active
                      ? scheme.tertiaryContainer
                      : scheme.surfaceContainerHighest,
                  fg: active
                      ? scheme.onTertiaryContainer
                      : scheme.onSurfaceVariant,
                ),
                _Chip(
                  label: '${event.productIds.length} sản phẩm',
                  color: scheme.secondaryContainer,
                  fg: scheme.onSecondaryContainer,
                ),
                _CountdownChip(event: event, remaining: remaining, active: active),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.fg});
  final String label;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      );
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({
    required this.event,
    required this.remaining,
    required this.active,
  });
  final Event event;
  final Duration? remaining;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String label;
    Color color;
    Color fg;
    if (!active || remaining == null) {
      label = 'Đã hết hạn';
      color = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else if (remaining!.isNegative) {
      label = 'Đã hết hạn';
      color = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else if (remaining!.inDays >= 1) {
      label = 'Còn ${remaining!.inDays} ngày';
      color = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (remaining!.inHours >= 1) {
      label = 'Còn ${remaining!.inHours} giờ';
      color = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else if (remaining!.inMinutes >= 1) {
      label = 'Còn ${remaining!.inMinutes} phút';
      color = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else {
      label = 'Sắp hết hạn';
      color = scheme.tertiaryContainer;
      fg = scheme.onTertiaryContainer;
    }
    return _Chip(label: label, color: color, fg: fg);
  }
}

class _EventDialog extends StatefulWidget {
  const _EventDialog({required this.existing, required this.onSave});

  final Event? existing;
  final Future<void> Function(Event) onSave;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _valueCtrl;
  DiscountType _type = DiscountType.percent;
  DateTime? _endTime;
  final List<String> _selectedProductIds = [];

  // 24h from now default — admin picks the actual time below.
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
      builder: (_) => _ProductMultiSelectDialog(
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

  String _formatEndTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Multi-select product picker for the event dialog. Pops with the
/// set of selected IDs (or null on cancel).
///
/// Modeled after `_ProductPickerDialog` in admin_articles.dart but
/// keeps an internal selection set so the user can toggle several
/// items and commit them in one action via the bottom "Xong" button.
class _ProductMultiSelectDialog extends StatefulWidget {
  const _ProductMultiSelectDialog({required this.existingIds});

  final List<String> existingIds;

  @override
  State<_ProductMultiSelectDialog> createState() =>
      _ProductMultiSelectDialogState();
}

class _ProductMultiSelectDialogState
    extends State<_ProductMultiSelectDialog> {
  final TextEditingController _queryCtrl = TextEditingController();
  final Set<String> _selected = <String>{};
  List<Product> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.existingIds);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    // Simple debounce via Future.delayed — keeps a stale frame from
    // overwriting a newer one.
    final myQuery = v;
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted || myQuery != _lastQuery && _queryCtrl.text != myQuery) {
        return;
      }
      _search(myQuery);
    });
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lastQuery = query;
    });
    try {
      final svc = context.read<IProductService>();
      final results = await svc.searchProducts(query);
      if (!mounted || query != _lastQuery) return;
      setState(() {
        _results = results;
      });
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
          'Chọn sản phẩm (${_selected.length} đã chọn)',
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _queryCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tìm kiếm',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _onChanged,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? const Center(child: Text('Không tìm thấy sản phẩm'))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final p = _results[i];
                              final selected = _selected.contains(p.id);
                              return CheckboxListTile(
                                value: selected,
                                onChanged: (v) {
                                  setState(() {
                                    if (v ?? false) {
                                      _selected.add(p.id);
                                    } else {
                                      _selected.remove(p.id);
                                    }
                                  });
                                },
                                title: Text(
                                  p.name.isEmpty ? p.id : p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: p.category.isEmpty
                                    ? null
                                    : Text(p.category),
                                secondary: p.imageUrl.isEmpty
                                    ? const Icon(Icons.shopping_bag_outlined)
                                    : ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        child: Image.network(
                                          p.imageUrl,
                                          width: 36,
                                          height: 36,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                                  Icons.shopping_bag_outlined),
                                        ),
                                      ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('Xong'),
          ),
        ],
      );
}