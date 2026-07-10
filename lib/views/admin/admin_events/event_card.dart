import 'package:flutter/material.dart';

import '../../../models/event.dart';
import 'chip.dart';
import 'countdown_chip.dart';

// ---------------------------------------------------------------------------
// Event card + supporting chips
// ---------------------------------------------------------------------------

class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
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
                EventChip(
                  label: event.formatDiscount(),
                  color: active
                      ? scheme.tertiaryContainer
                      : scheme.surfaceContainerHighest,
                  fg: active
                      ? scheme.onTertiaryContainer
                      : scheme.onSurfaceVariant,
                ),
                EventChip(
                  label: '${event.productIds.length} sản phẩm',
                  color: scheme.secondaryContainer,
                  fg: scheme.onSecondaryContainer,
                ),
                CountdownChip(event: event, remaining: remaining, active: active),
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
