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
    required this.selectedSub,
    required this.onSubSelected,
  });

  final List<String> largeCategories;
  final String selectedLarge;
  final ValueChanged<String> onLargeSelected;

  /// Sub-categories of the currently selected Large. Caller should pass
  /// `[]` to hide the sub row (typically when `selectedLarge == 'All'`).
  final List<String> subCategories;
  final String selectedSub;
  final ValueChanged<String> onSubSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              child: _buildRow(
                context: context,
                items: subCategories,
                selected: selectedSub,
                onSelected: onSubSelected,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required BuildContext context,
    required List<String> items,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return SingleChildScrollView(
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
  }
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
