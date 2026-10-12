import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/executive_command_center_screen.dart';
import 'package:frontend/presentation/widgets/industrial_widgets.dart';

void main() {
  testWidgets('ExecutiveCommandCenterScreen renders Autonomous Operations Panel and 1-Click Demo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: ExecutiveCommandCenterScreen(
          onNavigate: (index, {targetMachine}) {},
        ),
      ),
    );
    await tester.pump();

    // Verify Title & Tag
    expect(find.text('Executive Factory Command Center'), findsOneWidget);
    expect(find.text('AUTONOMOUS FACTORY INTELLIGENCE'), findsOneWidget);

    // Verify Autonomous Panel & Dispatch Button
    expect(find.text('Autonomous Factory Agent Orchestrator'), findsOneWidget);
    expect(find.text('DISPATCH AUTONOMOUS PIPELINE'), findsOneWidget);

    // Verify Worker Status Pills
    expect(find.text('ORCHESTRATOR WORKER: '), findsOneWidget);
    expect(find.text('ANOMALY DETECTOR: '), findsOneWidget);
    expect(find.text('ACTIVE WORKFLOWS: '), findsOneWidget);
    expect(find.text('MANAGER APPROVALS: '), findsOneWidget);

    // Verify Direct Access bar
    expect(find.text('DIRECT ACCESS:'), findsOneWidget);
    expect(find.text('Incident Intelligence'), findsOneWidget);
    expect(find.text('Factory Digital Twin'), findsOneWidget);
    expect(find.text('Approval Center'), findsOneWidget);

    // Verify Metric Cards structure
    expect(find.byType(IndustrialMetricCard), findsWidgets);
  });
}
