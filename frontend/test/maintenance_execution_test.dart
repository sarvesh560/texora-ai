import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/work_order_models.dart';
import 'package:frontend/presentation/screens/maintenance_execution_screen.dart';

void main() {
  group('Phase 12 Work Order Model Parsing Tests', () {
    test('ChecklistItem JSON serialization & deserialization', () {
      final json = {
        'step_id': 1,
        'task': 'Measure main drive vibration',
        'status': 'PENDING',
        'expected_threshold': 'Vibration < 4.0 mm/s',
        'observed_value': '6.8 mm/s',
        'notes': 'High harmonic spike',
      };

      final item = ChecklistItem.fromJson(json);
      expect(item.stepId, 1);
      expect(item.task, 'Measure main drive vibration');
      expect(item.status, 'PENDING');
      expect(item.observedValue, '6.8 mm/s');

      final serialized = item.toJson();
      expect(serialized['step_id'], 1);
      expect(serialized['status'], 'PENDING');
      expect(serialized['observed_value'], '6.8 mm/s');
    });

    test('WorkOrderTicket JSON deserialization with transitions and verification data', () {
      final json = {
        'id': 101,
        'ticket_number': 'MNT-2026-0099',
        'machine': 12,
        'machine_code': 'WEV-AJ-02',
        'machine_name': 'Picanol OmniPlus-i Loom #2',
        'machine_type_name': 'Air Jet Loom 340cm',
        'department_name': 'Weaving Shed A',
        'department_code': 'WEV',
        'incident_reference': 'INC-2026-0099',
        'title': 'Repair: Excessive main drive vibration on WEV-AJ-02',
        'description': 'Authorized maintenance work order',
        'priority': 'CRITICAL',
        'status': 'AWAITING_VERIFICATION',
        'assigned_technician': 'R. Sharma (Senior Diagnostic Tech)',
        'created_by_agent': 'Maintenance Coordinator',
        'root_cause': 'Drive bearing race spalling',
        'parts_cost': 850.0,
        'labor_hours': 2.0,
        'actual_repair_duration_minutes': 45,
        'ai_suspected_causes': [
          {'cause': 'Bearing fatigue wear', 'likelihood': 'HIGH', 'category': 'Bearing'}
        ],
        'inspection_checklist': [
          {
            'step_id': 1,
            'task': 'Check bearing vibration',
            'status': 'DEFECT_FOUND',
            'expected_threshold': '< 4.0 mm/s',
            'observed_value': '6.8 mm/s',
            'notes': 'Damaged raceway',
          }
        ],
        'confirmed_fault': 'Fatigue spalling on bearing #6204',
        'fault_confirmation_notes': 'Confirmed via acoustic and thermal probe',
        'repair_performed': 'Replaced bearing #6204 and repacked grease',
        'parts_replaced': [
          {'item_code': 'SPR-BRG-6204', 'quantity': 1, 'deducted': true}
        ],
        'remaining_issues': 'None',
        'repair_completed_at': '2026-10-12T10:00:00Z',
        'verification_status': 'PASSED_TELEMETRY_CHECKS',
        'verification_summary': 'All 5 samples nominal',
        'verification_data': {
          'outcome': 'PASSED_TELEMETRY_CHECKS',
          'max_vibration': 2.4,
          'max_temp': 55.0,
        },
        'authorized_signoff_by': '',
        'authorized_signoff_at': null,
        'signoff_notes': '',
        'is_simulation': true,
        'created_at': '2026-10-12T09:00:00Z',
        'resolved_at': null,
        'transitions': [
          {
            'id': 1,
            'actor': 'R. Sharma',
            'actor_role': 'Technician',
            'previous_state': 'CREATED',
            'new_state': 'ACCEPTED',
            'reason': 'Accepted work order',
            'timestamp': '2026-10-12T09:15:00Z',
          }
        ],
      };

      final ticket = WorkOrderTicket.fromJson(json);
      expect(ticket.id, 101);
      expect(ticket.ticketNumber, 'MNT-2026-0099');
      expect(ticket.machineCode, 'WEV-AJ-02');
      expect(ticket.confirmedFault, 'Fatigue spalling on bearing #6204');
      expect(ticket.actualRepairDurationMinutes, 45);
      expect(ticket.verificationStatus, 'PASSED_TELEMETRY_CHECKS');
      expect(ticket.isSimulation, true);
      expect(ticket.transitions.length, 1);
      expect(ticket.transitions.first.newState, 'ACCEPTED');
    });

    test('ExecutionDetailResponse JSON deserialization', () {
      final json = {
        'ticket': {
          'id': 101,
          'ticket_number': 'MNT-2026-0099',
          'machine': 12,
          'machine_code': 'WEV-AJ-02',
          'machine_name': 'Loom #2',
          'machine_type_name': 'Air Jet Loom',
          'department_name': 'Weaving',
          'department_code': 'WEV',
          'incident_reference': 'INC-2026-0099',
          'title': 'Repair Loom #2',
          'description': 'Desc',
          'priority': 'CRITICAL',
          'status': 'REPAIR_COMPLETED',
          'assigned_technician': 'R. Sharma',
          'created_by_agent': 'AI',
          'root_cause': 'Bearing',
          'parts_cost': 850.0,
          'labor_hours': 1.5,
          'actual_repair_duration_minutes': 45,
          'ai_suspected_causes': [],
          'inspection_checklist': [],
          'confirmed_fault': 'Bearing #6204',
          'fault_confirmation_notes': '',
          'repair_performed': 'Replaced bearing',
          'parts_replaced': [],
          'remaining_issues': '',
          'verification_status': 'MONITORING',
          'verification_summary': '',
          'verification_data': {},
          'authorized_signoff_by': '',
          'signoff_notes': '',
          'is_simulation': false,
          'created_at': '2026-10-12T09:00:00Z',
          'transitions': [],
        },
        'machine_limits': {
          'warning_vibration_mms': 4.0,
          'max_vibration_mms': 5.5,
          'warning_temp_c': 75.0,
          'max_temp_c': 85.0,
          'min_rpm': 700,
          'max_rpm': 1200,
        },
        'telemetry_trend': [
          {
            'id': 1,
            'timestamp': '2026-10-12T09:30:00Z',
            'vibration_mms': 2.3,
            'temperature_c': 55.4,
            'speed_rpm': 1050.0,
            'power_kw': 12.1,
          }
        ],
        'spare_parts_catalog': [
          {
            'item_code': 'SPR-BRG-6204',
            'name': 'Bearing 6204',
            'current_stock': 12.0,
            'unit': 'PCS',
            'unit_cost': 850.0,
          }
        ],
        'maintenance_history': [],
        'verification_evaluation': {
          'outcome': 'AWAITING_AUTHORIZED_SIGNOFF',
          'summary': '5 samples within nominal limits',
          'is_healthy': true,
          'readings_count': 5,
          'avg_vibration': 2.3,
          'max_vibration': 2.5,
          'limit_vibration': 4.0,
          'avg_temp': 55.0,
          'max_temp': 56.5,
          'limit_temp': 75.0,
          'is_stable': true,
          'checks': {'telemetry_nominal': true},
        },
      };

      final resp = ExecutionDetailResponse.fromJson(json);
      expect(resp.ticket.ticketNumber, 'MNT-2026-0099');
      expect(resp.limits.warningVibrationMms, 4.0);
      expect(resp.telemetryTrend.length, 1);
      expect(resp.telemetryTrend.first.vibrationMms, 2.3);
      expect(resp.verificationEvaluation.isHealthy, true);
      expect(resp.verificationEvaluation.outcome, 'AWAITING_AUTHORIZED_SIGNOFF');
    });
  });

  group('Phase 12 Maintenance Execution Screen Widget Tests', () {
    testWidgets('MaintenanceExecutionScreen renders title, header, and search box', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MaintenanceExecutionScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Maintenance Execution Center'), findsOneWidget);
      expect(find.text('AI-Guided Field Repairs • Sensor Verification • Evidence-Based Incident Closure'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    test('Ticket MNT-20261012104734-3F03 model representation in AWAITING_VERIFICATION state', () {
      final json = {
        'id': 44,
        'ticket_number': 'MNT-20261012104734-3F03',
        'machine': 2,
        'machine_code': 'WEV-AJ-02',
        'machine_name': 'Picanol OmniPlus-i Loom #2',
        'machine_type_name': 'Air Jet Loom 340cm',
        'department_name': 'Weaving Shed A',
        'department_code': 'WEV',
        'incident_reference': 'INC-20261012-0042',
        'title': 'Corrective Repair: WEV-AJ-02 Drive Bearing Spalling',
        'description': 'Main drive bearing replacement and realignment',
        'priority': 'CRITICAL',
        'status': 'AWAITING_VERIFICATION',
        'assigned_technician': 'R. Sharma (Senior Diagnostic Tech)',
        'created_by_agent': 'Maintenance Coordinator',
        'root_cause': 'Fatigue wear on drive bearing #6204',
        'parts_cost': '10550.00',
        'labor_hours': '2.50',
        'actual_repair_duration_minutes': '45',
        'ai_suspected_causes': [],
        'inspection_checklist': [
          {'step_id': 1, 'task': 'Bearing vibration', 'status': 'DEFECT_FOUND', 'observed_value': '6.8 mm/s'}
        ],
        'confirmed_fault': 'Fatigue spalling on bearing #6204',
        'fault_confirmation_notes': 'Acoustic and thermal probe confirmation',
        'repair_performed': 'Bearing #6204 replaced and aligned',
        'parts_replaced': [
          {'item_code': 'SPR-BRG-6204', 'quantity': 1.0, 'deducted': true, 'unit_cost': 350.0}
        ],
        'remaining_issues': 'None',
        'repair_completed_at': '2026-10-13T06:25:15Z',
        'verification_status': 'AWAITING_AUTHORIZED_SIGNOFF',
        'verification_summary': 'All 6 samples within nominal limits',
        'verification_data': {
          'outcome': 'AWAITING_AUTHORIZED_SIGNOFF',
          'max_vibration': 2.35,
          'max_temp': 56.4,
          'is_healthy': true,
        },
        'authorized_signoff_by': '',
        'authorized_signoff_at': null,
        'signoff_notes': '',
        'is_simulation': true,
        'created_at': '2026-10-12T10:47:34Z',
        'resolved_at': null,
        'transitions': [
          {
            'id': 1,
            'actor': 'R. Sharma',
            'actor_role': 'Technician',
            'previous_state': 'OPEN',
            'new_state': 'ACCEPTED',
            'reason': 'Accepted',
            'timestamp': '2026-10-13T06:20:57Z',
          },
          {
            'id': 2,
            'actor': 'R. Sharma',
            'actor_role': 'Technician',
            'previous_state': 'REPAIR_IN_PROGRESS',
            'new_state': 'REPAIR_COMPLETED',
            'reason': 'Finished repair',
            'timestamp': '2026-10-13T06:25:15Z',
          },
          {
            'id': 3,
            'actor': 'R. Sharma',
            'actor_role': 'Technician',
            'previous_state': 'REPAIR_COMPLETED',
            'new_state': 'AWAITING_VERIFICATION',
            'reason': 'Ready for verification',
            'timestamp': '2026-10-13T06:25:15Z',
          },
        ],
      };

      final ticket = WorkOrderTicket.fromJson(json);
      expect(ticket.ticketNumber, 'MNT-20261012104734-3F03');
      expect(ticket.status, 'AWAITING_VERIFICATION');
      expect(ticket.verificationStatus, 'AWAITING_AUTHORIZED_SIGNOFF');
      expect(ticket.repairCompletedAt, isNotNull);
      expect(ticket.partsReplaced.length, 1);
      expect(ticket.partsReplaced.first['deducted'], true);
      expect(ticket.transitions.length, 3);
      expect(ticket.transitions.last.newState, 'AWAITING_VERIFICATION');
    });

    test('ExecutionDetailResponse for AWAITING_VERIFICATION ticket correctly structures evaluation', () {
      final detailJson = {
        'ticket': {
          'id': 44,
          'ticket_number': 'MNT-20261012104734-3F03',
          'machine': 2,
          'machine_code': 'WEV-AJ-02',
          'machine_name': 'Loom #2',
          'machine_type_name': 'Air Jet Loom',
          'department_name': 'Weaving Shed A',
          'department_code': 'WEV',
          'incident_reference': 'INC-20261012-0042',
          'title': 'Drive Bearing Repair',
          'description': 'Repaired',
          'priority': 'CRITICAL',
          'status': 'AWAITING_VERIFICATION',
          'assigned_technician': 'R. Sharma',
          'created_by_agent': 'AI',
          'root_cause': 'Bearing wear',
          'parts_cost': '10550.00',
          'labor_hours': '2.50',
          'actual_repair_duration_minutes': '45',
          'ai_suspected_causes': [],
          'inspection_checklist': [],
          'confirmed_fault': 'Fatigued bearing',
          'fault_confirmation_notes': '',
          'repair_performed': 'Replaced bearing',
          'parts_replaced': [
            {'item_code': 'SPR-BRG-6204', 'quantity': 1.0, 'deducted': true}
          ],
          'remaining_issues': '',
          'repair_completed_at': '2026-10-13T06:25:15Z',
          'verification_status': 'AWAITING_AUTHORIZED_SIGNOFF',
          'verification_summary': 'Telemetry normalized',
          'verification_data': {
            'outcome': 'AWAITING_AUTHORIZED_SIGNOFF',
            'is_healthy': true,
            'max_vibration': 2.35,
            'limit_vibration': 4.0,
            'max_temp': 56.4,
            'limit_temp': 75.0,
          },
          'authorized_signoff_by': '',
          'signoff_notes': '',
          'is_simulation': true,
          'created_at': '2026-10-12T10:47:34Z',
          'transitions': [],
        },
        'machine_limits': {
          'warning_vibration_mms': 4.0,
          'max_vibration_mms': 5.5,
          'warning_temp_c': 75.0,
          'max_temp_c': 85.0,
          'min_rpm': 700,
          'max_rpm': 1200,
        },
        'telemetry_trend': [
          {
            'id': 1,
            'timestamp': '2026-10-13T06:25:20Z',
            'vibration_mms': 2.35,
            'temperature_c': 56.4,
            'speed_rpm': 1050.0,
            'power_kw': 12.0,
          }
        ],
        'spare_parts_catalog': [
          {
            'item_code': 'SPR-BRG-6204',
            'name': 'Deep Groove Ball Bearing 6204',
            'current_stock': '11.00',
            'unit': 'PCS',
            'unit_cost': '350.00',
          }
        ],
        'maintenance_history': [],
        'verification_evaluation': {
          'outcome': 'AWAITING_AUTHORIZED_SIGNOFF',
          'summary': 'All telemetry within limits. Ready for manager sign-off.',
          'is_healthy': true,
          'readings_count': 6,
          'avg_vibration': 2.30,
          'max_vibration': 2.35,
          'limit_vibration': 4.0,
          'avg_temp': 55.5,
          'max_temp': 56.4,
          'limit_temp': 75.0,
          'is_stable': true,
          'checks': {
            'physical_repair_completed': true,
            'telemetry_nominal': true,
            'stability_confirmed': true,
            'authorized_signoff': false,
          },
        },
      };

      final response = ExecutionDetailResponse.fromJson(detailJson);
      expect(response.ticket.ticketNumber, 'MNT-20261012104734-3F03');
      expect(response.ticket.status, 'AWAITING_VERIFICATION');
      expect(response.verificationEvaluation.isHealthy, true);
      expect(response.verificationEvaluation.outcome, 'AWAITING_AUTHORIZED_SIGNOFF');
      expect(response.verificationEvaluation.maxVibration, 2.35);
      expect(response.sparePartsCatalog.first['current_stock'], '11.00');
    });
  });
}
