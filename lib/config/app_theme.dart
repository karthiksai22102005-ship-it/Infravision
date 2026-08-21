import 'package:flutter/material.dart';

/// Central Design System & Color Palette for InfraVision Enterprise Command Center.
///
/// Designed with a Unified Dark Cyber-Enterprise aesthetic:
/// - Deep Slate & Pitch Dark canvas (`#0B1120`, `#0F172A`, `#131D31`)
/// - Sleek Dark Card surfaces (`#131D31`, `#1E293B`)
/// - Vibrant Indigo & Cyan primary accents (`#4F46E5`, `#06B6D4`)
/// - Emerald (`#10B981`) for verified/healthy states
/// - Amber (`#F59E0B`) for warnings & pending items
/// - Rose (`#EF4444`) for critical defects & SLAs
/// - Violet (`#8B5CF6`) for AI models & training
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Color Palette (Dark Enterprise Cyber Theme)
  // ---------------------------------------------------------------------------
  static const Color bgCanvas = Color(0xFF0B1120);
  static const Color bgSurface = Color(0xFF131D31);
  static const Color bgSurfaceSubtle = Color(0xFF1E293B);
  static const Color bgDark = Color(0xFF0B1120);
  static const Color bgDarkCard = Color(0xFF131D31);
  static const Color bgDarkSurface = Color(0xFF1E293B);

  static const Color primary = Color(0xFF6366F1); // Electric Indigo
  static const Color primaryHover = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF1E1B4B);

  static const Color accentBlue = Color(0xFF3B82F6); // Royal Blue
  static const Color accentBlueLight = Color(0xFF172554);

  static const Color success = Color(0xFF10B981); // Emerald
  static const Color successLight = Color(0xFF064E3B);
  static const Color successDark = Color(0xFF34D399);

  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningLight = Color(0xFF78350F);
  static const Color warningDark = Color(0xFFFBBF24);

  static const Color error = Color(0xFFEF4444); // Rose
  static const Color errorLight = Color(0xFF7F1D1D);
  static const Color errorDark = Color(0xFFF87171);

  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleLight = Color(0xFF2E1065);

  static const Color cyan = Color(0xFF06B6D4);
  static const Color cyanLight = Color(0xFF164E63);

  // Neutral text & border colors for Dark Theme
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color border = Color(0xFF1E293B);
  static const Color borderSubtle = Color(0xFF334155);
  static const Color divider = Color(0xFF1E293B);

  // ---------------------------------------------------------------------------
  // Box Shadows & Card Styles
  // ---------------------------------------------------------------------------
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  // ---------------------------------------------------------------------------
  // Responsive Breakpoints
  // ---------------------------------------------------------------------------
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 768;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= 768 && w < 1100;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1100;

  static bool isWidescreen(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1440;

  // ---------------------------------------------------------------------------
  // ThemeData Builder (Dark Enterprise Theme)
  // ---------------------------------------------------------------------------
  static ThemeData buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgCanvas,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: cyan,
        surface: bgSurface,
        error: error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderSubtle),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurfaceSubtle,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cyan, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
