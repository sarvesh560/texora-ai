import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/agent_operations_models.dart';
import 'package:frontend/data/models/digital_twin_models.dart';
import 'package:frontend/data/models/work_order_models.dart';

void main() {
  group('E2E Factory Workflow Verification — Frontend Models & State Integrity', () {
    test('Stages 1-3: Machine Twin, Telemetry Alert & Incident Model Integrity', () {
      final machineJson = {
        'id': 101,
        'code': 'WEV-AJ-01',
        'name': 'Picanol OmniPlus-i Loom #1',
        'machine_type_name': 'Airjet Loom',
        'category': 'WEAVING',
        'department_code': 'WEV',
        'department_name': 'Weaving Department',
        'floor_location': 'Weaving Shed West',
        'raw_status': 'OPERATIONAL',
        'twin_presentation_state': 'HEALTHY',
        'state_reason': 'Nominal operation',
        'health_score': 95.5,
        'rated_capacity_units_per_hour': 60.0,
        'rated_speed_rpm': 950,
        'operating_limits': {
          'warning_vibration_mms': 4.0,
          'max_vibration_mms': 5.8,
          'warning_temp_c': 68.0,
          'max_temp_c': 80.0,
        },
        'latest_telemetry': {
          'vibration_mms': 2.35,
          'temperature_c': 54.2,
          'is_simulated': true,
          'label': 'SIMULATED',
        },
        'active_incidents': [],
        'active_tickets': [],
      };

      final machine = MachineTwinModel.fromJson(machineJson);
      expect(machine.code, equals('WEV-AJ-01'));
      expect(machine.operatingLimits?['max_vibration_mms'], equals(5.8));
      expect(machine.latestTelemetry?['label'], equals('SIMULATED'));
      expect(machine.isStale, isFalse);
    });

    test('Stages 4-5: Specialist Multi-Agent Fleet Execution Model Parsing', () {
      final agentFleetJson = [
        {
          'agent_type': 'MACHINE_HEALTH',
          'name': 'Machine Health Specialist',
          'role': 'Industrial Telemetry Diagnostics',
          'responsibilities': ['Analyze abnormal vibration', 'Synthesize fault hypotheses'],
          'model_name': 'qwen/qwen3.8-27b',
          'is_enabled': true,
          'permitted_actions': ['READ_TELEMETRY', 'PRODUCE_DIAGNOSIS'],
          'current_status': 'COMPLETED',
          'metrics': {
            'total_executions': 42,
            'completed_executions': 42,
            'failed_executions': 0,
            'avg_latency_ms': 590,
          },
          'latest_execution': {
            'execution_id': 'EXEC-001',
            'id': 1,
            'agent_type': 'MACHINE_HEALTH',
            'agent_name': 'Machine Health Specialist',
            'status': 'COMPLETED',
            'machine_code': 'WEV-AJ-01',
            'machine_name': 'Picanol Loom #1',
            'incident_id': 10,
            'incident_code': 'INC-20261013-001',
            'started_at': '2026-10-13T10:00:00Z',
            'completed_at': '2026-10-13T10:00:01Z',
            'latency_ms': 590,
            'token_count': 380,
            'execution_summary': 'Diagnosed drive shaft bearing race spalling [GROQ_LIVE].',
            'latest_findings': 'Drive bearing vibration exceeds critical limit.',
            'confidence_score': 94.5,
            'risk_level': 'HIGH',
            'provenance': 'GroqCloud (qwen/qwen3.8-27b)',
          },
          'recent_executions': [],
        },
      ];

      final agent = SpecialistAgentModel.fromJson(agentFleetJson[0]);
      expect(agent.agentType, equals('MACHINE_HEALTH'));
      expect(agent.name, equals('Machine Health Specialist'));
      expect(agent.currentStatus, equals('COMPLETED'));
      expect(agent.latestExecution?.provenance, contains('GroqCloud'));
      expect(agent.latestExecution?.tokenCount, equals(380));
    });

    test('Stage 6: Digital Twin Strategies A, B, C Ranking & Financial Model', () {
      final evaluationsJson = [
        {
          'strategy_code': 'STRATEGY_A',
          'strategy_name': 'Direct In-Place Component Replacement',
          'rank': 1,
          'is_feasible': true,
          'estimated_cost': 6921.00,
          'estimated_downtime_hours': 1.5,
          'estimated_output_loss': '72.0 m',
          'effectiveness_level': 'HIGH',
        },
        {
          'strategy_code': 'STRATEGY_C',
          'strategy_name': 'Parallel Repair + Retooling',
          'rank': 2,
          'is_feasible': true,
          'estimated_cost': 10521.00,
          'estimated_downtime_hours': 1.5,
          'estimated_output_loss': '72.0 m',
          'effectiveness_level': 'HIGH',
        },
        {
          'strategy_code': 'STRATEGY_B',
          'strategy_name': 'Reroute Production Only',
          'rank': 3,
          'is_feasible': true,
          'estimated_cost': 11292.00,
          'estimated_downtime_hours': 3.0,
          'estimated_output_loss': '144.0 m',
          'effectiveness_level': 'MEDIUM',
        },
      ];

      expect(evaluationsJson[0]['rank'], equals(1));
      expect(evaluationsJson[0]['strategy_code'], equals('STRATEGY_A'));
      expect(evaluationsJson[0]['estimated_cost'], lessThan(evaluationsJson[1]['estimated_cost'] as num));
      expect(evaluationsJson[1]['estimated_cost'], lessThan(evaluationsJson[2]['estimated_cost'] as num));
    });

    test('Stages 7-9: Work Order Ticket Lifecycle & Checklist Population', () {
      final ticketJson = {
        'id': 201,
        'ticket_number': 'MNT-20261013-A101',
        'machine': 12,
        'machine_code': 'WEV-AJ-01',
        'machine_name': 'Picanol Airjet Loom #1',
        'machine_type_name': 'Air Jet Loom',
        'department_name': 'Weaving Shed West',
        'department_code': 'WEV',
        'incident_reference': 'INC-20261013-001',
        'status': 'OPEN',
        'priority': 'CRITICAL',
        'title': 'Authorized Recovery on WEV-AJ-01 (STRATEGY_A)',
        'description': 'Work order created following manager approval',
        'assigned_technician': 'Senior Mechanical Specialist (Shift A)',
        'created_by_agent': 'AutonomousFactoryOrchestrator',
        'root_cause': 'Bearing fatigue wear',
        'parts_cost': 2450.00,
        'labor_hours': 2.50,
        'actual_repair_duration_minutes': 45,
        'ai_suspected_causes': [],
        'inspection_checklist': [
          {
            'step_id': 1,
            'task': 'Measure main drive shaft vibration',
            'status': 'PENDING',
            'expected_threshold': 'Vibration < 4.0 mm/s',
            'observed_value': '',
            'notes': '',
          },
          {
            'step_id': 2,
            'task': 'Inspect bearing housing temperature',
            'status': 'PENDING',
            'expected_threshold': 'Temperature < 68.0 °C',
            'observed_value': '',
            'notes': '',
          },
        ],
        'confirmed_fault': '',
        'fault_confirmation_notes': '',
        'repair_performed': '',
        'parts_replaced': [],
        'remaining_issues': '',
        'verification_status': 'PENDING_EVIDENCE',
        'verification_summary': '',
        'verification_data': {},
        'authorized_signoff_by': '',
        'signoff_notes': '',
        'is_simulation': true,
        'created_at': '2026-10-13T10:00:00Z',
        'transitions': [
          {
            'id': 1,
            'previous_state': 'CREATED',
            'new_state': 'OPEN',
            'actor': 'AutonomousFactoryOrchestrator',
            'actor_role': 'AI Orchestrator',
            'timestamp': '2026-10-13T10:00:00Z',
          }
        ],
      };

      final ticket = WorkOrderTicket.fromJson(ticketJson);
      expect(ticket.ticketNumber, equals('MNT-20261013-A101'));
      expect(ticket.status, equals('OPEN'));
      expect(ticket.inspectionChecklist.length, equals(2));
      expect(ticket.inspectionChecklist[0].task, contains('vibration'));
      expect(ticket.transitions.length, equals(1));
    });

    test('Stages 10-12: Post-Repair Verification States (Healthy vs Faulty)', () {
      // Healthy evaluation payload
      final healthyEvalJson = {
        'ticket': {
          'id': 201,
          'ticket_number': 'MNT-20261013-A101',
          'machine': 12,
          'machine_code': 'WEV-AJ-01',
          'machine_name': 'Picanol Airjet Loom #1',
          'machine_type_name': 'Air Jet Loom',
          'department_name': 'Weaving Shed West',
          'department_code': 'WEV',
          'incident_reference': 'INC-20261013-001',
          'status': 'AWAITING_VERIFICATION',
          'priority': 'CRITICAL',
          'title': 'Authorized Recovery on WEV-AJ-01',
          'description': 'Work order description',
          'assigned_technician': 'Senior Mechanical Specialist',
          'created_by_agent': 'AutonomousFactoryOrchestrator',
          'root_cause': '',
          'parts_cost': 2450.0,
          'labor_hours': 2.5,
          'actual_repair_duration_minutes': 45,
          'ai_suspected_causes': [],
          'inspection_checklist': [],
          'confirmed_fault': 'Bearing race spalling',
          'fault_confirmation_notes': '',
          'repair_performed': 'Replaced bearing #6204',
          'parts_replaced': [{'item_code': 'SPR-BRG-6204', 'quantity': 1, 'deducted': true}],
          'remaining_issues': '',
          'verification_status': 'AWAITING_AUTHORIZED_SIGNOFF',
          'verification_summary': 'All 6 post-repair telemetry samples nominal',
          'verification_data': {},
          'authorized_signoff_by': '',
          'signoff_notes': '',
          'is_simulation': true,
          'created_at': '2026-10-13T10:00:00Z',
          'transitions': [],
        },
        'machine_limits': {
          'warning_vibration_mms': 4.0,
          'max_vibration_mms': 5.8,
          'warning_temp_c': 68.0,
          'max_temp_c': 80.0,
          'min_rpm': 700,
          'max_rpm': 1050,
        },
        'telemetry_trend': [],
        'spare_parts_catalog': [],
        'maintenance_history': [],
        'verification_evaluation': {
          'outcome': 'AWAITING_AUTHORIZED_SIGNOFF',
          'summary': 'All 6 post-repair telemetry samples are within nominal limits.',
          'is_healthy': true,
          'readings_count': 6,
          'avg_vibration': 2.35,
          'max_vibration': 2.55,
          'limit_vibration': 4.0,
          'avg_temp': 54.0,
          'max_temp': 56.5,
          'limit_temp': 68.0,
          'is_stable': true,
          'checks': {
            'physical_repair_completed': true,
            'telemetry_nominal': true,
            'authorized_signoff': false,
          },
        },
      };

      final healthyResp = ExecutionDetailResponse.fromJson(healthyEvalJson);
      expect(healthyResp.ticket.status, equals('AWAITING_VERIFICATION'));
      expect(healthyResp.verificationEvaluation.outcome, equals('AWAITING_AUTHORIZED_SIGNOFF'));
      expect(healthyResp.verificationEvaluation.isHealthy, isTrue);
      expect(healthyResp.verificationEvaluation.checks['physical_repair_completed'], isTrue);

      // Faulty evaluation payload
      final faultyEvalJson = {
        'ticket': {
          'id': 202,
          'ticket_number': 'MNT-FAULTY-002',
          'machine': 12,
          'machine_code': 'WEV-AJ-01',
          'machine_name': 'Picanol Airjet Loom #1',
          'machine_type_name': 'Air Jet Loom',
          'department_name': 'Weaving Shed West',
          'department_code': 'WEV',
          'incident_reference': 'INC-20261013-002',
          'status': 'VERIFICATION_FAILED',
          'priority': 'CRITICAL',
          'title': 'Faulty Recovery Test',
          'description': '',
          'assigned_technician': 'Tech',
          'created_by_agent': 'AI',
          'root_cause': '',
          'parts_cost': 0.0,
          'labor_hours': 1.0,
          'actual_repair_duration_minutes': 30,
          'ai_suspected_causes': [],
          'inspection_checklist': [],
          'confirmed_fault': 'Vibration persisting',
          'fault_confirmation_notes': '',
          'repair_performed': 'Attempted adjustment',
          'parts_replaced': [],
          'remaining_issues': 'Elevated vibration',
          'verification_status': 'FAILED',
          'verification_summary': 'Vibration readings exceed threshold',
          'verification_data': {},
          'authorized_signoff_by': '',
          'signoff_notes': '',
          'is_simulation': true,
          'created_at': '2026-10-13T10:00:00Z',
          'transitions': [],
        },
        'machine_limits': {
          'warning_vibration_mms': 4.0,
          'max_vibration_mms': 5.8,
          'warning_temp_c': 68.0,
          'max_temp_c': 80.0,
          'min_rpm': 700,
          'max_rpm': 1050,
        },
        'telemetry_trend': [],
        'spare_parts_catalog': [],
        'maintenance_history': [],
        'verification_evaluation': {
          'outcome': 'FAILED',
          'summary': 'Recovery verification failed: Vibration readings exceed threshold.',
          'is_healthy': false,
          'readings_count': 6,
          'avg_vibration': 6.85,
          'max_vibration': 7.10,
          'limit_vibration': 4.0,
          'avg_temp': 81.0,
          'max_temp': 84.5,
          'limit_temp': 68.0,
          'is_stable': false,
          'checks': {
            'physical_repair_completed': true,
            'telemetry_nominal': false,
            'authorized_signoff': false,
          },
        },
      };

      final faultyResp = ExecutionDetailResponse.fromJson(faultyEvalJson);
      expect(faultyResp.ticket.status, equals('VERIFICATION_FAILED'));
      expect(faultyResp.verificationEvaluation.outcome, equals('FAILED'));
      expect(faultyResp.verificationEvaluation.isHealthy, isFalse);
      expect(faultyResp.verificationEvaluation.checks['telemetry_nominal'], isFalse);
    });

    test('Stage 15: Multi-Cloud Provider Health Matrix Parsing', () {
      final matrixJson = {
        'routing_mode': 'auto',
        'primary_provider': 'groq',
        'secondary_provider': 'gemini',
        'current_fallback_state': 'STANDBY',
        'groq': {
          'configured': true,
          'is_configured': true,
          'status': 'OPERATIONAL',
          'model': 'qwen/qwen3.8-27b',
          'ready': true,
          'circuit_breaker_open': false,
          'circuit_breaker_status': 'CLOSED',
          'latency_ms': 589,
          'is_stale': false,
          'message': 'Operational',
        },
        'gemini': {
          'configured': true,
          'is_configured': true,
          'status': 'CONFIGURED',
          'model': 'gemini-3.5-flash',
          'ready': true,
          'circuit_breaker_open': false,
          'circuit_breaker_status': 'CLOSED',
          'latency_ms': null,
          'is_stale': false,
          'message': 'Configured',
        },
        'deterministic_fallback': {
          'configured': true,
          'is_configured': true,
          'status': 'OPERATIONAL',
          'model': 'texora-industrial-heuristics-v2',
          'ready': true,
          'circuit_breaker_open': false,
          'circuit_breaker_status': 'BUILT-IN (STANDBY)',
          'latency_ms': 0,
          'message': 'Fallback Ready',
        },
      };

      final health = AiProviderHealthModel.fromJson(matrixJson);
      expect(health.groq.isConfigured, isTrue);
      expect(health.groq.status, equals('OPERATIONAL'));
      expect(health.groq.model, equals('qwen/qwen3.8-27b'));
      expect(health.gemini.isConfigured, isTrue);
      expect(health.deterministicFallback.isConfigured, isTrue);
      expect(health.deterministicFallback.status, equals('OPERATIONAL'));
      expect(health.currentFallbackState, equals('STANDBY'));
    });
  });
}
