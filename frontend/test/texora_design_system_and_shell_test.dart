import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/widgets/design_system/design_system.dart';
import 'package:frontend/presentation/screens/main_shell_screen.dart';

void main() {
  group('Texora Design System & Shared Components Tests', () {
    testWidgets('TexoraCard renders title, subtitle, and content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TexoraCard(
              title: 'Factory Telemetry Overview',
              subtitle: 'Sub-metered readings across lines',
              trailing: const Icon(Icons.bolt),
              child: const Text('Child Content Block'),
            ),
          ),
        ),
      );

      expect(find.text('Factory Telemetry Overview'), findsOneWidget);
      expect(find.text('Sub-metered readings across lines'), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(find.text('Child Content Block'), findsOneWidget);
    });

    testWidgets('TexoraKpiCard renders metric value and trend badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TexoraKpiCard(
              label: 'Production Today',
              value: '12,450 kg',
              subtitle: '+8% vs yesterday',
              isPositive: true,
            ),
          ),
        ),
      );

      expect(find.text('Production Today'), findsOneWidget);
      expect(find.text('12,450 kg'), findsOneWidget);
      expect(find.text('+8% vs yesterday'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('TexoraStatusBadge renders correct variants', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TexoraStatusBadge(label: 'Running', variant: TexoraBadgeVariant.running, showDot: true),
                TexoraStatusBadge(label: 'Attention', variant: TexoraBadgeVariant.attention),
                TexoraStatusBadge(label: 'Critical', variant: TexoraBadgeVariant.critical),
                TexoraStatusBadge(label: 'In Progress', variant: TexoraBadgeVariant.inProgress),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Attention'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
    });

    testWidgets('TexoraPageHeader renders title, status pill and profile dropdown', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TexoraPageHeader(
              title: 'Machines — All Departments',
              subtitle: '120 active machines',
              notificationCount: 5,
              statusPill: const Text('AI Running'),
            ),
          ),
        ),
      );

      expect(find.text('Machines — All Departments'), findsOneWidget);
      expect(find.text('• 120 active machines'), findsOneWidget);
      expect(find.text('AI Running'), findsOneWidget);
      expect(find.text('Factory Manager'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('TexoraDataTable renders columns and row data', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TexoraDataTable(
              columns: const [
                TexoraColumnDef(title: 'Machine'),
                TexoraColumnDef(title: 'Status'),
                TexoraColumnDef(title: 'Vibration'),
              ],
              rows: const [
                [Text('TX-101'), Text('Running'), Text('2.1 mm/s')],
                [Text('TX-102'), Text('Attention'), Text('8.2 mm/s')],
              ],
            ),
          ),
        ),
      );

      expect(find.text('MACHINE'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('VIBRATION'), findsOneWidget);
      expect(find.text('TX-101'), findsOneWidget);
      expect(find.text('TX-102'), findsOneWidget);
    });

    testWidgets('TexoraActionButton renders primary and outline buttons', (tester) async {
      bool primaryClicked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TexoraActionButton(
              label: 'Create Maintenance Ticket',
              variant: TexoraButtonVariant.primary,
              onPressed: () => primaryClicked = true,
            ),
          ),
        ),
      );

      expect(find.text('Create Maintenance Ticket'), findsOneWidget);
      await tester.tap(find.text('Create Maintenance Ticket'));
      expect(primaryClicked, isTrue);
    });

    testWidgets('TexoraStateViews render loading, empty, and error states', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const TexoraLoadingState(message: 'Loading telemetry stream...'),
                  const TexoraEmptyState(title: 'No Active Anomalies', subtitle: 'All machines nominal'),
                  TexoraErrorState(message: 'Connection timed out', onRetry: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Loading telemetry stream...'), findsOneWidget);
      expect(find.text('No Active Anomalies'), findsOneWidget);
      expect(find.text('All machines nominal'), findsOneWidget);
      expect(find.text('Connection timed out'), findsOneWidget);
      expect(find.text('Retry Connection'), findsOneWidget);
    });
  });

  group('MainShellScreen Responsive Viewport Tests (320px to 1920px)', () {
    for (final size in [
      const Size(1920, 1080),
      const Size(1440, 900),
      const Size(1280, 800),
      const Size(1024, 768),
      const Size(800, 600),
      const Size(480, 854),
      const Size(360, 640),
      const Size(320, 568),
    ]) {
      testWidgets('MainShellScreen renders at ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(const MaterialApp(home: MainShellScreen()));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(MainShellScreen), findsOneWidget);
      });
    }
  });
}
