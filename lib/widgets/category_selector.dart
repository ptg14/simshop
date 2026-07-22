import 'package:flutter/material.dart';
import '../utils/responsive.dart';

/// Two-row category selector for the home/shop screen.
///
/// Row 1: pill chips for "All" + each Large category.
/// Row 2: pill chips for the sub-categories of the selected Large (hidden
/// when "All" is selected).
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    super.key,
    required this.largeCategories,
    required this.selectedLarge,
    required this.onLargeSelected,
    required this.subCategories,
    required this.selectedSubs,
    required this.onSubToggled,
  });

  final List<String> largeCategories;
  final String selectedLarge;
  final ValueChanged<String> onLargeSelected;

  /// Sub-categories of the currently selected Large. Caller should pass
  /// `[]` to hide the sub row (typically when `selectedLarge == 'All'`).
  final List<String> subCategories;

  /// Set of currently-selected sub-categories. Any sub in
  /// [subCategories] that appears here is rendered as selected.
  /// The widget itself does not enforce the "always at least one
  /// entry" invariant — that's the view-model's job.
  final Set<String> selectedSubs;

  /// Fired when the user taps any sub pill. The view-model is
  /// expected to apply its own add/remove/auto-All logic and
  /// re-emit a new [selectedSubs] set.
  final ValueChanged<String> onSubToggled;

  @override
  Widget build(BuildContext context) => Container(
      margin: EdgeInsets.symmetric(
        vertical: context.responsive<double>(mobile: 8, tablet: 10, desktop: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRow(
            context: context,
            items: largeCategories,
            selected: selectedLarge,
            onSelected: onLargeSelected,
          ),
          if (subCategories.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: context.responsive<double>(
                    mobile: 6, tablet: 8, desktop: 10),
              ),
              child: _buildMultiRow(
                context: context,
                items: subCategories,
                selectedSubs: selectedSubs,
                onToggled: onSubToggled,
              ),
            ),
        ],
      ),
    );

  /// Single-select row (Large).
  Widget _buildRow({
    required BuildContext context,
    required List<String> items,
    required String selected,
    required ValueChanged<String> onSelected,
  }) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _CategoryPill(
              label: items[i],
              selected: items[i] == selected,
              onTap: () => onSelected(items[i]),
            ),
            if (i != items.length - 1)
              SizedBox(
                width: context.responsive<double>(
                    mobile: 8, tablet: 10, desktop: 12),
              ),
          ],
        ],
      ),
    );

  /// Multi-select row (subs). The tap is a toggle — the view-model
  /// decides whether the click adds or removes the entry.
  Widget _buildMultiRow({
    required BuildContext context,
    required List<String> items,
    required Set<String> selectedSubs,
    required ValueChanged<String> onToggled,
  }) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: context.horizontalPadding),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _CategoryPill(
              label: items[i],
              selected: selectedSubs.contains(items[i]),
              onTap: () => onToggled(items[i]),
            ),
            if (i != items.length - 1)
              SizedBox(
                width: context.responsive<double>(
                    mobile: 8, tablet: 10, desktop: 12),
              ),
          ],
        ],
      ),
    );
}

/// A single tappable category pill.
///
/// Uses [Material] + [InkWell] so it is:
///   • keyboard-focusable (Tab to focus, Enter/Space to activate)
///   • screen-reader-friendly (button role + label)
///   • ripple-feedback on press
class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: context.responsive<double>(
                  mobile: 16, tablet: 18, desktop: 20),
              vertical: context.responsive<double>(
                  mobile: 8, tablet: 10, desktop: 12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimary : scheme.onSurface,
                fontSize: context.responsive<double>(
                  mobile: 13,
                  tablet: 14,
                  desktop: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
