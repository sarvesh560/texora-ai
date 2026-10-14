import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/digital_twin_models.dart';
import 'package:frontend/presentation/screens/digital_twin_screen.dart';

DigitalTwinSnapshotModel _buildMockSnapshot({
  List<Map<String, dynamic>>? customMachines,
}) {
  final defaultMachines = [
    {
      'id': 1,
      'code': 'SPN-CRD-01',
      'name': 'Trutzschler TC 19i Carding Machine #1',
      'machine_type_name': 'Carding Machine',
      'category': 'SPINNING',
      'department_code': 'SPN',
      'department_name': 'Spinning Department',
      'floor_location': 'Bay A-1',
      'raw_status': 'OPERATIONAL',
      'twin_presentation_state': 'RUNNING',
      'state_reason': 'Nominal operation within baseline envelopes',
      'health_score': 98.0,
      'rated_capacity_units_per_hour': 280.0,
      'rated_speed_rpm': 1200,
      'latest_telemetry': {
        'temperature_c': 58.4,
        'vibration_mms': 1.8,
        'speed_rpm': 1195,
        'power_kw': 32.5,
        'utilization_pct': 94.2,
        'timestamp': '2026-10-12T11:00:00Z',
      },
      'operating_limits': {
        'max_temp_c': 85.0,
        'warning_temp_c': 75.0,
        'max_vibration_mms': 4.5,
        'warning_vibration_mms': 3.5,
      },
      'active_incidents': [],
      'active_tickets': [],
      'compatible_alternates': ['SPN-CRD-02'],
    },
    {
      'id': 2,
      'code': 'WEV-RAP-01-SP',
      'name': 'Picanol OmniPlus-i High Speed Rapier Loom #1',
      'machine_type_name': 'Rapier Loom',
      'category': 'WEAVING',
      'department_code': 'WEV',
      'department_name': 'Weaving Shed Sector A',
      'floor_location': 'Bay W-04',
      'raw_status': 'WARNING',
      'twin_presentation_state': 'UNDER_MAINTENANCE',
      'state_reason': 'Active Work Order WO-2026-0042 in execution',
      'health_score': 62.5,
      'rated_capacity_units_per_hour': 75.0,
      'rated_speed_rpm': 650,
      'latest_telemetry': {
        'temperature_c': 82.1,
        'vibration_mms': 4.6,
        'speed_rpm': 610,
        'power_kw': 18.2,
        'utilization_pct': 88.0,
        'timestamp': '2026-10-12T11:00:00Z',
      },
      'operating_limits': {
        'max_temp_c': 80.0,
        'warning_temp_c': 70.0,
        'max_vibration_mms': 4.0,
        'warning_vibration_mms': 3.0,
      },
      'active_incidents': [],
      'active_tickets': [42],
      'compatible_alternates': ['WEV-RAP-02'],
    },
    {
      'id': 3,
      'code': 'DYE-JET-01',
      'name': 'Fong Supreme High-Temp Dyeing Vessel #1',
      'machine_type_name': 'Dyeing Vessel',
      'category': 'DYEING',
      'department_code': 'DYE',
      'department_name': 'Dyeing & Wet Processing',
      'floor_location': 'Wet Floor B',
      'raw_status': 'STOPPED',
      'twin_presentation_state': 'CRITICAL',
      'state_reason': 'Exceeded thermal threshold (94.2°C > 85.0°C)',
      'health_score': 38.0,
      'rated_capacity_units_per_hour': 120.0,
      'rated_speed_rpm': 400,
      'latest_telemetry': {
        'temperature_c': 94.2,
        'vibration_mms': 5.8,
        'speed_rpm': 0,
        'power_kw': 4.1,
        'utilization_pct': 0.0,
        'timestamp': '2026-10-12T11:00:00Z',
      },
      'operating_limits': {
        'max_temp_c': 85.0,
        'warning_temp_c': 75.0,
        'max_vibration_mms': 3.0,
        'warning_vibration_mms': 2.0,
      },
      'active_incidents': [12],
      'active_tickets': [],
      'compatible_alternates': ['DYE-JET-02'],
    },
  ];

  return DigitalTwinSnapshotModel.fromJson({
    'snapshot_id': 'SNAP-TEST-2026',
    'factory_code': 'FAC-01',
    'captured_at': DateTime.now().toIso8601String(),
    'total_machines': 25,
    'operational_summary': {
      'total_machines': 25,
      'state_distribution': {
        'RUNNING': 18,
        'WARNING': 4,
        'CRITICAL': 1,
        'UNDER_MAINTENANCE': 2,
        'UNKNOWN': 0,
      },
    },
    'machine_states': customMachines ?? defaultMachines,
  });
}

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

    expect(find.text('Factory Digital Twin Command Center'), findsOneWidget);
    expect(find.text('SIMULATED FACTORY DIGITAL TWIN'), findsOneWidget);
    expect(find.byType(DigitalTwinScreen), findsOneWidget);
  });

  testWidgets('Regression: GridView at 1280px renders machine tiles without RenderFlex overflow (line 615 fix)', (WidgetTester tester) async {
    // 1280x800 resolution with GridView mode reproduces the 202.4px tile width constraint
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final snapshot = _buildMockSnapshot();

    await tester.pumpWidget(
      MaterialApp(
        home: DigitalTwinScreen(
          initialSnapshot: snapshot,
          initialViewMode: DigitalTwinViewMode.gridView,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial layout has zero RenderFlex overflow exceptions
    expect(tester.takeException(), isNull);

    // Verify machine codes render
    expect(find.text('SPN-CRD-01'), findsOneWidget);
    expect(find.text('WEV-RAP-01-SP'), findsOneWidget);
    expect(find.text('DYE-JET-01'), findsOneWidget);

    // Verify state labels render
    expect(find.text('RUNNING'), findsWidgets);
    expect(find.text('UNDER_MAINTENANCE'), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);

    // Click on WEV-RAP-01-SP to open the 380px inspector panel, shrinking the grid further
    await tester.tap(find.text('WEV-RAP-01-SP'));
    await tester.pumpAndSettle();

    // Verify inspector opened
    expect(find.text('TWIN PRESENTATION STATE: UNDER_MAINTENANCE'), findsOneWidget);
    expect(find.text('OPERATING THRESHOLD LIMITS'), findsOneWidget);

    // Verify no RenderFlex overflow exceptions occurred
    expect(tester.takeException(), isNull);
  });

  testWidgets('Responsive layouts render across 1920px, 1440px, 1280px, 1024px, and 800px viewports without overflow', (WidgetTester tester) async {
    final viewports = [
      const Size(1920, 1080),
      const Size(1440, 900),
      const Size(1280, 800),
      const Size(1024, 768),
      const Size(800, 600),
    ];

    final snapshot = _buildMockSnapshot();

    for (final size in viewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          home: DigitalTwinScreen(
            initialSnapshot: snapshot,
            initialViewMode: DigitalTwinViewMode.gridView,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No overflow exceptions on any viewport
      expect(tester.takeException(), isNull, reason: 'Failed at viewport size $size');
    }

    tester.view.resetPhysicalSize();
  });

  testWidgets('DigitalTwinScreen handles extreme machine codes, abnormal telemetry, and long names gracefully', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final extremeMachines = [
      {
        'id': 99,
        'code': 'EXTRA-LONG-MACHINE-IDENTIFIER-CODE-999-SPECIAL-EXP',
        'name': 'Picanol OmniPlus-i Super High Speed Air Jet Rapier Loom Extended Edition #99',
        'machine_type_name': 'Advanced Industrial Textile Machine Model XT-9999',
        'category': 'WEAVING',
        'department_code': 'WEV',
        'department_name': 'Weaving Shed & Heavy Fabrication Department (North Wing)',
        'floor_location': 'Building 14, Sector 7-C, High Vibration Foundation Pad #4',
        'raw_status': 'OPERATIONAL_FAULT',
        'twin_presentation_state': 'UNDER_MAINTENANCE_EMERGENCY_REPAIR',
        'state_reason': 'Emergency bearing failure and secondary thermal sensor spike to abnormal level',
        'health_score': 12.5,
        'rated_capacity_units_per_hour': 9999.0,
        'rated_speed_rpm': 999999,
        'latest_telemetry': {
          'temperature_c': 999.9,
          'vibration_mms': 99.99,
          'speed_rpm': 999999,
          'power_kw': 999.9,
          'utilization_pct': 100.0,
          'timestamp': '2026-10-12T11:00:00Z',
        },
        'operating_limits': {
          'max_temp_c': 999.0,
          'warning_temp_c': 888.0,
          'max_vibration_mms': 99.0,
          'warning_vibration_mms': 88.0,
        },
        'production_assignment': {
          'order_number': 'ORD-EXP-EXTREME-PRODUCTION-SPEC-2026-XYZ',
          'client_name': 'PSG Tech Global Industrial Textiles Corporation Limited',
          'fabric_spec': 'Ultra-Dense Ballistic Kevlar-Aramid Hybrid 850 GSM Composite',
          'planned_quantity': 50000,
          'unit': 'METERS',
          'status': 'INTERRUPTED_BY_MAINTENANCE',
        },
        'active_incidents': [999],
        'active_tickets': [888],
        'compatible_alternates': ['ALT-M1', 'ALT-M2', 'ALT-M3', 'ALT-M4', 'ALT-M5'],
      },
    ];

    final snapshot = _buildMockSnapshot(customMachines: extremeMachines);

    await tester.pumpWidget(
      MaterialApp(
        home: DigitalTwinScreen(
          initialSnapshot: snapshot,
          initialViewMode: DigitalTwinViewMode.gridView,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify extreme tile rendered without throwing layout overflow
    expect(tester.takeException(), isNull);

    // Open detail panel for the extreme machine
    await tester.tap(find.text('EXTRA-LONG-MACHINE-IDENTIFIER-CODE-999-SPECIAL-EXP'));
    await tester.pumpAndSettle();

    // Verify detail panel rendered with extreme values without throwing layout overflow
    expect(tester.takeException(), isNull);
    expect(find.text('OPERATING THRESHOLD LIMITS'), findsOneWidget);
    expect(find.text('ACTIVE PRODUCTION ASSIGNMENT'), findsOneWidget);

    // Close inspector
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
