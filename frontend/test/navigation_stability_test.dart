import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/screens/main_shell_screen.dart';
import 'package:frontend/presentation/screens/executive_command_center_screen.dart';
import 'package:frontend/presentation/screens/machine_health_agent_screen.dart';
import 'package:frontend/presentation/screens/ai_agent_operations_screen.dart';
import 'package:frontend/presentation/screens/quality_monitoring_screen.dart';
import 'package:frontend/presentation/screens/energy_management_screen.dart';
import 'package:frontend/presentation/screens/reports_analytics_screen.dart';

void main() {
  group('Navigation Stability Regression Tests (No Automatic Navigation)', () {
    testWidgets('1. Selected screen remains unchanged during periodic data updates and silent refreshes', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Navigate manually to Machine Monitoring
      final machinesNav = find.text('Machine Monitoring');
      expect(machinesNav, findsWidgets);
      await tester.tap(machinesNav.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify currently on Machines
      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);

      // Simulate passage of time and periodic timers (10s, 15s)
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 15));

      // Assert that selected screen is STILL MachineHealthAgentScreen and NOT reset to 0
      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);
    });

    testWidgets('2. Incoming AI incidents or background events do NOT trigger navigation', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Navigate to AI Agents
      final aiAgentsNav = find.text('AI Agents');
      expect(aiAgentsNav, findsWidgets);
      await tester.tap(aiAgentsNav.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);

      // Pump through multi-second background polling cycles where incident data arrives
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 10));

      // Assert that screen is still AI Agents, no dialogs or incident pages forced open
      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('3. Widget rebuilds and setState do not change the selected screen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Navigate to Machine Monitoring
      await tester.tap(find.text('Machine Monitoring').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);

      // Force widget tree rebuild
      final element = tester.element(find.byType(MainShellScreen));
      element.markNeedsBuild();
      await tester.pump();

      // Still on Machines screen
      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);
    });

    testWidgets('4. Sidebar clicks navigate correctly to explicit user destinations', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Initially on Dashboard
      expect(find.byType(ExecutiveCommandCenterScreen), findsOneWidget);

      // Click AI Agents
      await tester.tap(find.text('AI Agents').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);

      // Click Machine Monitoring
      await tester.tap(find.text('Machine Monitoring').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);

      // Click Dashboard again
      await tester.tap(find.text('Dashboard').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ExecutiveCommandCenterScreen), findsOneWidget);
    });

    testWidgets('5. Resizing the viewport does not switch pages', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // User selects AI Agents
      await tester.tap(find.text('AI Agents').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);

      // Resize to Tablet (800x600)
      tester.view.physicalSize = const Size(800, 600);
      await tester.pump();
      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);

      // Resize to Mobile (360x640)
      tester.view.physicalSize = const Size(360, 640);
      await tester.pump();
      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);

      // Resize back to Desktop (1440x900)
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pump();
      expect(find.byType(AiAgentOperationsScreen), findsOneWidget);
    });

    testWidgets('6. User-initiated AI pipeline dispatch on Dashboard does NOT automatically navigate away from Dashboard', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      expect(find.byType(ExecutiveCommandCenterScreen), findsOneWidget);

      // Locate dispatch button and trigger it
      final dispatchBtn = find.text('DISPATCH AUTONOMOUS PIPELINE');
      if (dispatchBtn.evaluate().isNotEmpty) {
        await tester.tap(dispatchBtn.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Allow background async tasks to tick
      await tester.pump(const Duration(seconds: 2));

      // Must remain on ExecutiveCommandCenterScreen (Dashboard)
      expect(find.byType(ExecutiveCommandCenterScreen), findsOneWidget);
    });

    testWidgets('7. Telemetry polling pulses on Machines screen NEVER switch screens or force modals open', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Navigate to Machine Monitoring
      await tester.tap(find.text('Machine Monitoring').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);

      // Multiple background polling intervals
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 4));
      }

      // Assert still strictly on MachineHealthAgentScreen
      expect(find.byType(MachineHealthAgentScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('8. Operational screens remain strictly active and on case detail during continuous background polling', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Navigate to Quality
      await tester.tap(find.text('Quality').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QualityMonitoringScreen), findsOneWidget);

      // Simulate 12 seconds of background telemetry
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      expect(find.byType(QualityMonitoringScreen), findsOneWidget);

      // Navigate to Energy
      await tester.tap(find.text('Energy').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(EnergyManagementScreen), findsOneWidget);

      // Simulate background polling
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(EnergyManagementScreen), findsOneWidget);

      // Navigate to Reports & Analytics
      await tester.tap(find.text('Reports & Analytics').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ReportsAnalyticsScreen), findsOneWidget);

      // Simulate background polling
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(ReportsAnalyticsScreen), findsOneWidget);
    });
  });
}
