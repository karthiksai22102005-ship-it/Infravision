import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../presentation/shell/app_shell.dart';

/// Root widget of InfraVision Enterprise Workstation.
class InfraVisionApp extends StatelessWidget {
  const InfraVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InfraVision AI Workstation',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      home: const AppShell(),
    );
  }
}

