import 'package:flutter/material.dart';

/// Breakpoints for responsive design.
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  /// Width threshold kept for callers that want a static fallback
  /// (e.g. tests that build MediaQuery without orientation). The
  /// product-detail screen itself uses the orientation-based
  /// getter [isProductDetailTwoCol] — see that getter for the
  /// rule.
  ///
  /// History: was 1024 dp when the rule was "width >= 1024 dp
  /// switches to the 2-col layout". Replaced with orientation
  /// because iPhone landscape (~932 dp wide) falls under 1024 dp
  /// but should still use the 2-col PC layout. Kept as a constant
  /// so tests + future code can pin to a number if they want.
  static const double productDetailTwoCol = 1024;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}

/// Extension on [BuildContext] for quick responsive checks.
extension ResponsiveContext on BuildContext {
  bool get isMobile => Breakpoints.isMobile(MediaQuery.of(this).size.width);
  bool get isTablet => Breakpoints.isTablet(MediaQuery.of(this).size.width);
  bool get isDesktop => Breakpoints.isDesktop(MediaQuery.of(this).size.width);

  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Returns appropriate padding based on screen size.
  EdgeInsets get responsivePadding {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) {
      return const EdgeInsets.symmetric(horizontal: 48, vertical: 16);
    }
    if (w >= Breakpoints.mobile) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  /// Returns the number of columns for a grid based on screen width.
  int get gridColumns {
    final w = screenWidth;
    if (w >= Breakpoints.desktop) return 4;
    if (w >= Breakpoints.tablet) return 3;
    if (w >= Breakpoints.mobile) return 2;
    return 2;
  }

  /// Responsive font size: scales with screen width.
  double responsiveFont(double base) {
    if (isDesktop) return base * 1.2;
    if (isTablet) return base * 1.1;
    return base;
  }

  /// Responsive width constraint for centering content on large screens.
  double get maxContentWidth {
    if (isDesktop) return 1200;
    if (isTablet) return 900;
    return double.infinity;
  }

  /// Whether to use a side navigation rail (desktop/tablet) vs bottom nav/drawer.
  bool get useNavigationRail => screenWidth > 600;

  /// Responsive horizontal padding for page content.
  double get horizontalPadding {
    if (isDesktop) return 48;
    if (isTablet) return 24;
    return 12;
  }

  /// Responsive grid spacing.
  double get gridSpacing {
    if (isDesktop) return 24;
    if (isTablet) return 16;
    return 8;
  }

  /// Responsive carousel height.
  double get carouselHeight {
    if (isDesktop) return 350;
    if (isTablet) return 250;
    return 180;
  }

  /// Responsive value selector: returns different values per breakpoint.
  T responsive<T>({required T mobile, T? tablet, T? desktop}) {
    if (isDesktop && desktop != null) return desktop;
    if (isTablet && tablet != null) return tablet;
    return mobile;
  }

  /// Responsive image height for product cards.
  ///
  /// Sized so the image takes roughly half of the card's vertical
  /// real estate on the narrowest supported phone (iPhone SE at
  /// 320×568), leaving room for the info block below (name +
  /// options row + categories row + price + button).
  ///
  /// History: this was 100/150/180 when the spec row was still in
  /// the card; once the spec row was removed and the image was
  /// switched to [BoxFit.contain] (so customers can see the full
  /// product, not a crop), the image grew to 140/210/250.
  double get productCardImageHeight {
    if (isDesktop) return 250;
    if (isTablet) return 210;
    return 140;
  }

  /// Responsive font size for product card name.
  double get productCardNameFontSize {
    if (isDesktop) return 15;
    if (isTablet) return 14;
    return 12;
  }

  /// Responsive font size for product card price.
  double get productCardPriceFontSize {
    if (isDesktop) return 16;
    if (isTablet) return 15;
    return 13;
  }

  /// Responsive padding for product card content.
  EdgeInsets get productCardPadding {
    if (isDesktop) return const EdgeInsets.all(14);
    if (isTablet) return const EdgeInsets.all(12);
    return const EdgeInsets.all(8);
  }

  /// Responsive button height for product card.
  ///
  /// Sized to fit the theme's `filledButtonTheme` padding (v:10) + 12-14pt
  /// label without vertical clipping.
  double get productCardButtonHeight {
    if (isDesktop) return 40;
    if (isTablet) return 38;
    return 36;
  }

  /// Responsive dialog width.
  ///
  /// On mobile this caps the dialog at 360 so it doesn't run edge-to-edge.
  /// Use [formDialogWidth] for forms that need a bit more room.
  double get dialogWidth {
    if (isDesktop) return 600;
    if (isTablet) return 500;
    return 360;
  }

