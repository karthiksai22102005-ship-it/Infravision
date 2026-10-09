import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:infravision_camera/infravision_camera.dart';

import 'app/app.dart';
import 'mobile/ui/mobile_portal_app.dart';
import 'mobile/ui/portal_services.dart';
import 'repositories/app_storage.dart';

/// Entry point. Deliberately thin — all real setup lives in app/app.dart
/// and the individual service modules, per the Level 1 architecture rule
/// that main.dart must not contain the application itself.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android runs the offline-first Observation Portal. Desktop keeps the full
  // multi-role workstation below, so the laptop build is unaffected (§104/§105).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    runApp(const _MobilePortalBootstrap());
    return;
  }

  // Initialize the Windows webcam plugin (registers the frame event channel on Windows).
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    InfravisionCamera.initialize();
  }

  // Initialize local evidence vault and metadata repositories.
  await AppStorage.instance.initialize();

  runApp(const InfraVisionApp());
}

/// Boots the real service graph before showing the portal, and surfaces a
/// readable error instead of a blank screen if that ever fails.
class _MobilePortalBootstrap extends StatefulWidget {
  const _MobilePortalBootstrap();

  @override
  State<_MobilePortalBootstrap> createState() => _MobilePortalBootstrapState();
}

class _MobilePortalBootstrapState extends State<_MobilePortalBootstrap> {
  late final Future<PortalServices> _future = PortalServices.bootstrap();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PortalServices>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<PortalServices> snapshot) {
        if (snapshot.hasData) {
          return MobilePortalApp(services: snapshot.data!);
        }
        if (snapshot.hasError) {
          return _BootstrapFailure(error: snapshot.error!);
        }
        return const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'The Observation Portal could not start.\n\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
