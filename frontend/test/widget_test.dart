import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/widgets/app_sidebar.dart';
import 'package:frontend/presentation/screens/executive_command_center_screen.dart';

void main() {
  testWidgets('Texora AI App loads with sidebar and executive command center on desktop', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const TexoraApp());
    await tester.pump();

    // Verify Texora AI branding is rendered in sidebar and header
    expect(find.text('Texora AI'), findsWidgets);
    expect(find.text('Autonomous Factory Operations'), findsWidgets);

    // Verify AppSidebar is present
    expect(find.byType(AppSidebar), findsOneWidget);

    // Verify ExecutiveCommandCenterScreen is rendered at default index 0
    expect(find.byType(ExecutiveCommandCenterScreen), findsOneWidget);
    expect(find.text('Factory Overview'), findsOneWidget);

    // Verify the 9 Core Reference Navigation items are present
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('AI Agents'), findsWidgets);
    expect(find.text('Machines'), findsWidgets);
    expect(find.text('Production'), findsWidgets);
    expect(find.text('Quality'), findsWidgets);
    expect(find.text('Maintenance'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('Energy'), findsWidgets);
    expect(find.text('Reports'), findsWidgets);

    // Verify Advanced Operations navigation items are present
    expect(find.text('Factory Digital Twin'), findsWidgets);
    expect(find.text('Incident Intelligence'), findsWidgets);
    expect(find.text('Factory Recovery'), findsWidgets);
    expect(find.text('Approval Center'), findsWidgets);
    expect(find.text('Audit Trail'), findsWidgets);
    expect(find.text('System Diagnostics'), findsWidgets);

    // Verify Sandbox / Simulation UI section is completely removed
    expect(find.text('SANDBOX / SIMULATION'), findsNothing);
    expect(find.text('Telemetry Simulator'), findsNothing);
    expect(find.text('What-If Simulation'), findsNothing);
    expect(find.text('What-If Sandbox'), findsNothing);
  });
}
