import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/utils/numeric_parser.dart';
import 'package:frontend/data/models/work_order_models.dart';

void main() {
  group('NumericParser Unit Tests', () {
    test('parseNullableDouble handles null, num, decimal string, and spaces', () {
      expect(parseNullableDouble(null), isNull);
      expect(parseNullableDouble(''), isNull);
      expect(parseNullableDouble('   '), isNull);
      expect(parseNullableDouble(0), 0.0);
      expect(parseNullableDouble(0.0), 0.0);
      expect(parseNullableDouble(42.5), 42.5);
      expect(parseNullableDouble('0.00'), 0.0);
      expect(parseNullableDouble('123.45'), 123.45);
      expect(parseNullableDouble('  -15.75  '), -15.75);
    });

    test('parseNullableDouble rejects invalid strings and non-numeric types', () {
      expect(() => parseNullableDouble('invalid_num'), throwsFormatException);
      expect(() => parseNullableDouble('12.34.56'), throwsFormatException);
      expect(() => parseNullableDouble(['not', 'a', 'num']), throwsFormatException);
      expect(() => parseNullableDouble({'bad': 'value'}), throwsFormatException);
    });

    test('parseRequiredDouble handles values and defaults, rejects missing/invalid', () {
      expect(parseRequiredDouble(10.5, fieldName: 'test'), 10.5);
      expect(parseRequiredDouble('10.50', fieldName: 'test'), 10.5);
      expect(parseRequiredDouble('0.00', fieldName: 'test'), 0.0);
      expect(parseRequiredDouble(null, fieldName: 'test', defaultValue: 5.0), 5.0);
      expect(parseRequiredDouble('', fieldName: 'test', defaultValue: 5.0), 5.0);

      expect(
        () => parseRequiredDouble(null, fieldName: 'parts_cost'),
        throwsFormatException,
      );
      expect(
        () => parseRequiredDouble('abc', fieldName: 'parts_cost'),
        throwsFormatException,
      );
    });

    test('parseDoubleWithFallback uses fallback on null/empty, parses valid strings/nums', () {
      expect(parseDoubleWithFallback(null, 4.0), 4.0);
      expect(parseDoubleWithFallback('', 4.0), 4.0);
      expect(parseDoubleWithFallback('   ', 4.0), 4.0);
      expect(parseDoubleWithFallback('0.00', 4.0), 0.0);
      expect(parseDoubleWithFallback('5.25', 4.0), 5.25);
      expect(parseDoubleWithFallback(8.5, 4.0), 8.5);
      expect(() => parseDoubleWithFallback('corrupt', 4.0), throwsFormatException);
    });

    test('parseNullableInt and parseIntWithFallback handle int, double, and string formats', () {
      expect(parseNullableInt(null), isNull);
      expect(parseNullableInt(''), isNull);
      expect(parseNullableInt(10), 10);
      expect(parseNullableInt(10.7), 10);
      expect(parseNullableInt('10'), 10);
      expect(parseNullableInt('10.0'), 10);
      expect(parseNullableInt('  45  '), 45);

      expect(parseIntWithFallback(null, 100), 100);
      expect(parseIntWithFallback('', 100), 100);
      expect(parseIntWithFallback('0', 100), 0);
      expect(parseIntWithFallback('50', 100), 50);

      expect(() => parseNullableInt('not_int'), throwsFormatException);
      expect(() => parseRequiredInt(null, fieldName: 'id'), throwsFormatException);
    });
  });

  group('WorkOrderTicket & ExecutionDetailResponse String Decimal Parsing Tests', () {
    test('WorkOrderTicket parses Django DecimalField string values ("0.00") without TypeError', () {
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
        'title': 'Repair: Main drive vibration',
        'description': 'Work order description',
        'priority': 'CRITICAL',
        'status': 'CREATED',
        'assigned_technician': 'Mechanical Team',
        'created_by_agent': 'Maintenance Coordinator',
        'root_cause': '',
        // These are strings from Django DecimalField!
        'parts_cost': '0.00',
        'labor_hours': '0.00',
        'actual_repair_duration_minutes': '0',
        'ai_suspected_causes': [],
        'inspection_checklist': [],
        'confirmed_fault': '',
        'fault_confirmation_notes': '',
        'repair_performed': '',
        'parts_replaced': [],
        'remaining_issues': '',
        'repair_completed_at': null,
        'verification_status': 'PENDING_EVIDENCE',
        'verification_summary': '',
        'verification_data': {},
        'authorized_signoff_by': '',
        'authorized_signoff_at': null,
        'signoff_notes': '',
        'is_simulation': false,
        'created_at': '2026-10-12T09:00:00Z',
        'resolved_at': null,
        'transitions': [],
      };

      final ticket = WorkOrderTicket.fromJson(json);
      expect(ticket.id, 101);
      expect(ticket.partsCost, 0.0);
      expect(ticket.laborHours, 0.0);
      expect(ticket.actualRepairDurationMinutes, 0);
      expect(ticket.status, 'CREATED');
    });

    test('WorkOrderTicket parses non-zero DecimalField strings e.g. "850.50" and "2.50"', () {
      final json = {
        'id': 102,
        'ticket_number': 'MNT-2026-0102',
        'machine': 12,
        'parts_cost': '850.50',
        'labor_hours': '2.50',
        'actual_repair_duration_minutes': '45',
        'status': 'REPAIR_COMPLETED',
        'verification_status': 'PASSED_TELEMETRY_CHECKS',
      };

      final ticket = WorkOrderTicket.fromJson(json);
      expect(ticket.partsCost, 850.50);
      expect(ticket.laborHours, 2.50);
      expect(ticket.actualRepairDurationMinutes, 45);
      expect(ticket.status, 'REPAIR_COMPLETED');
    });

    test('ExecutionDetailResponse parses full backend payload with string decimals and telemetry trends', () {
      final fullResponse = {
        'ticket': {
          'id': 105,
          'ticket_number': 'MNT-2026-0105',
          'machine': 14,
          'machine_code': 'WEV-AJ-02',
          'machine_name': 'Loom #2',
          'machine_type_name': 'Air Jet Loom',
          'department_name': 'Weaving',
          'department_code': 'WEV',
          'incident_reference': 'INC-2026-0105',
          'title': 'Bearing Replacement',
          'description': 'Replace defective drive bearing',
          'priority': 'HIGH',
          'status': 'AWAITING_VERIFICATION',
          'assigned_technician': 'R. Sharma',
          'created_by_agent': 'Maintenance Coordinator',
          'root_cause': 'Bearing Raceway Spalling',
          'parts_cost': '125.00',
          'labor_hours': '1.75',
          'actual_repair_duration_minutes': 45,
          'ai_suspected_causes': [],
          'inspection_checklist': [
            {
              'step_id': '1',
              'task': 'Inspect drive bearing',
              'status': 'PASS',
              'expected_threshold': '< 4.0 mm/s',
              'observed_value': '2.1 mm/s',
              'notes': 'Nominal vibration',
            }
          ],
          'confirmed_fault': 'Fatigue spalling on bearing #6204',
          'fault_confirmation_notes': 'Acoustic spike verified',
          'repair_performed': 'Installed new bearing SPR-BRG-6204',
          'parts_replaced': [
            {'item_code': 'SPR-BRG-6204', 'quantity': '1', 'name': 'Ball Bearing 6204'}
          ],
          'remaining_issues': 'None',
          'repair_completed_at': '2026-10-12T11:00:00Z',
          'verification_status': 'PASSED_TELEMETRY_CHECKS',
          'verification_summary': 'Healthy vibration profile',
          'verification_data': {
            'avg_vibration': '2.15',
            'max_vibration': '2.40',
          },
          'authorized_signoff_by': '',
          'authorized_signoff_at': null,
          'signoff_notes': '',
          'is_simulation': true,
          'created_at': '2026-10-12T10:00:00Z',
          'resolved_at': null,
          'transitions': [
            {
              'id': '1',
              'actor': 'R. Sharma',
              'actor_role': 'Technician',
              'previous_state': 'CREATED',
              'new_state': 'ACCEPTED',
              'reason': 'Accepted task',
              'timestamp': '2026-10-12T10:15:00Z',
            }
          ],
        },
        'machine_limits': {
          'warning_vibration_mms': '4.00',
          'max_vibration_mms': '5.50',
          'warning_temp_c': '75.0',
          'max_temp_c': '85.0',
          'min_rpm': '10000',
          'max_rpm': '22000',
        },
        'telemetry_trend': [
          {
            'id': '101',
            'timestamp': '2026-10-12T10:55:00Z',
            'vibration_mms': '2.10',
            'temperature_c': '58.5',
            'speed_rpm': '18500',
            'power_kw': '14.2',
          },
          {
            'id': 102,
            'timestamp': '2026-10-12T10:56:00Z',
            'vibration_mms': 2.05,
            'temperature_c': 58.2,
            'speed_rpm': 18500,
            'power_kw': 14.1,
          }
        ],
        'incident': {
          'id': 50,
          'incident_code': 'INC-2026-0105',
          'status': 'RESOLVED',
        },
        'spare_parts_catalog': [
          {
            'item_code': 'SPR-BRG-6204',
            'name': 'Deep Groove Ball Bearing 6204-2RS',
            'current_stock': '8.00',
            'unit_cost': '45.00',
          }
        ],
        'maintenance_history': [],
        'verification_evaluation': {
          'outcome': 'VERIFIED_RECOVERED',
          'summary': 'All telemetry nominal',
          'is_healthy': true,
          'readings_count': '5',
          'avg_vibration': '2.12',
          'max_vibration': '2.35',
          'limit_vibration': '4.0',
          'avg_temp': '58.4',
          'max_temp': '60.1',
          'limit_temp': '75.0',
          'is_stable': true,
          'checks': {},
        },
      };

      final detail = ExecutionDetailResponse.fromJson(fullResponse);
      expect(detail.ticket.id, 105);
      expect(detail.ticket.partsCost, 125.0);
      expect(detail.ticket.laborHours, 1.75);
      expect(detail.ticket.actualRepairDurationMinutes, 45);
      expect(detail.ticket.inspectionChecklist.first.stepId, 1);
      expect(detail.ticket.transitions.first.id, 1);

      expect(detail.limits.warningVibrationMms, 4.0);
      expect(detail.limits.minRpm, 10000);

      expect(detail.telemetryTrend.length, 2);
      expect(detail.telemetryTrend.first.vibrationMms, 2.10);
      expect(detail.telemetryTrend.last.vibrationMms, 2.05);

      expect(detail.verificationEvaluation.isHealthy, true);
      expect(detail.verificationEvaluation.readingsCount, 5);
      expect(detail.verificationEvaluation.avgVibration, 2.12);
      expect(detail.verificationEvaluation.maxVibration, 2.35);
    });

    test('Handles tickets across all operational states: OPEN, CLOSED, VERIFIED, VERIFICATION_FAILED', () {
      final statuses = [
        {'status': 'CREATED', 'ver': 'PENDING_EVIDENCE'},
        {'status': 'ACCEPTED', 'ver': 'PENDING_EVIDENCE'}, // OPEN
        {'status': 'IN_PROGRESS', 'ver': 'PENDING_EVIDENCE'},
        {'status': 'REPAIR_COMPLETED', 'ver': 'AWAITING_VERIFICATION'},
        {'status': 'VERIFIED_RECOVERED', 'ver': 'PASSED_TELEMETRY_CHECKS'}, // VERIFIED
        {'status': 'VERIFICATION_FAILED', 'ver': 'FAILED_THRESHOLD'}, // VERIFICATION_FAILED
        {'status': 'CLOSED', 'ver': 'PASSED_TELEMETRY_CHECKS'}, // CLOSED
      ];

      for (var s in statuses) {
        final json = {
          'id': 200,
          'ticket_number': 'MNT-TEST',
          'status': s['status'],
          'verification_status': s['ver'],
          'parts_cost': '0.00',
          'labor_hours': '0.00',
        };
        final ticket = WorkOrderTicket.fromJson(json);
        expect(ticket.status, s['status']);
        expect(ticket.verificationStatus, s['ver']);
        expect(ticket.partsCost, 0.0);
        expect(ticket.laborHours, 0.0);
      }
    });
  });
}
