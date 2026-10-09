import 'package:flutter_test/flutter_test.dart';
import 'package:infravision/app/app.dart';

void main() {
  testWidgets('InfraVision smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const InfraVisionApp());
    expect(find.byType(InfraVisionApp), findsOneWidget);
  });
}
