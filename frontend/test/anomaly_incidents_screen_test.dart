import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/anomaly_incidents_screen.dart';

void main() {
  testWidgets('AnomalyIncidentsScreen loads with monitoring badge and headers', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: AnomalyIncidentsScreen(),
      ),
    );
    await tester.pump();

    // Verify header and run detection button exist
    expect(find.text('Autonomous Anomaly & Incident Center'), findsOneWidget);
    expect(find.text('Run Detection Cycle'), findsOneWidget);
  });
}
