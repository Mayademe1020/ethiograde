import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────
//  Design Tokens
// ─────────────────────────────────────────────

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double full = 999;
}

/// Theme-aware semantic colors. Migrate `AppTheme.*` usages in widgets to
/// `context.*` so they adapt to the active light/dark ColorScheme.
/// Only 1:1 semantic mappings are exposed here; brand-specific hues that have
/// no ColorScheme role (info blue, success green) keep their static constants.
extension AppThemeContext on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  Color get primaryGreen => _scheme.primary;
  Color get primaryYellow => _scheme.secondary;
  Color get primaryRed => _scheme.tertiary;
  Color get warmGray => _scheme.surfaceContainerHighest;
  Color get darkText => _scheme.onSurface;
  Color get lightText => _scheme.onSurfaceVariant;
  Color get cardBg => _scheme.surface;
  Color get scaffoldBg => Theme.of(this).scaffoldBackgroundColor;

  Color get warning => _scheme.secondary;
  Color get warningContainer => _scheme.secondaryContainer;
  Color get error => _scheme.error;
  Color get errorContainer => _scheme.errorContainer;
  Color get outlineLight => _scheme.outline;
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> card = [
    BoxShadow(
      color: const Color(0xFF0A1929).withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> elevated = [
    BoxShadow(
      color: const Color(0xFF0A1929).withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];
  static List<BoxShadow> fab = [
    BoxShadow(
      color: AppTheme.primary.withValues(alpha: 0.35),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}

// ─────────────────────────────────────────────
//  Semantic Colors (context-independent)
// ─────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  // ── Brand palette ──────────────────────────
  static const Color primary = Color(0xFF0B6E4F); // Deep teal-green
  static const Color primaryLight = Color(0xFF1A8A65); // Lighter for hover/fill
  static const Color primaryContainer = Color(0xFFDFF5EC);
  static const Color secondary = Color(0xFFF4A623); // Warm amber
  static const Color secondaryContainer = Color(0xFFFFF0D6);
  static const Color tertiary = Color(0xFFDA2A2A); // Alert red
  static const Color tertiaryContainer = Color(0xFFFFE8E8);

  // ── Semantic ───────────────────────────────
  static const Color success = Color(0xFF18A558);
  static const Color successContainer = Color(0xFFDCF5E8);
  static const Color warning = Color(0xFFF4A623);
  static const Color warningContainer = Color(0xFFFFF0D6);
  static const Color error = Color(0xFFDA2A2A);
  static const Color errorContainer = Color(0xFFFFE8E8);
  static const Color info = Color(0xFF1A6FD4);
  static const Color infoContainer = Color(0xFFDEEBFF);

  // ── Light neutral palette ──────────────────
  static const Color scaffoldLight = Color(0xFFF4F7F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF0F4F2);
  static const Color outlineLight = Color(0xFFDDE4E0);
  static const Color onSurfaceLight = Color(0xFF0D1C17);
  static const Color onSurfaceVariantLight = Color(0xFF4A5E56);

  // ── Dark neutral palette ───────────────────
  static const Color scaffoldDark = Color(0xFF0A1410);
  static const Color surfaceDark = Color(0xFF121F1A);
  static const Color surfaceVariantDark = Color(0xFF1C2B24);
  static const Color outlineDark = Color(0xFF2C3E35);
  static const Color onSurfaceDark = Color(0xFFE4EDE9);
  static const Color onSurfaceVariantDark = Color(0xFF8BA898);

  // ── Legacy aliases (used in existing widgets) ─
  static const Color primaryGreen = primary;
  static const Color primaryYellow = secondary;
  static const Color primaryRed = tertiary;
  static const Color deepBlue = info;
  static const Color warmGray = surfaceVariantLight;
  static const Color darkText = onSurfaceLight;
  static const Color lightText = onSurfaceVariantLight;
  static const Color cardBg = surfaceLight;
  static const Color scaffoldBg = scaffoldLight;

  // ─────────────────────────────────────────────
  //  Text Theme (Plus Jakarta Sans)
  // ─────────────────────────────────────────────

  static TextTheme _buildTextTheme(Color bodyColor, Color displayColor) {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: displayColor,
        height: 1.1,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: displayColor,
        height: 1.15,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: displayColor,
        height: 1.2,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: displayColor,
        height: 1.25,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: displayColor,
        height: 1.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: displayColor,
        height: 1.35,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        height: 1.4,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: bodyColor,
        height: 1.4,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        height: 1.5,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: bodyColor,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: bodyColor.withValues(alpha: 0.7),
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: bodyColor,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: bodyColor.withValues(alpha: 0.7),
        letterSpacing: 0.5,
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Light Theme
  // ─────────────────────────────────────────────

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: Color(0xFF00311F),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: Color(0xFF3E2300),
      tertiary: tertiary,
      onTertiary: Colors.white,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: Color(0xFF410002),
      error: error,
      onError: Colors.white,
      errorContainer: errorContainer,
      surface: surfaceLight,
      onSurface: onSurfaceLight,
      surfaceContainerHighest: surfaceVariantLight,
      onSurfaceVariant: onSurfaceVariantLight,
      outline: outlineLight,
      outlineVariant: Color(0xFFEAEFEC),
      shadow: Color(0xFF0A1929),
      scrim: Color(0xFF000000),
      inverseSurface: onSurfaceLight,
      onInverseSurface: surfaceLight,
      inversePrimary: primaryLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldLight,
      textTheme: _buildTextTheme(onSurfaceLight, onSurfaceLight),

      // ── AppBar ──────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLight,
        foregroundColor: onSurfaceLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: outlineLight,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurfaceLight,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        iconTheme: const IconThemeData(color: onSurfaceLight, size: 22),
        actionsIconTheme: const IconThemeData(
          color: onSurfaceVariantLight,
          size: 22,
        ),
      ),

      // ── Navigation Bar ──────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        indicatorColor: primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 22);
          }
          return const IconThemeData(color: onSurfaceVariantLight, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = GoogleFonts.plusJakartaSans(fontSize: 11);
          if (states.contains(WidgetState.selected)) {
            return base.copyWith(fontWeight: FontWeight.w700, color: primary);
          }
          return base.copyWith(
            fontWeight: FontWeight.w500,
            color: onSurfaceVariantLight,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
      ),

      // ── Cards ───────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: outlineLight),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Elevated Button ─────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      // ── Filled Button ───────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      // ── Outlined Button ─────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 1.5),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      // ── Text Button ─────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),

      // ── Input fields ────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariantLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: outlineLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: outlineLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariantLight,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariantLight.withValues(alpha: 0.6),
        ),
      ),

      // ── Chips ───────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariantLight,
        selectedColor: primaryContainer,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: const BorderSide(color: outlineLight),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      // ── FAB ─────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
      ),

      // ── Divider ─────────────────────────────
      dividerTheme: const DividerThemeData(
        color: outlineLight,
        thickness: 1,
        space: 1,
      ),

      // ── List Tiles ──────────────────────────
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        tileColor: Colors.transparent,
      ),

      // ── Bottom Sheet ─────────────────────────
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
        elevation: 8,
      ),

      // ── Dialog ──────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        elevation: 8,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurfaceLight,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariantLight,
          height: 1.5,
        ),
      ),

      // ── Snackbar ────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurfaceLight,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),

      // ── Switch / Checkbox / Radio ────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : onSurfaceVariantLight,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primaryContainer
              : surfaceVariantLight,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),

      // ── Progress ────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primaryContainer,
        circularTrackColor: primaryContainer,
      ),

      // ── Tab Bar ─────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: onSurfaceVariantLight,
        indicatorColor: primary,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: outlineLight,
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Dark Theme
  // ─────────────────────────────────────────────

  static ThemeData get darkTheme {
    const darkPrimary = Color(0xFF5ED4A0); // Lighter for dark surfaces
    const darkPrimaryContainer = Color(0xFF004D34);
    const darkSecondary = Color(0xFFFFB84D);
    const darkSecondaryContainer = Color(0xFF4A2D00);

    const colorScheme = ColorScheme.dark(
      primary: darkPrimary,
      onPrimary: Color(0xFF003824),
      primaryContainer: darkPrimaryContainer,
      onPrimaryContainer: Color(0xFFB7F5D8),
      secondary: darkSecondary,
      onSecondary: Color(0xFF3E2300),
      secondaryContainer: darkSecondaryContainer,
      onSecondaryContainer: Color(0xFFFFDDAD),
      tertiary: Color(0xFFFF8A8A),
      onTertiary: Color(0xFF690005),
      error: Color(0xFFFF8A8A),
      onError: Color(0xFF690005),
      surface: surfaceDark,
      onSurface: onSurfaceDark,
      surfaceContainerHighest: surfaceVariantDark,
      onSurfaceVariant: onSurfaceVariantDark,
      outline: outlineDark,
      outlineVariant: Color(0xFF1F2E27),
      shadow: Colors.black,
      inverseSurface: onSurfaceDark,
      onInverseSurface: surfaceDark,
      inversePrimary: primary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldDark,
      textTheme: _buildTextTheme(onSurfaceDark, onSurfaceDark),

      appBarTheme: AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: onSurfaceDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: outlineDark,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurfaceDark,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        iconTheme: const IconThemeData(color: onSurfaceDark, size: 22),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: darkPrimaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: darkPrimary, size: 22);
          }
          return const IconThemeData(color: onSurfaceVariantDark, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = GoogleFonts.plusJakartaSans(fontSize: 11);
          if (states.contains(WidgetState.selected)) {
            return base.copyWith(
              fontWeight: FontWeight.w700,
              color: darkPrimary,
            );
          }
          return base.copyWith(
            fontWeight: FontWeight.w500,
            color: onSurfaceVariantDark,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: outlineDark),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: const Color(0xFF003824),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: const Color(0xFF003824),
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          side: const BorderSide(color: darkPrimary, width: 1.5),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariantDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: outlineDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: outlineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: darkPrimary, width: 2),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariantDark,
        ),
        hintStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariantDark.withValues(alpha: 0.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariantDark,
        selectedColor: darkPrimaryContainer,
        labelStyle: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: onSurfaceDark,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: const BorderSide(color: outlineDark),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkPrimary,
        foregroundColor: Color(0xFF003824),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: outlineDark,
        thickness: 1,
        space: 1,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
        elevation: 8,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurfaceDark,
        ),
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: onSurfaceVariantDark,
          height: 1.5,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: onSurfaceDark,
        contentTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: surfaceDark,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: darkPrimary,
      ),
    );
  }
}
