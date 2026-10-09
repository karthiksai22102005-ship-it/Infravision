import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../presentation/portals/citizen_portal.dart';
import '../presentation/portals/portal_selector_screen.dart';

/// Root widget of InfraVision.
///
/// Laptop (Windows desktop): Preserves 100% of the Admin Workstation & Portal Selector.
/// Mobile (Android phone): Automatically routes to the Citizen User Portal without admin access.
class InfraVisionApp extends StatelessWidget {
  const InfraVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isMobile = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    return MaterialApp(
      title: isMobile ? 'InfraVision Citizen' : 'InfraVision AI Workstation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      home: isMobile ? const CitizenPortal() : const PortalSelectorScreen(),
    );
  }
}

