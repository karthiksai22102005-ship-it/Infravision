import 'package:flutter/material.dart';
import 'package:infravision_camera/infravision_camera.dart';

import 'app/app.dart';
import 'repositories/app_storage.dart';

/// Entry point. Deliberately thin — all real setup lives in app/app.dart
/// and the individual service modules, per the Level 1 architecture rule
/// that main.dart must not contain the application itself.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the Windows webcam plugin (registers the frame event channel).
  InfravisionCamera.initialize();

  // Initialize local evidence vault and metadata repositories.
  await AppStorage.instance.initialize();

  runApp(const InfraVisionApp());
}