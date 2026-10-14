import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/widgets/department_status_card.dart';
import 'package:frontend/presentation/screens/executive_command_center_screen.dart';

void main() {
  group('DepartmentStatusCard Widget Tests', () {
    testWidgets('renders properly with standard desktop width (300px) and active incidents', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: DepartmentStatusCard(
                  departmentCode: 'WEV',
                  departmentName: 'Weaving Shed',
                  floorLocation: 'Bay 2 — High Speed Looms',
                  totalMachines: 6,
                  stateCounts: const {
                    'RUNNING': 4,
                    'WARNING': 1,
                    'CRITICAL': 1,
                    'UNDER_MAINTENANCE': 0,
                    'UNKNOWN': 0,
                  },
                  ratedCapacity: 850.0,
                  unit: 'meters/h',
                  activeIncidentsCount: 2,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('WEV'), findsOneWidget);
      expect(find.text('Weaving Shed'), findsOneWidget);
      expect(find.text('Bay 2 — High Speed Looms'), findsOneWidget);
      expect(find.text('2 Incidents'), findsOneWidget);
      expect(find.text('850.0 meters/h'), findsOneWidget);
      expect(find.text('6 Units'), findsOneWidget);
      expect(find.text('4 Running'), findsOneWidget);
      expect(find.text('1 Warning'), findsOneWidget);
      expect(find.text('1 Critical'), findsOneWidget);
    });

    testWidgets('renders without RenderFlex overflow under narrow width (160px) with 1 incident', (WidgetTester tester) async {
      // 160px card was previously triggering: A RenderFlex overflowed by 18 pixels on the right
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 160,
                child: DepartmentStatusCard(
                  departmentCode: 'WEV',
                  departmentName: 'Weaving Shed',
                  floorLocation: 'Bay 2 — High Speed Looms',
                  totalMachines: 5,
                  stateCounts: const {
                    'RUNNING': 4,
                    'WARNING': 0,
                    'CRITICAL': 1,
                    'UNDER_MAINTENANCE': 0,
                    'UNKNOWN': 0,
                  },
                  ratedCapacity: 850.0,
                  unit: 'meters/h',
                  activeIncidentsCount: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Crucial: No RenderFlex overflow exception
      expect(tester.takeException(), isNull);
      expect(find.text('WEV'), findsOneWidget);
      expect(find.text('1 Incident'), findsOneWidget);
      expect(find.text('850.0 meters/h'), findsOneWidget);
      expect(find.text('5 Units'), findsOneWidget);
    });

    testWidgets('renders without overflow under tight width (140px) with long department name and incidents', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 140,
                child: DepartmentStatusCard(
                  departmentCode: 'FIN',
                  departmentName: 'Finishing & Inspection',
                  floorLocation: 'Bay 5 — Stenter & Pack',
                  totalMachines: 4,
                  stateCounts: const {
                    'RUNNING': 3,
                    'WARNING': 1,
                    'CRITICAL': 0,
                    'UNDER_MAINTENANCE': 0,
                    'UNKNOWN': 0,
                  },
                  ratedCapacity: 600.0,
                  unit: 'meters/h',
                  activeIncidentsCount: 3,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('FIN'), findsOneWidget);
      expect(find.text('3 Incidents'), findsOneWidget);
    });

    testWidgets('renders all 5 departments without overflow', (WidgetTester tester) async {
      final departments = [
        {'code': 'SPN', 'name': 'Spinning Department', 'loc': 'Bay 1 — Ring Spinning Mill', 'unit': 'kg/h'},
        {'code': 'WEV', 'name': 'Weaving Shed', 'loc': 'Bay 2 — High Speed Looms', 'unit': 'meters/h'},
        {'code': 'KNT', 'name': 'Knitting Division', 'loc': 'Bay 3 — Circular Knitting', 'unit': 'kg/h'},
        {'code': 'DYE', 'name': 'Dyeing & Chemical', 'loc': 'Bay 4 — Soft Flow Vessels', 'unit': 'kg/h'},
        {'code': 'FIN', 'name': 'Finishing & Inspection', 'loc': 'Bay 5 — Stenter & Pack', 'unit': 'meters/h'},
      ];

      for (final dept in departments) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 155, // Constrained width that previously broke Row at line 63
                  child: DepartmentStatusCard(
                    departmentCode: dept['code']!,
                    departmentName: dept['name']!,
                    floorLocation: dept['loc']!,
                    totalMachines: 5,
                    stateCounts: const {
                      'RUNNING': 3,
                      'WARNING': 1,
                      'CRITICAL': 1,
                    },
                    ratedCapacity: 1000.0,
                    unit: dept['unit']!,
                    activeIncidentsCount: 1,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'Department ${dept['code']} threw an overflow exception');
        expect(find.text(dept['code']!), findsOneWidget);
      }
    });

    testWidgets('ExecutiveCommandCenterScreen renders department section responsively at 800px width', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
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

      expect(tester.takeException(), isNull);
      expect(find.byType(DepartmentStatusCard), findsNWidgets(5));
      expect(find.text('SPN'), findsOneWidget);
      expect(find.text('WEV'), findsOneWidget);
      expect(find.text('KNT'), findsOneWidget);
      expect(find.text('DYE'), findsOneWidget);
      expect(find.text('FIN'), findsOneWidget);
    });

    testWidgets('ExecutiveCommandCenterScreen renders department section responsively at 1440px width', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 1600);
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

      expect(tester.takeException(), isNull);
      expect(find.byType(DepartmentStatusCard), findsNWidgets(5));
    });

    testWidgets('ExecutiveCommandCenterScreen renders department section responsively at 500px narrow width', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 2400);
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

      expect(tester.takeException(), isNull);
      expect(find.byType(DepartmentStatusCard), findsNWidgets(5));
    });
  });
}
