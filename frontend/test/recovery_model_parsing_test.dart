import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/data/models/recovery_models.dart';
import 'package:frontend/data/services/api_service.dart';

void main() {
  group('Phase 6 Recovery Model & API Service Regression Tests', () {
    test('RecoveryCaseModel.fromJson parses complete backend response for REC-20261009-4D88', () {
      final sampleJson = {
        "id": 4,
        "case_code": "REC-20261009-4D88",
        "incident": 30,
        "incident_code": "INC-20261009033959-0AA590-WEV-AJ-02",
        "incident_severity": "CRITICAL",
        "incident_summary": "Severe mechanical vibration (5.97 mm/s) exceeding critical limit (5.8 mm/s) on WEV-AJ-02",
        "machine": 10,
        "machine_code": "WEV-AJ-02",
        "machine_name": "Picanol OmniPlus-i Loom #2",
        "department_name": "Weaving Shed",
        "status": "AWAITING_APPROVALS",
        "priority": "HIGH",
        "priority_score": "70.00",
        "target_resolution_hours": "2.00",
        "estimated_downtime_hours": "1.50",
        "summary": "Correlated Multi-Agent Recovery Plan for WEV-AJ-02",
        "pending_approvals_count": 1,
        "is_all_steps_completed": false,
        "health_diagnosis": {
          "severity_assessment": "CRITICAL",
          "confidence_score": 95.0,
        },
        "maintenance_recommendation": {
          "assigned_technician": "Weaving Shed Fast-Response Mechanical Team",
          "estimated_hours": 1.5,
        },
        "inventory_assessment": {
          "shortages_count": 0,
        },
        "production_impact_assessment": {
          "alternate_machines": [{"machine_code": "WEV-AJ-01"}],
        },
        "steps": [
          {
            "id": 10,
            "step_order": 1,
            "title": "Spare Parts Allocation & Warehouse Reservation",
            "description": "Reserve 1.0 PCS of SPR-BRG-6309",
            "agent_type": "INVENTORY",
            "action_type": "RESERVE_SPARE_PART",
            "status": "AWAITING_APPROVAL",
            "dependencies": [],
            "approval_id": 31,
            "approval_code": "APR-20261009034015-341E",
            "approval_status": "PENDING",
            "action_payload": {},
            "output_payload": {},
          },
          {
            "id": 11,
            "step_order": 2,
            "title": "Mechanical Work Order Execution & Inspection Protocols",
            "description": "Dispatch team",
            "agent_type": "MAINTENANCE",
            "action_type": "CREATE_MAINTENANCE_TICKET",
            "status": "COMPLETED",
            "dependencies": [1],
            "approval_id": 30,
            "approval_code": "APR-20261009034015-42EE",
            "approval_status": "APPROVED",
            "action_payload": {},
            "output_payload": {"ticket_number": "MNT-20261009034015-88A5"},
          }
        ],
        "created_at": "2026-10-09T09:10:15.633601+05:30",
        "updated_at": "2026-10-09T09:10:15.633622+05:30",
      };

      final model = RecoveryCaseModel.fromJson(sampleJson);

      expect(model.id, 4);
      expect(model.caseCode, 'REC-20261009-4D88');
      expect(model.machineCode, 'WEV-AJ-02');
      expect(model.status, 'AWAITING_APPROVALS');
      expect(model.priorityScore, 70.0);
      expect(model.steps.length, 2);
      expect(model.steps[0].approvalCode, 'APR-20261009034015-341E');
      expect(model.steps[1].status, 'COMPLETED');
      expect(model.steps[1].outputPayload['ticket_number'], 'MNT-20261009034015-88A5');
    });

    test('RecoverySummaryModel.fromJson parses metrics and lists', () {
      final sampleSummary = {
        "metrics": {
          "total_cases": 4,
          "active_cases": 4,
          "awaiting_approvals": 4,
          "in_recovery": 0,
          "recovered_cases": 0,
          "critical_cases": 0,
          "pending_approvals_total": 27,
          "reserved_spares_count": 0,
        },
        "recent_cases": [],
        "pending_approvals": [],
      };

      final summary = RecoverySummaryModel.fromJson(sampleSummary);
      expect(summary.totalCases, 4);
      expect(summary.activeCases, 4);
      expect(summary.awaitingApprovals, 4);
      expect(summary.pendingApprovalsTotal, 27);
    });

    test('ApiService throws Exception on HTTP 500 error instead of silently returning empty list', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final apiService = ApiService(client: mockClient);

      expect(
        () async => await apiService.getRecoveryCases(),
        throwsA(isA<Exception>()),
      );
      expect(
        () async => await apiService.getRecoverySummary(),
        throwsA(isA<Exception>()),
      );
    });
  });
}
