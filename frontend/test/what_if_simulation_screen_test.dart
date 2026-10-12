import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/what_if_simulation_screen.dart';

void main() {
  testWidgets('WhatIfSimulationScreen loads with configuration panel, demo action buttons, and studio header', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: WhatIfSimulationScreen(),
      ),
    );
    await tester.pump();

    // Verify studio header and isolation badge
    expect(find.text('What-If Simulation Studio & AI Strategy Advisor'), findsOneWidget);
    expect(find.text('DETERMINISTIC SIMULATION ISOLATION GUARANTEED'), findsOneWidget);
    expect(find.text('SCENARIO CONFIGURATION'), findsOneWidget);
    expect(find.text('Demo A: Single Loom'), findsOneWidget);
    expect(find.text('Demo B: Weaving Cluster'), findsOneWidget);
    expect(find.text('Demo C: Spinning Shortage'), findsOneWidget);
    expect(find.byType(WhatIfSimulationScreen), findsOneWidget);
  });
}
