import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/digital_twin_screen.dart';

void main() {
  testWidgets('DigitalTwinScreen loads with header, metrics, and command center layout', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: DigitalTwinScreen(),
      ),
    );
    await tester.pump();

    // Verify header title and simulated label
    expect(find.text('Factory Digital Twin Command Center'), findsOneWidget);
    expect(find.text('SIMULATED FACTORY DIGITAL TWIN'), findsOneWidget);
    expect(find.byType(DigitalTwinScreen), findsOneWidget);
  });
}
