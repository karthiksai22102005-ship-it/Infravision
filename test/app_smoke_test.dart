import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/app/app.dart';

void main() {
  testWidgets('InfraVisionApp builds and shows the app title', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const InfraVisionApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('InfraVision'), findsWidgets);
  });

  testWidgets('App theme is modern enterprise theme', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const InfraVisionApp());
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
  });
}