import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Tiny pill chip used by [EventCard] / [CountdownChip].
// ---------------------------------------------------------------------------

class EventChip extends StatelessWidget {
  const EventChip({
    super.key,
    required this.label,
    required this.color,
    required this.fg,
  });
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
