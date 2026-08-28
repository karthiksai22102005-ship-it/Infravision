import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/app/app.dart';
import 'package:infravision/presentation/portals/citizen_portal.dart';
import 'package:infravision/presentation/portals/crew_portal.dart';
import 'package:infravision/presentation/portals/inspector_portal.dart';
import 'package:infravision/presentation/portals/portal_selector_screen.dart';
import 'package:infravision/presentation/portals/supervisor_portal.dart';
import 'package:infravision/repositories/app_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppStorage.instance.initialize();
  });

  group('Multi-User Role Portal System Tests', () {
    testWidgets('App root boots into PortalSelectorScreen', (tester) async {
      await tester.pumpWidget(const InfraVisionApp());
      await tester.pumpAndSettle();

      expect(find.byType(PortalSelectorScreen), findsOneWidget);
      expect(find.text('Select Your Operational Role Portal'), findsOneWidget);
      expect(find.text('Citizen Reporter Portal'), findsOneWidget);
      expect(find.text('Field Inspector Portal'), findsOneWidget);
      expect(find.text('Contractor Crew Portal'), findsOneWidget);
      expect(find.text('Municipal Supervisor Portal'), findsOneWidget);
    });

    testWidgets('CitizenPortal renders 4 bottom tabs and quick report form', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CitizenPortal(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Citizen Reporter Portal'), findsOneWidget);
      expect(find.text('Quick Report'), findsOneWidget);
      expect(find.text('My Reports'), findsOneWidget);
      expect(find.text('Nearby Issues'), findsOneWidget);
      expect(find.text('Community Hub'), findsOneWidget);

      // Verify the new intelligent Quick Report flow initial UI.
      expect(find.text('Report a Civil Infrastructure Defect'), findsOneWidget);
      expect(find.text('Start Camera'), findsOneWidget);
      expect(find.text('Upload Photos'), findsOneWidget);
      expect(find.text('Add Video'), findsOneWidget);
      expect(find.text('Analyze, Route & Submit Report'), findsOneWidget);

      // Each section still switches in place on the same bottom navigation.
      await tester.tap(find.text('My Reports'));
      await tester.pumpAndSettle();
      expect(find.text('My Reports & Real-Time Tracking'), findsOneWidget);

      await tester.tap(find.text('Nearby Issues'));
      await tester.pumpAndSettle();
      expect(find.text('Nearby Issues & Verification'), findsOneWidget);

      await tester.tap(find.text('Community Hub'));
      await tester.pumpAndSettle();
      expect(find.text('Community Infrastructure Hub'), findsOneWidget);
    });

    testWidgets('InspectorPortal renders live scanner, offline queue, and checklist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InspectorPortal(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Field Inspector Portal'), findsOneWidget);
      expect(find.text('Live CV Sweep'), findsOneWidget);
      expect(find.text('Batch Route'), findsOneWidget);
      expect(find.text('Offline Queue'), findsOneWidget);
      expect(find.text('Checklist'), findsOneWidget);

      expect(find.text('Capture & Log Defect'), findsOneWidget);
    });

    testWidgets('CrewPortal renders assigned work orders and action buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CrewPortal(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Contractor Crew Portal'), findsOneWidget);
      expect(find.text('View Before-Photo'), findsWidgets);
      expect(find.text('Mark Fixed'), findsWidgets);
    });

    testWidgets('SupervisorPortal wraps AppShell and renders Mission Control header', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: SupervisorPortal(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SupervisorPortal), findsOneWidget);
      expect(find.byTooltip('Switch Operational Portal'), findsOneWidget);
    });
  });
}
