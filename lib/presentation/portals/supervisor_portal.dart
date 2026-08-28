import 'package:flutter/material.dart';
import '../shell/app_shell.dart';

class SupervisorPortal extends StatelessWidget {
  const SupervisorPortal({super.key});

  @override
  Widget build(BuildContext context) {
    // Simply render the core supervisor dashboard control center
    return const AppShell();
  }
}
