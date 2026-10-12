import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/digital_twin_models.dart';

void main() {
  test('DigitalTwinSnapshotModel and MachineTwinModel parsing test', () {
    final rawSnapshot = {
      'snapshot_id': 'TWIN-20261009-TEST',
      'factory_code': 'FAC-01',
      'captured_at': '2026-10-09T10:00:00Z',
      'total_machines': 25,
      'operational_summary': {
        'factory_name': 'Texora Smart Textile Mill #1',
        'is_simulated_twin': true,
        'state_distribution': {'RUNNING': 24, 'CRITICAL': 1},
      },
      'machine_states': [
        {
          'id': 2,
          'code': 'WEV-AJ-02',
          'name': 'Air Jet Loom #02',
          'category': 'WEAVING',
          'department_code': 'WEV',
          'department_name': 'Weaving Shed',
          'twin_presentation_state': 'CRITICAL',
          'state_reason': 'Active Critical Incident on Main Drive Shaft',
          'health_score': 68.5,
          'rated_capacity_units_per_hour': 48.0,
          'compatible_alternates': ['WEV-AJ-01', 'WEV-AJ-03', 'WEV-AJ-04'],
        }
      ],
    };

    final snapshot = DigitalTwinSnapshotModel.fromJson(rawSnapshot);
    expect(snapshot.snapshotId, 'TWIN-20261009-TEST');
    expect(snapshot.totalMachines, 25);
    expect(snapshot.machineStates.length, 1);

    final loom = snapshot.machineStates.first;
    expect(loom.code, 'WEV-AJ-02');
    expect(loom.twinPresentationState, 'CRITICAL');
    expect(loom.healthScore, 68.5);
    expect(loom.compatibleAlternates, contains('WEV-AJ-01'));
  });

  test('WhatIfScenarioModel and RecoveryStrategyEvaluationModel parsing test', () {
    final rawScenario = {
      'id': 1,
      'scenario_id': 'SCEN-TEST-001',
      'name': 'Demo A - Single Loom Failure',
      'description': 'Test scenario',
      'scenario_type': 'SINGLE_MACHINE_FAILURE',
      'failure_duration_hours': 4.0,
      'repair_duration_hours': 2.5,
      'capacity_reduction_pct': 100.0,
      'spare_parts_availability': 'FULL',
      'technicians_available': 2,
      'latest_run': {
        'id': 10,
        'run_id': '11111111-2222-3333-4444-555555555555',
        'status': 'COMPLETED',
        'execution_duration_ms': 15,
        'result': {
          'id': 5,
          'lost_machine_operating_hours': 4.0,
          'capacity_reduction_pct': 8.33,
          'bottleneck_department': 'WEV',
          'estimated_output_loss': {'METERS': 120.0, 'KG': 0.0},
        },
        'strategy_evaluations': [
          {
            'id': 1,
            'strategy_code': 'STRATEGY_C',
            'strategy_name': 'Strategy C - Hybrid Prioritized Repair & Rerouting',
            'is_feasible': true,
            'estimated_downtime_hours': 2.5,
            'capacity_recovered_pct': 100.0,
            'rank': 1,
            'pros': ['Lowest net loss'],
            'cons': ['Coordination required'],
          }
        ],
      },
    };

    final scenario = WhatIfScenarioModel.fromJson(rawScenario);
    expect(scenario.scenarioId, 'SCEN-TEST-001');
    expect(scenario.latestRun, isNotNull);
    expect(scenario.latestRun!.result!.lostMachineOperatingHours, 4.0);
    expect(scenario.latestRun!.result!.bottleneckDepartment, 'WEV');
    expect(scenario.latestRun!.strategyEvaluations.length, 1);

    final topStrat = scenario.latestRun!.strategyEvaluations.first;
    expect(topStrat.strategyCode, 'STRATEGY_C');
    expect(topStrat.rank, 1);
    expect(topStrat.isFeasible, true);
    expect(topStrat.estimatedDowntimeHours, 2.5);
  });
}
