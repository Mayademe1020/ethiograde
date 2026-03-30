import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Ethiopian-inspired color palette
  static const Color primaryGreen = Color(0xFF1B7A43); // Ethiopian flag green
  static const Color primaryYellow = Color(0xFFFCC312); // Ethiopian flag yellow
  static const Color primaryRed = Color(0xFFDA121A);   // Ethiopian flag red
  static const Color deepBlue = Color(0xFF1A365D);
  static const Color warmGray = Color(0xFFF5F0EB);
  static const Color darkText = Color(0xFF1A202C);
  static const Color lightText = Color(0xFF6B7280);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color scaffoldBg = Color(0xFFF7FAFC);
  static const Color success = Color(0xFF38A169);
  static const Color warning = Color(0xFFECC94B);
  static const Color error = Color(0xFFE53E3E);
  static const Color info = Color(0xFF3182CE);

  static const ColorScheme _colorScheme = ColorScheme.light(
    primary: primaryGreen,
    secondary: primaryYellow,
    tertiary: primaryRed,
    surface: cardBg,
    background: scaffoldBg,
    error: error,
    onPrimary: Colors.white,
    onSecondary: darkText,
    onSurface: darkText,
    onBackground: darkText,
    onError: Colors.white,
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryGreen,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: primaryGreen, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryGreen.withOpacity(0.1),
          foregroundColor: primaryGreen,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        color: cardBg,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryGreen,
        unselectedItemColor: lightText,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scaffoldBg,
        selectedColor: primaryGreen.withOpacity(0.15),
        labelStyle: const TextStyle(fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primaryGreen,
        secondary: primaryYellow,
        tertiary: primaryRed,
        surface: const Color(0xFF1E293B),
        background: const Color(0xFF0F172A),
        error: error,
        onPrimary: Colors.white,
        onSecondary: darkText,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      textTheme: _darkTextTheme,
    );
  }

  static TextTheme get _textTheme => TextTheme(
    displayLarge: GoogleFonts.inter(
      fontSize: 32, fontWeight: FontWeight.bold, color: darkText,
    ),
    displayMedium: GoogleFonts.inter(
      fontSize: 28, fontWeight: FontWeight.bold, color: darkText,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: 24, fontWeight: FontWeight.w700, color: darkText,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 20, fontWeight: FontWeight.w600, color: darkText,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 18, fontWeight: FontWeight.w600, color: darkText,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 16, fontWeight: FontWeight.w500, color: darkText,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 16, fontWeight: FontWeight.normal, color: darkText,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.normal, color: darkText,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 12, fontWeight: FontWeight.normal, color: lightText,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 14, fontWeight: FontWeight.w600, color: darkText,
    ),
  );

  static TextTheme get _darkTextTheme => _textTheme.apply(
    bodyColor: Colors.white,
    displayColor: Colors.white,
  );
}
