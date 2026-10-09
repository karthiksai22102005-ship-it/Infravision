import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mobile/ui/mobile_portal_app.dart';
import 'mobile/ui/portal_services.dart';

/// Entry point of the offline-first Observation Portal.
///
/// Services are bootstrapped before the first frame so the UI never renders a
/// half-wired state; a bootstrap failure is shown honestly instead of a blank
/// screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  PortalServices services;
  try {
    services = await PortalServices.bootstrap();
  } catch (error) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'The portal could not start:\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  unawaited(services.refreshStatus());
  runApp(MobilePortalApp(services: services));
}
