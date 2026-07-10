import 'package:flutter/material.dart';

import '../../../models/event.dart';
import 'chip.dart';

// ---------------------------------------------------------------------------
// Countdown chip — derives a human-readable "Còn X / Sắp hết / Đã hết hạn"
// label from [Event.endTime]. Picked over writing a Timer elsewhere because
// [EventCard] rebuilds on every refresh anyway, so a sync computation
// is sufficient.
// ---------------------------------------------------------------------------

class CountdownChip extends StatelessWidget {
  const CountdownChip({
    super.key,
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
    return EventChip(label: label, color: color, fg: fg);
  }
}
