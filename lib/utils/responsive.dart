import 'package:flutter/material.dart';

/// Breakpoints for responsive design.
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;

  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}

/// Responsive builder that provides layout info based on screen width.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final Widget Function(BuildContext context) mobile;
  final Widget Function(BuildContext context)? tablet;
  final Widget Function(BuildContext context)? desktop;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= Breakpoints.desktop && desktop != null) {
      return desktop!(context);
    }
    if (width >= Breakpoints.mobile && tablet != null) {
      return tablet!(context);
    }
    return mobile(context);
  }
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

  /// Responsive card width for grids.
  double get cardWidth {
    if (isDesktop) return 280;
    if (isTablet) return 220;
    return double.infinity;
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
  double get productCardImageHeight {
    if (isDesktop) return 180;
    if (isTablet) return 150;
    return 120;
  }

  /// Responsive font size for product card name.
  double get productCardNameFontSize {
    if (isDesktop) return 15;
    if (isTablet) return 14;
    return 13;
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
    return const EdgeInsets.all(10);
  }

  /// Responsive button height for product card.
  double get productCardButtonHeight {
    if (isDesktop) return 36;
    if (isTablet) return 34;
    return 32;
  }

  /// Responsive admin grid columns for stat cards.
  int get adminGridColumns {
    if (isDesktop) return 4;
    if (isTablet) return 2;
    return 2;
  }

  /// Responsive dialog width.
  double get dialogWidth {
    if (isDesktop) return 600;
    if (isTablet) return 500;
    return double.infinity;
  }

  /// Whether to show a full navigation rail (desktop) vs compact (tablet).
  bool get useFullNavigationRail => screenWidth > 900;

  /// Responsive admin sidebar width.
  double get adminSidebarWidth {
    if (isDesktop) return 250;
    if (isTablet) return 200;
    return 0;
  }

  /// Whether the device orientation is portrait.
  bool get isPortrait => screenHeight > screenWidth;

  /// Whether the device orientation is landscape.
  bool get isLandscape => screenWidth > screenHeight;

  /// Responsive product detail image height.
  double get productDetailImageHeight => responsive<double>(
        mobile: 250,
        tablet: 350,
        desktop: 450,
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

/// Responsive SizedBox that adapts spacing based on screen size.
class ResponsiveSpace extends StatelessWidget {
  const ResponsiveSpace(
      {super.key, this.mobile = 8, this.tablet = 16, this.desktop = 24});

  final double mobile;
  final double tablet;
  final double desktop;

  @override
  Widget build(BuildContext context) {
    final w = context.screenWidth;
    double size;
    if (w >= Breakpoints.desktop) {
      size = desktop;
    } else if (w >= Breakpoints.mobile) {
      size = tablet;
    } else {
      size = mobile;
    }
    return SizedBox(height: size);
  }
}
