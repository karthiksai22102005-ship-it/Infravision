import 'package:flutter/material.dart';

import 'pothole_mobile/pothole_mobile_app.dart';

/// Separate Android entry point. Build this target to produce the lightweight
/// field-inspection APK without changing the laptop portal entry point.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PotholeMobileApp());
}
