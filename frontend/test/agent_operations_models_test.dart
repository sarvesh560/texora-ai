import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/agent_operations_models.dart';
import 'package:frontend/data/models/workflow_timeline_models.dart';

void main() {
  group('Phase 11 Models Parsing Tests', () {
    test('AgentOperationsOverviewModel parses JSON correctly', () {
      final json = {
        'worker_heartbeats': {
          'AUTONOMOUS_ORCHESTRATOR': {
            'worker_name': 'AUTONOMOUS_ORCHESTRATOR',
            'status': 'RUNNING',
            'process_id': 1234,
            'last_heartbeat_at': '2026-10-12T04:45:00Z',
            'processing_count': 14,
            'last_error': '',
          },
          'ANOMALY_DETECTOR': {
            'worker_name': 'ANOMALY_DETECTOR',
            'status': 'RUNNING',
            'process_id': 1235,
            'last_heartbeat_at': '2026-10-12T04:45:00Z',
            'processing_count': 125,
            'last_error': '',
          },
        },
        'overall_metrics': {
          'total_executions': 160,
          'completed_executions': 155,
          'failed_executions': 5,
          'active_incidents': 25,
          'pending_approvals': 2,
        },
        'specialist_agents': [
          {
            'agent_type': 'MACHINE_HEALTH',
            'name': 'Machine Health Specialist',
            'role': 'Industrial Telemetry Diagnostics',
            'responsibilities': ['Analyze abnormal telemetry', 'Diagnose faults'],
            'model_name': 'gemini-2.0-flash',
            'is_enabled': true,
            'permitted_actions': ['READ_TELEMETRY', 'PRODUCE_DIAGNOSIS'],
            'current_status': 'COMPLETED',
            'metrics': {
              'total_executions': 40,
              'completed_executions': 39,
              'failed_executions': 1,
              'avg_latency_ms': 520,
            },
            'latest_execution': {
              'execution_id': 'exec-101',
              'id': 101,
              'agent_type': 'MACHINE_HEALTH',
              'agent_name': 'Machine Health Specialist',
              'status': 'COMPLETED',
              'machine_code': 'WEV-AJ-02',
              'machine_name': 'Toyota Air-Jet Loom #02',
              'incident_id': 10,
              'incident_code': 'INC-20261012-0010',
              'started_at': '2026-10-12T04:00:00Z',
              'completed_at': '2026-10-12T04:00:01Z',
              'latency_ms': 540,
              'token_count': 120,
              'execution_summary': 'Executed diagnostic cycle',
              'latest_findings': 'Bearing friction detected on main drive cylinder.',
              'confidence_score': 92.5,
              'risk_level': 'HIGH',
              'provenance': 'GEMINI_LIVE_API',
            },
            'recent_executions': [],
          },
          {
            'agent_type': 'MAINTENANCE_COORDINATOR',
            'name': 'Maintenance Coordinator',
            'role': 'Industrial Repair Planning',
            'responsibilities': ['Estimate repair duration'],
            'model_name': 'deterministic-engine',
            'is_enabled': true,
            'permitted_actions': ['ESTIMATE_REPAIR'],
            'current_status': 'IDLE',
            'metrics': {
              'total_executions': 40,
              'completed_executions': 40,
              'failed_executions': 0,
              'avg_latency_ms': 120,
            },
            'latest_execution': null,
            'recent_executions': [],
          },
        ],
      };

      final model = AgentOperationsOverviewModel.fromJson(json);
      expect(model.overallMetrics.totalExecutions, 160);
      expect(model.overallMetrics.completedExecutions, 155);
      expect(model.workerHeartbeats.length, 2);
      expect(model.workerHeartbeats['AUTONOMOUS_ORCHESTRATOR']?.isRunning, true);
      expect(model.specialistAgents.length, 2);

      final agent1 = model.specialistAgents[0];
      expect(agent1.agentType, 'MACHINE_HEALTH');
      expect(agent1.currentStatus, 'COMPLETED');
      expect(agent1.latestExecution?.machineCode, 'WEV-AJ-02');
      expect(agent1.latestExecution?.provenance, 'GEMINI_LIVE_API');

      final agent2 = model.specialistAgents[1];
      expect(agent2.agentType, 'MAINTENANCE_COORDINATOR');
      expect(agent2.latestExecution, isNull);
    });

    test('IncidentWorkflowModel parses 12-stage pipeline correctly', () {
      final json = {
        'incident': {
          'id': 10,
          'incident_code': 'INC-20261012-0010',
          'machine_code': 'WEV-AJ-02',
          'machine_name': 'Toyota Air-Jet Loom #02',
          'department': 'Weaving',
          'severity': 'CRITICAL',
          'status': 'INVESTIGATING',
          'title': 'High Vibration Breach',
          'created_at': '2026-10-12T04:00:00Z',
        },
        'workflow_run_id': 'run-20261012-01',
        'current_stage': 'PRODUCTION_IMPACT_ANALYSIS',
        'recommended_strategy': 'STRATEGY_C',
        'approval_status': 'PENDING',
        'stages': [
          {
            'stage_index': 1,
            'stage_key': 'TELEMETRY_RECEIVED',
            'title': 'Telemetry Received',
            'component': 'IoT Edge Ingestion Simulator',
            'status': 'COMPLETED',
            'timestamp': '2026-10-12T04:00:00Z',
            'duration_ms': 5,
            'output_summary': 'Telemetry stream captured with 5.82 mm/s vibration',
            'evidence': {'reading_id': 554, 'vibration_mms': 5.82},
            'provenance': 'REAL_TIME_STREAM',
          },
          {
            'stage_index': 10,
            'stage_key': 'MANAGER_APPROVAL',
            'title': 'Manager Approval',
            'component': 'Approval Center',
            'status': 'WAITING_FOR_APPROVAL',
            'timestamp': null,
            'duration_ms': null,
            'output_summary': 'Manager gate required for dispatch',
            'evidence': {'approval_status': 'PENDING'},
            'provenance': 'SAFETY_GOVERNANCE',
          },
        ],
      };

      final model = IncidentWorkflowModel.fromJson(json);
      expect(model.incident['incident_code'], 'INC-20261012-0010');
      expect(model.currentStage, 'PRODUCTION_IMPACT_ANALYSIS');
      expect(model.stages.length, 2);
      expect(model.stages[0].isCompleted, true);
      expect(model.stages[1].isWaitingApproval, true);
      expect(model.stages[0].evidence['vibration_mms'], 5.82);
    });

    test('BusinessImpactModel parses financial metrics correctly', () {
      final json = {
        'incident': {'id': 10, 'code': 'INC-20261012-0010'},
        'kpis': {
          'recommended_strategy': 'STRATEGY_C',
          'recommended_strategy_name': 'Scheduled Maintenance & Reallocation',
          'potential_downtime_hours': 2.5,
          'production_output_loss': 180,
          'estimated_repair_cost_inr': 12500.0,
          'unmitigated_exposure_inr': 80500.0,
          'mitigated_exposure_inr': 32500.0,
          'net_financial_risk_avoided_inr': 48000.0,
        },
        'strategy_comparison': [
          {
            'strategy_code': 'STRATEGY_A',
            'strategy_name': 'Autonomous Speed Reduction',
            'rank': 2,
            'is_feasible': true,
            'effectiveness_level': 'MODERATE',
            'estimated_downtime_hours': 0.0,
            'capacity_recovered_pct': 70.0,
            'estimated_output_loss': 350,
            'estimated_cost_inr': 2000.0,
            'cost_breakdown': {'labor': 500, 'spares': 1500},
            'pros': ['Zero downtime'],
            'cons': ['Reduced throughput'],
          },
          {
            'strategy_code': 'STRATEGY_C',
            'strategy_name': 'Scheduled Maintenance & Reallocation',
            'rank': 1,
            'is_feasible': true,
            'effectiveness_level': 'HIGH_EFFECTIVENESS',
            'estimated_downtime_hours': 2.5,
            'capacity_recovered_pct': 95.0,
            'estimated_output_loss': 180,
            'estimated_cost_inr': 12500.0,
            'cost_breakdown': {'labor': 3500, 'spares': 9000},
            'pros': ['Permanent repair'],
            'cons': ['Planned 2.5h downtime'],
          },
        ],
        'data_provenance': {
          'engine': 'DIGITAL_TWIN_SIMULATOR',
          'is_deterministic': true,
        },
      };

      final model = BusinessImpactModel.fromJson(json);
      expect(model.kpis.recommendedStrategy, 'STRATEGY_C');
      expect(model.kpis.netFinancialRiskAvoidedInr, 48000.0);
      expect(model.strategyComparison.length, 2);
      expect(model.strategyComparison[1].rank, 1);
    });
  });
}
