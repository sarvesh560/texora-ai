import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/simulation_screen.dart';

void main() {
  testWidgets('SimulationScreen loads with controls and headers', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: SimulationScreen(),
      ),
    );
    await tester.pump();

    // Verify header and controls exist
    expect(find.text('Factory Simulation Engine'), findsOneWidget);
    expect(find.text('Step Tick'), findsOneWidget);
  });
}
