import 'package:flutter/material.dart';

import 'portal_services.dart';
import 'portal_shell.dart';

/// Dark, dense, field-work oriented theme (§52).
ThemeData buildPortalTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF43E9B2),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0B0F14),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    cardTheme: CardThemeData(
      color: const Color(0xFF141A21),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A222B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF10161D),
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelTextStyle: const WidgetStatePropertyAll<TextStyle?>(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Root widget of the Android Observation Portal.
class MobilePortalApp extends StatelessWidget {
  const MobilePortalApp({super.key, required this.services});

  final PortalServices services;

  @override
  Widget build(BuildContext context) {
    return PortalScope(
      services: services,
      child: MaterialApp(
        title: 'Observation Portal',
        debugShowCheckedModeBanner: false,
        theme: buildPortalTheme(),
        home: const PortalShell(),
      ),
    );
  }
}
