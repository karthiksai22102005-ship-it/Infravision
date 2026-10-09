import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/mobile/data/evidence_store.dart';
import 'package:infravision/mobile/services/mobile_camera_service.dart';
import 'package:infravision/mobile/ui/capture_screen.dart';
import 'package:infravision/mobile/ui/mobile_portal_app.dart';
import 'package:infravision/mobile/ui/portal_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke tests for the portal shell: five destinations, an honest offline
/// banner and a capture screen that refuses to work without a position.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory vaultRoot;
  late PortalServices services;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    vaultRoot = await Directory.systemTemp.createTemp('portal_ui');
    EvidenceStore.rootDirectoryOverride = vaultRoot;
    // path_provider has no platform implementation in tests, so point the
    // bootstrap at the same temporary vault instead of the system temp dir.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => vaultRoot.path,
    );
    services = await PortalServices.bootstrap();
  });

  tearDown(() async {
    EvidenceStore.rootDirectoryOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      await vaultRoot.delete(recursive: true);
    } catch (_) {
      // Nothing left to remove.
    }
  });

  /// Unmounts the tree before the services are torn down, so no widget keeps
  /// listening to a disposed notifier.
  Future<void> closePortal(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    services.shutdown();
  }

  testWidgets('shell shows the five portal destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MobilePortalApp(services: services));
    await tester.pump();

    expect(find.text('Observation Portal'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('Capture'), findsWidgets);
    expect(find.text('Sync'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('New pothole report'), findsOneWidget);
    await closePortal(tester);
  });

  testWidgets('no backend configured means an honest banner, not a fake sync', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MobilePortalApp(services: services));
    await tester.pump();

    expect(find.textContaining('Offline'), findsWidgets);
    expect(services.repository.backendConfigured, isFalse);
    expect(services.repository.pendingCount, 0);
    await closePortal(tester);
  });

  testWidgets('capture screen demands a real position before evidence', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MobilePortalApp(services: services));
    await tester.pump();
    await tester.tap(find.text('Capture'));
    await tester.pump();

    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Get location'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Submit report'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CaptureScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Submit report'), findsOneWidget);
    await closePortal(tester);
  });

  testWidgets('sync tab lists a real, empty queue honestly', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MobilePortalApp(services: services));
    await tester.pump();
    await tester.tap(find.text('Sync'));
    await tester.pump();

    expect(find.text('Queue (0)'), findsOneWidget);
    expect(
      find.textContaining('Nothing is waiting'),
      findsOneWidget,
    );
    await closePortal(tester);
  });

  // Regression: a failing geolocator call used to leave _busyLocation latched,
  // which permanently disabled "Get location" with no way to recover.
  testWidgets('a failed location request re-enables the GPS button', (
    WidgetTester tester,
  ) async {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.io/geolocator'),
      (MethodCall call) async => throw PlatformException(code: 'DENIED'),
    );
    addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('flutter.io/geolocator'),
          null,
        ));

    await tester.pumpWidget(MobilePortalApp(services: services));
    await tester.pump();
    await tester.tap(find.text('Capture'));
    await tester.pump();

    // FilledButton.icon lays the label out in a Row, so match on the button
    // that owns the onPressed callback for this action.
    final Finder gps = find.ancestor(
      of: find.text('Get location'),
      matching: find.byType(FilledButton),
    );
    expect(gps, findsOneWidget);

    await tester.tap(gps);
    await tester.pumpAndSettle();

    // The button must still be tappable afterwards — not latched disabled.
    final FilledButton button = tester.widget<FilledButton>(gps);
    expect(button.onPressed, isNotNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await closePortal(tester);
  });

  // Regression: leaving the Capture tab must release the camera singleton,
  // otherwise the preview keeps running behind the other tabs and drains the
  // battery.
  testWidgets('leaving the capture tab stops the camera singleton', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MobilePortalApp(services: services));
    await tester.pump();

    await tester.tap(find.text('Capture'));
    await tester.pump();
    await tester.tap(find.text('Home'));
    await tester.pump();

    expect(MobileCameraService.instance.isInitialized, isFalse);
    await closePortal(tester);
  });
}
