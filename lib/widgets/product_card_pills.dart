import 'package:flutter/material.dart';

/// Pill-shaped label for a product option (e.g. "Đỏ", "Size M").
/// Uses the secondary container colour so it reads as visually
/// distinct from category pills, which use the tertiary container.
class OptionPill extends StatelessWidget {
  const OptionPill({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Pill-shaped label for a category chip. Uses the tertiary
/// container colour so it reads as visually distinct from the
/// option pills above it (which use the secondary container) —
/// customers can tell at a glance "this is a category, not a
/// variant" while scanning the home grid.
class CategoryPill extends StatelessWidget {
  const CategoryPill({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: scheme.onTertiaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Small "+N" indicator pill, used after a truncated pill row.
///
/// Visually consistent with [OptionPill] / [CategoryPill] (same
/// border radius, same vertical alignment) but rendered in
/// [ColorScheme.surfaceContainerHighest] with muted text so the eye
/// reads "more is here, but not the headline".
class OverflowPill extends StatelessWidget {
  const OverflowPill({super.key, required this.extra});
  final int extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '+$extra',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Builds a single horizontal pill strip with overflow protection:
/// shows the first [maxVisible] pills then collapses any tail into a
/// muted "+N" pill.
///
/// Returns a plain [Row] (not a [ListView]) so the caller can spread
/// it into a fixed-aspect-ratio grid cell without the row fighting
/// the cell's bounded height — a horizontal ListView would also
/// work but brings scroll affordances that don't make sense for a
/// 2-3 pill strip. Long pill labels truncate via [TextOverflow.ellipsis]
/// inside [OptionPill] / [CategoryPill].
List<Widget> buildPillRow({
  required List<String> items,
  required Widget Function(String label) pillBuilder,
  required int maxVisible,
}) {
  final visible = items.length <= maxVisible
      ? items
      : items.sublist(0, maxVisible);
  final overflow = items.length - visible.length;
  final children = <Widget>[
    for (var i = 0; i < visible.length; i++) ...[
      if (i > 0) const SizedBox(width: 6),
      pillBuilder(visible[i]),
    ],
    if (overflow > 0) ...[
      const SizedBox(width: 6),
      OverflowPill(extra: overflow),
    ],
  ];
  return children;
}
