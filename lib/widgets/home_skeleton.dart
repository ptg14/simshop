import 'package:flutter/material.dart';
import '../utils/responsive.dart';
import 'shimmer_placeholder.dart';

/// Skeleton placeholder for [HomeScreen] used while the initial network
/// loads are in flight.
///
/// Rendered on the very first frame instead of a [CircularProgressIndicator]
/// so the user sees the home page layout (carousel band, category chips,
/// product grid silhouette) immediately. The shimmer pulse matches the
/// rest of the app — see [ShimmerBox] for the shared placeholder
/// machinery. When `HomeViewModel.products` becomes non-empty we swap the
/// whole screen to the real grid in one rebuild, which is faster than
/// re-laying the tree out across a spinner transition.
///
/// The widget is stateless and only renders — it does not own or read
/// any provider, so calling it from the very first [build] does not
/// force any other [ChangeNotifierProvider] in the tree to construct.
/// That matches the perf goal of [HomeViewModel]'s `lazy: true` mount.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  // Block body on purpose — the inline comments above the
  // ShimmerPlaceholder wrap and the per-section LayoutBuilder explain
  // why we paint all skeleton cells up-front (no lazy viewport) and
  // why the chip widths vary. Collapsing to `=> ShimmerPlaceholder(...)`
  // would silently drop them.
  // ignore: prefer_expression_function_bodies
  Widget build(BuildContext context) {
    return ShimmerPlaceholder(
      // Wrap once around the whole skeleton so a single AnimationController
      // pulses every box in lockstep. Wrapping each box in its own
      // ShimmerPlaceholder would spin up dozens of controllers and
      // make the shimmer feel out-of-sync across rows.
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: context.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: context.responsive<double>(
                  mobile: 12,
                  tablet: 20,
                  desktop: 24,
                )),
                // Carousel band — same height as the real
                // [ImageCarousel] so when the banners arrive the
                // height doesn't jump.
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.horizontalPadding,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ShimmerBox(
                      height: context.carouselHeight,
                      width: double.infinity,
                    ),
                  ),
                ),
                // Category selector placeholder. Same horizontal
                // padding as [CategorySelector] so the chip row
                // doesn't jump sideways when the real categories
                // arrive.
                Container(
                  margin: EdgeInsets.symmetric(
                    vertical: context.responsive<double>(
                      mobile: 8,
                      tablet: 10,
                      desktop: 12,
                    ),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: context.horizontalPadding,
                  ),
                  child: _ChipSkeletonRow(),
                ),
                // Product grid placeholder. We render *all* the boxes
                // here (no viewport-aware lazy build) because:
                //   • shrinking the grid would make the column get a
                //     scrollbar before data lands, causing another
                //     relayout when products resolve.
                //   • the box count (≈ gridColumns × 2 rows) is
                //     small enough that the layout cost is
                //     negligible — they're plain ShimmerBox widgets
                //     with no image decoding.
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.horizontalPadding,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = context.gridColumns;
                      final spacing = context.gridSpacing;
                      final cellHeight = context.productCardHeight;
                      // Two rows of placeholders is enough to suggest
                      // the grid shape without painting hundreds of
                      // shimmer boxes on the first frame.
                      const skeletonRows = 2;
                      final totalCells = crossAxisCount * skeletonRows;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          for (var i = 0; i < totalCells; i++)
                            SizedBox(
                              // Width derived from the same math as
                              // SliverGridDelegateWithFixedCrossAxisCount
                              // (parent usable width / cross axis
                              // count, minus the inter-cell spacing)
                              // so the column count matches the real
                              // grid once data lands.
                              width: (constraints.maxWidth -
                                      spacing * (crossAxisCount - 1)) /
                                  crossAxisCount,
                              height: cellHeight,
                              child: ShimmerBox(
                                width: double.infinity,
                                height: cellHeight,
                                radius: 12,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                // Bottom padding matches the real grid so the
                // pull-to-refresh gesture doesn't shorten the
                // scrollable region mid-load.
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row of skeleton chips that mirrors the [CategorySelector] Large
/// category row: a row of equal-height rounded rects with the same gap
/// the real chips use. We don't bother with a sub-row skeleton because
/// the sub-row is hidden until the user picks a Large, so an empty
/// area there is the natural look.
class _ChipSkeletonRow extends StatelessWidget {
  @override
  // Block body on purpose — the inline comments explain why we vary
  // chip widths and why five is enough for the first paint. Collapsing
  // to a `=> Row(...)` expression body would silently drop them.
  // ignore: prefer_expression_function_bodies
  Widget build(BuildContext context) {
    // Use [context.responsive] so the same gap / chip height apply
    // that [CategorySelector] uses — keeps the skeleton and the real
    // row identical, so the swap-in doesn't shift vertically.
    final gap = context.responsive<double>(mobile: 8, tablet: 10, desktop: 12);
    final chipHeight = context.responsive<double>(mobile: 36, tablet: 40, desktop: 44);
    // Five chips roughly spans the typical phone width with one row
    // of the real selector — the user can immediately tell "this is
    // the filter bar" without us having to measure the viewport.
    const chipCount = 5;
    return Row(
      children: [
        for (var i = 0; i < chipCount; i++) ...[
          if (i > 0) SizedBox(width: gap),
          ShimmerBox(
            // Slightly varying widths per chip — a row of identically
            // wide pills looks more artificial than the natural
            // padding-driven widths the real chips get (variable
            // label lengths like "Phụ kiện" vs "Tất cả").
            width: i == 0 ? 64 : 56 + (i * 12) % 32,
            height: chipHeight,
            radius: 999,
          ),
        ],
      ],
    );
  }
}
