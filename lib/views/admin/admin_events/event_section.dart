import 'package:flutter/material.dart';

import '../../../models/event.dart';
import '../../../viewmodels/events_viewmodel.dart';
import 'event_card.dart';
import 'event_dialog.dart';

// ---------------------------------------------------------------------------
// Event section (list + add/edit/delete affordances)
// ---------------------------------------------------------------------------

class EventSection extends StatelessWidget {
  const EventSection({super.key, required this.vm, required this.events});

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
          ...events.map((e) => EventCard(
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
      builder: (ctx) => EventDialog(
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
