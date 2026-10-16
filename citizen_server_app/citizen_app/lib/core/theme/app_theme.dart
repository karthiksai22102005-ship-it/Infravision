import 'package:flutter/material.dart';

class AppColors {
  static const blue = Color(0xFF1F5FE0);
  static const navy = Color(0xFF0B2A6B);
  static const bg = Color(0xFFF4F6FB);
  static const card = Colors.white;
  static const text = Color(0xFF14213D);
  static const muted = Color(0xFF6B7690);
  static const green = Color(0xFF2EAD66);
  static const amber = Color(0xFFF2A516);
  static const red = Color(0xFFE5484D);
  static const line = Color(0xFFE3E8F3);
}

Color statusColor(String s) => switch (s) {
      'resolved' => AppColors.green,
      'in_progress' => AppColors.blue,
      'under_review' => AppColors.amber,
      'assigned' => const Color(0xFF7C4DFF),
      _ => AppColors.muted,
    };

String statusLabel(String s) =>
    s.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

ThemeData buildTheme({bool dark = false}) {
  const darkBg = Color(0xFF101827);
  const darkCard = Color(0xFF182338);
  const darkText = Color(0xFFF3F6FC);
  const darkMuted = Color(0xFFABB7CB);
  const darkLine = Color(0xFF2A3952);
  final background = dark ? darkBg : AppColors.bg;
  final surface = dark ? darkCard : AppColors.card;
  final foreground = dark ? darkText : AppColors.text;
  final muted = dark ? darkMuted : AppColors.muted;
  final line = dark ? darkLine : AppColors.line;
  final brightness = dark ? Brightness.dark : Brightness.light;
  final base = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    brightness: brightness,
    primary: AppColors.blue,
    surface: surface,
    onPrimary: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: foreground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            color: foreground, fontSize: 18, fontWeight: FontWeight.w600)),
    cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: line))),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            disabledBackgroundColor: const Color(0xFF5B8DEF),
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            side: const BorderSide(color: AppColors.blue),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: line))),
    dividerColor: line,
    textTheme: ThemeData(brightness: brightness)
        .textTheme
        .apply(
          bodyColor: foreground,
          displayColor: foreground,
        )
        .copyWith(bodySmall: TextStyle(color: muted)),
  );
}