  /// Slightly wider dialog width for forms (used by add/edit product dialogs).
  double get formDialogWidth {
    if (isDesktop) return 720;
    if (isTablet) return 600;
    return 400;
  }

  /// Whether to show a full navigation rail (desktop) vs compact (tablet).
  bool get useFullNavigationRail => screenWidth > 900;

  /// Responsive product detail image height.
  ///
  /// Bumped from 250/350/450 to 320/480/600 for the redesign — the
  /// inline gallery now fills more of the screen on tablet/desktop
  /// because the info column sits beside it instead of below it.
  /// Mobile stays at 320 dp so a portrait phone (~390 dp wide)
  /// still has room for the thumbnail strip + dot indicators
  /// without forcing the user to scroll past the gallery to see
  /// the price.
  double get productDetailImageHeight => responsive<double>(
        mobile: 320,
        tablet: 480,
        desktop: 600,
      );

  /// True when the screen is wide enough for the product-detail
  /// 2-column layout (gallery left, info right). Threshold is
  /// [Breakpoints.mobile] (600 dp) — used by the home grid + admin
  /// rail for the "tablet-or-wider" decision. The product-detail
  /// screen itself uses [isProductDetailTwoCol] (≥1024 dp) instead,
  /// because we want iPad portrait (768 dp) to stay mobile-style
  /// while iPad landscape (1024 dp) gets the 2-column layout.
  bool get isTabletOrUp => screenWidth >= Breakpoints.mobile;

  /// True when the product-detail screen should render the
  /// 2-column Row (gallery on the left, info on the right) with
  /// the thumbnail strip + description + specs + buy CTA rendered
  /// below the row in the main flow.
  ///
  /// Rule: **orientation-based** — true when the device is in
  /// landscape (`MediaQuery.of(context).orientation ==
  /// Orientation.landscape`), false in portrait. This covers:
  ///   * PC / laptop (landscape) → 2-col
  ///   * iPad landscape (1024×768) → 2-col
  ///   * iPad split-view landscape → 2-col
  ///   * iPhone landscape (~932×430) → 2-col
  ///   * iPad portrait (768×1024) → single col (mobile)
  ///   * iPhone portrait (~390×844) → single col (mobile)
  ///
  /// History: was width-based with a 1024 dp threshold. Replaced
  /// because iPhone landscape (~932 dp wide) falls under 1024 dp
  /// but should use the 2-col layout — and orientation is the
  /// intent: "anything wider than tall uses the desktop layout".
  bool get isProductDetailTwoCol =>
      MediaQuery.of(this).orientation == Orientation.landscape;

  /// Responsive cell height for the product grid in dp. Used as the
  /// `mainAxisExtent` of the [SliverGridDelegate] so the cell
  /// height is *exactly* (image + info content) for the worst-case
  /// product on each breakpoint — no blank strip below the button.
  ///
  /// We picked `mainAxisExtent` over `childAspectRatio` because
  /// the card's intrinsic height is dominated by the image (140 /
  /// 210 / 250 dp) plus ~170 / ~190 / ~205 dp of info content. The
  /// cell width depends on the viewport (and orientation), so an
  /// aspect ratio would have to track every (width × breakpoint)
  /// combination separately — mainAxisExtent just expresses the
  /// target height directly.
  ///
  /// Derivation (mobile / tablet / desktop):
  ///   image height:        140 / 210 / 250 dp
  ///   info (worst case):
  ///     name (2 lines):    ~31 / ~36 / ~39 dp
  ///     + 6 gap + ~22 options + 6 + ~20 categories
  ///     + 8 + ~24 price + 8 + 36/38/40 button
  ///     + 16 / 24 / 28 vertical padding
  ///   total ≈ 311 / 398 / 455 dp
  ///
  /// Products missing options/categories use the same-size
  /// placeholder [SizedBox] in [ProductCard] so the price+button
  /// baseline matches cards with all fields — and because every
  /// card sits inside the same cell, no card is visibly shorter
  /// than another.
  double get productCardHeight => responsive<double>(
        mobile: 311,
        tablet: 398,
        desktop: 455,
      );

  /// Whether to show a bottom navigation bar (mobile) vs side rail.
  bool get showBottomNav => isMobile;

  /// Responsive admin rail width.
  double get adminRailWidth => responsive<double>(
        mobile: 200,
        tablet: 220,
        desktop: 260,
      );

  /// Responsive grid cross-axis count for admin stats.
  int get adminStatColumns => responsive<int>(
        mobile: 2,
        tablet: 2,
        desktop: 4,
      );
}
