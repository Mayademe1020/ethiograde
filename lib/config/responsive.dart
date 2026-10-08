import 'package:flutter/material.dart';

/// Breakpoint-based responsive layout helpers.
///
/// Breakpoints:
/// - **compact** < 600px — phone (single column, bottom nav)
/// - **medium** 600–840px — small tablet (single column, bottom nav)
/// - **expanded** > 840px — large tablet / desktop (side nav, multi-column)
class ResponsiveLayout {
  ResponsiveLayout._();

  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 840;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactBreakpoint;

  static bool isMedium(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= compactBreakpoint && w < expandedBreakpoint;
  }

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= expandedBreakpoint;

  /// Whether to use NavigationRail instead of NavigationBar.
  static bool useSideNav(BuildContext context) => isExpanded(context);

  /// Horizontal padding that adapts to screen width.
  static double horizontalPadding(BuildContext context) {
    if (isExpanded(context)) return 32;
    if (isMedium(context)) return 24;
    return 20;
  }

  /// Max content width for centering on wide screens.
  static double? maxContentWidth(BuildContext context) {
    if (isExpanded(context)) return 720;
    return null;
  }

  /// Number of grid columns for card layouts.
  static int gridColumns(BuildContext context) {
    if (isExpanded(context)) return 3;
    if (isMedium(context)) return 2;
    return 1;
  }

  /// Class card width in the horizontal carousel.
  static double classCardWidth(BuildContext context) {
    if (isExpanded(context)) return 180;
    return 150;
  }

  /// Class carousel height.
  static double classCarouselHeight(BuildContext context) {
    if (isExpanded(context)) return 150;
    return 130;
  }
}
