import 'package:flutter/material.dart';

import '../../../../utils/responsive.dart';
import '../../../../viewmodels/admin_viewmodel.dart';

/// Category filter for the admin product list.
///
/// Two horizontal pill rows (Large + sub-categories), shaped exactly
/// like the home menu's `CategorySelector`. The row is *driven by*
/// the view-model — every pill reads its selected-state from
/// `vm.filterLarge` / `vm.filterSelectedSubs`, and every tap
/// delegates to the VM via `selectFilterLarge` / `toggleFilterSub`.
///
/// The orphan bucket (`AdminViewModel.orphanBucket`) is rendered as
/// a synthetic Large tag with the Vietnamese label "Chưa phân loại".
/// When that tag is picked the second row shows every orphan sub
/// (`largeCategory == null`), so admins can drill into unparented
/// products.
class AdminProductFilter extends StatelessWidget {
  const AdminProductFilter({super.key, required this.viewModel});

  final AdminViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final largeTags = viewModel.filterLargePills;
    final subs = viewModel.visibleFilterSubs;
    // Build the human-facing labels for the Large row. Internal
    // sentinel [AdminViewModel.orphanBucket] needs to be translated
    // to a localized label, but real Larges pass through unchanged.
    final largeLabels = largeTags
        .map(viewModel.labelForFilterLarge)
        .toList(growable: false);

    if (largeTags.isEmpty) {
      // No Larges AND no orphans — nothing to filter on. Render an
      // empty (zero-height) container rather than wasting vertical
      // space on a "no filters available" hint, since this is the
      // first-run state and the empty-product copy already covers it.
      return const SizedBox.shrink();
    }

    // "Xoá lọc" used to live on its own third row beneath the
    // sub-row. That's three separate vertical bands for what is
    // really one logical control. Moving it into the Large row —
    // at the right edge so it sits AFTER the orphan bucket pill —
    // collapses it into a single scrollable band and means admins
    // can clear the filter with a single horizontal scroll instead
    // of having to drop down a row. The right-side placement keeps
    // "Chưa phân loại" at the leftmost position (the natural
    // anchor for the bucket taxonomy) and tucks the action at the
    // tail of the strip where destructive-style actions belong.
    //
    // The button is only rendered when a filter is active; an
    // always-visible "Xoá lọc" with no filter to clear is dead
    // chrome that adds noise.
    final hasActiveFilter = viewModel.filterLarge != null;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.horizontalPadding,
        vertical: context.responsive<double>(mobile: 4, tablet: 6, desktop: 8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LargeRow(
            labels: largeLabels,
            keys: largeTags,
            selectedKey: viewModel.filterLarge,
            onSelected: viewModel.selectFilterLarge,
            // The clear button is the LAST child of the row, so
            // when the row is wide enough to fit everything it
            // renders at the rightmost position — i.e. to the
            // RIGHT of "Chưa phân loại" and every other Large pill,
            // which is the layout the user asked for. Trailing
            // placement also keeps the orphan bucket as the visual
            // anchor at the left edge of the strip.
            trailing: hasActiveFilter
                ? _ClearFilterButton(
                    onPressed: viewModel.clearFilter,
                    gap: context.responsive<double>(
                        mobile: 8, tablet: 10, desktop: 12),
                  )
                : null,
          ),
          if (viewModel.filterLarge != null && subs.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: context.responsive<double>(
                    mobile: 4, tablet: 6, desktop: 8),
              ),
              child: _SubRow(
                subNames: subs,
                selected: viewModel.filterSelectedSubs,
                onToggled: viewModel.toggleFilterSub,
              ),
            ),
        ],
      ),
    );
  }
}

/// Trailing-edge action button rendered INSIDE the Large row when a
/// filter is active. Sits to the RIGHT of every pill, including the
/// "Chưa phân loại" orphan bucket, so the user can clear the filter
/// without scrolling down to a separate row.
///
/// Visually distinct from the pills (outline button, no stadium
/// background fill) so the row reads as "pills + a single action",
/// not as "an extra filter pill that's confusingly called
/// 'Xoá lọc'".
class _ClearFilterButton extends StatelessWidget {
  const _ClearFilterButton({
    required this.onPressed,
    required this.gap,
  });

  final VoidCallback onPressed;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      // Left gap separates the button from the last pill on its
      // left (e.g. "Chưa phân loại"); right gap would only matter
      // for trailing scroll-edge breathing room which the
      // SingleChildScrollView already provides.
      padding: EdgeInsets.only(left: gap),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.clear, size: 16, color: scheme.primary),
        label: const Text('Xoá lọc'),
        // Outline style so it reads as an *action*, not a pill:
        // - no filled stadium background that would compete with
        //   the active Large pill;
        // - primary-tinted border + text keeps it discoverable;
        // - compact padding so it doesn't visually outweigh the
        //   filters next to it.
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

/// Single-select row of Large pills. Decoupled from the VM so the
/// widget stays pure-presentational and is straightforward to test.
class _LargeRow extends StatelessWidget {
  const _LargeRow({
    required this.labels,
    required this.keys,
    required this.selectedKey,
    required this.onSelected,
    this.trailing,
  });

  /// Display labels for the user, in the same order as [keys].
  final List<String> labels;

  /// Stable keys the view-model compares against [selectedKey]. Same
  /// length and order as [labels]; the orphan sentinel lives here.
  final List<String> keys;

  /// Currently selected Large key (or null = nothing picked).
  final String? selectedKey;

  /// Tap callback. Receives the *key* at the tapped index, not the
  /// label, so the VM never has to translate copy back to a stable
  /// identifier.
  final ValueChanged<String> onSelected;

  /// Optional widget rendered as the LAST child of the row — after
  /// every pill, including "Chưa phân loại". Used by the parent
  /// to inject the clear-filter action at the trailing edge so
  /// "Chưa phân loại" stays anchored at the leftmost position of
  /// the strip.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _FilterPill(
              label: labels[i],
              selected: keys[i] == selectedKey,
              onTap: () => onSelected(keys[i]),
            ),
            if (i != labels.length - 1)
              SizedBox(
                width: context.responsive<double>(
                    mobile: 8, tablet: 10, desktop: 12),
              ),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
}

/// Multi-select row of sub pills. Tap is a toggle — the VM carries
/// the "always at least one selected" invariant.
class _SubRow extends StatelessWidget {
  const _SubRow({
    required this.subNames,
    required this.selected,
    required this.onToggled,
  });

  final List<String> subNames;
  final Set<String> selected;
  final ValueChanged<String> onToggled;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < subNames.length; i++) ...[
            _FilterPill(
              label: subNames[i],
              selected: selected.contains(subNames[i]),
              onTap: () => onToggled(subNames[i]),
            ),
            if (i != subNames.length - 1)
              SizedBox(
                width: context.responsive<double>(
                    mobile: 8, tablet: 10, desktop: 12),
              ),
          ],
        ],
      ),
    );
}

/// A single tappable filter pill. Mirrors the look of the home
/// menu's `CategorySelector` pill (same StadiumBorder + primary
/// highlight) so the two screens feel consistent.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
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
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.responsive<double>(
                  mobile: 14, tablet: 16, desktop: 18),
              vertical: context.responsive<double>(
                  mobile: 6, tablet: 8, desktop: 10),
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
