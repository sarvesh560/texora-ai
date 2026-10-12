import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/digital_twin_models.dart';
import 'package:frontend/presentation/widgets/factory_flow_view.dart';

void main() {
  testWidgets('FactoryFlowView renders all 5 departmental stages and conceptual flow notice', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dummySnapshot = DigitalTwinSnapshotModel.fromJson({
      'snapshot_id': 'SNAP-TEST-01',
      'factory_code': 'FAC-01',
      'captured_at': DateTime.now().toIso8601String(),
      'total_machines': 25,
      'operational_summary': {
        'total_machines': 25,
        'state_distribution': {'RUNNING': 25, 'CRITICAL': 0, 'WARNING': 0},
      },
      'machine_states': [
        {
          'id': 1,
          'code': 'SPN-CARD-01',
          'name': 'Carding Machine 01',
          'machine_type_name': 'Carding',
          'category': 'SPINNING',
          'department_code': 'SPN',
          'department_name': 'Spinning',
          'floor_location': 'Zone A',
          'raw_status': 'OPERATIONAL',
          'twin_presentation_state': 'RUNNING',
          'state_reason': 'Nominal operation',
          'health_score': 95.0,
          'rated_capacity_units_per_hour': 250.0,
          'rated_speed_rpm': 1200,
          'active_incidents': [],
          'active_tickets': [],
          'compatible_alternates': [],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FactoryFlowView(
            snapshot: dummySnapshot,
            selectedDepartment: 'ALL',
            selectedMachine: null,
            onSelectDepartment: (_) {},
            onSelectMachine: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Verify Department Flow Cards exist
    expect(find.text('Spinning Dept'), findsOneWidget);
    expect(find.text('Weaving Shed'), findsOneWidget);
    expect(find.text('Knitting Div'), findsOneWidget);
    expect(find.text('Dyeing & Proc'), findsOneWidget);
    expect(find.text('Finishing & Insp'), findsOneWidget);

    // Verify Conceptual Process Note
    expect(find.textContaining('Process Flow Topology:'), findsOneWidget);
  });
}
