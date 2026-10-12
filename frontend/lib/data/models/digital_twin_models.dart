class DigitalTwinSnapshotModel {
  final String snapshotId;
  final String factoryCode;
  final String capturedAt;
  final int totalMachines;
  final Map<String, dynamic> operationalSummary;
  final List<MachineTwinModel> machineStates;

  DigitalTwinSnapshotModel({
    required this.snapshotId,
    required this.factoryCode,
    required this.capturedAt,
    required this.totalMachines,
    required this.operationalSummary,
    required this.machineStates,
  });

  factory DigitalTwinSnapshotModel.fromJson(Map<String, dynamic> json) {
    var rawMachines = json['machine_states'] as List? ?? [];
    List<MachineTwinModel> machines = rawMachines
        .map((m) => MachineTwinModel.fromJson(m as Map<String, dynamic>))
        .toList();

    return DigitalTwinSnapshotModel(
      snapshotId: json['snapshot_id'] ?? 'TWIN-UNKNOWN',
      factoryCode: json['factory_code'] ?? 'FAC-01',
      capturedAt: json['captured_at'] ?? '',
      totalMachines: json['total_machines'] ?? machines.length,
      operationalSummary: json['operational_summary'] as Map<String, dynamic>? ?? {},
      machineStates: machines,
    );
  }
}

class MachineTwinModel {
  final int id;
  final String code;
  final String name;
  final String machineTypeName;
  final String category;
  final String departmentCode;
  final String departmentName;
  final String floorLocation;
  final String rawStatus;
  final String twinPresentationState; // RUNNING, WARNING, CRITICAL, IDLE, UNDER_MAINTENANCE, OFFLINE, UNKNOWN
  final String stateReason;
  final double healthScore;
  final double ratedCapacityUnitsPerHour;
  final int ratedSpeedRpm;
  final Map<String, dynamic>? latestTelemetry;
  final Map<String, dynamic>? telemetryFreshness;
  final Map<String, dynamic>? operatingLimits;
  final List<dynamic> activeIncidents;
  final List<dynamic> activeTickets;
  final Map<String, dynamic>? activeRecovery;
  final Map<String, dynamic>? productionAssignment;
  final List<String> compatibleAlternates;
  final String provenanceType;
  final bool isBaselineIncident;

  MachineTwinModel({
    required this.id,
    required this.code,
    required this.name,
    required this.machineTypeName,
    required this.category,
    required this.departmentCode,
    required this.departmentName,
    required this.floorLocation,
    required this.rawStatus,
    required this.twinPresentationState,
    required this.stateReason,
    required this.healthScore,
    required this.ratedCapacityUnitsPerHour,
    required this.ratedSpeedRpm,
    this.latestTelemetry,
    this.telemetryFreshness,
    this.operatingLimits,
    required this.activeIncidents,
    required this.activeTickets,
    this.activeRecovery,
    this.productionAssignment,
    this.compatibleAlternates = const [],
    this.provenanceType = 'NOMINAL_OPERATION',
    this.isBaselineIncident = false,
  });

  bool get isStale => telemetryFreshness?['is_stale'] == true || twinPresentationState == 'UNKNOWN';

  factory MachineTwinModel.fromJson(Map<String, dynamic> json) {
    var alternates = (json['compatible_alternates'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return MachineTwinModel(
      id: json['id'] ?? 0,
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      machineTypeName: json['machine_type_name'] ?? 'Textile Machine',
      category: json['category'] ?? 'SPINNING',
      departmentCode: json['department_code'] ?? 'SPN',
      departmentName: json['department_name'] ?? 'Spinning',
      floorLocation: json['floor_location'] ?? 'Bay A',
      rawStatus: json['raw_status'] ?? 'OPERATIONAL',
      twinPresentationState: json['twin_presentation_state'] ?? 'UNKNOWN',
      stateReason: json['state_reason'] ?? 'Nominal',
      healthScore: (json['health_score'] as num?)?.toDouble() ?? 100.0,
      ratedCapacityUnitsPerHour: (json['rated_capacity_units_per_hour'] as num?)?.toDouble() ?? 50.0,
      ratedSpeedRpm: (json['rated_speed_rpm'] as num?)?.toInt() ?? 1000,
      latestTelemetry: json['latest_telemetry'] as Map<String, dynamic>?,
      telemetryFreshness: json['telemetry_freshness'] as Map<String, dynamic>?,
      operatingLimits: json['operating_limits'] as Map<String, dynamic>?,
      activeIncidents: json['active_incidents'] as List? ?? [],
      activeTickets: json['active_tickets'] as List? ?? [],
      activeRecovery: json['active_recovery'] as Map<String, dynamic>?,
      productionAssignment: json['production_assignment'] as Map<String, dynamic>?,
      compatibleAlternates: alternates,
      provenanceType: json['provenance_type'] ?? 'NOMINAL_OPERATION',
      isBaselineIncident: json['is_baseline_incident'] ?? false,
    );
  }
}

class WhatIfScenarioModel {
  final int id;
  final String scenarioId;
  final String name;
  final String description;
  final String scenarioType;
  final double failureDurationHours;
  final double repairDurationHours;
  final double capacityReductionPct;
  final String sparePartsAvailability;
  final int techniciansAvailable;
  final double demandVariationPct;
  final double shiftDurationHours;
  final String selectedStrategy;
  final bool isDemoScenario;
  final String demoCode;
  final List<dynamic> machineChanges;
  final SimulationRunModel? latestRun;

  WhatIfScenarioModel({
    required this.id,
    required this.scenarioId,
    required this.name,
    required this.description,
    required this.scenarioType,
    required this.failureDurationHours,
    required this.repairDurationHours,
    required this.capacityReductionPct,
    required this.sparePartsAvailability,
    required this.techniciansAvailable,
    required this.demandVariationPct,
    required this.shiftDurationHours,
    required this.selectedStrategy,
    required this.isDemoScenario,
    required this.demoCode,
    required this.machineChanges,
    this.latestRun,
  });

  factory WhatIfScenarioModel.fromJson(Map<String, dynamic> json) {
    return WhatIfScenarioModel(
      id: json['id'] ?? 0,
      scenarioId: json['scenario_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      scenarioType: json['scenario_type'] ?? 'SINGLE_MACHINE_FAILURE',
      failureDurationHours: (json['failure_duration_hours'] as num?)?.toDouble() ?? 4.0,
      repairDurationHours: (json['repair_duration_hours'] as num?)?.toDouble() ?? 3.0,
      capacityReductionPct: (json['capacity_reduction_pct'] as num?)?.toDouble() ?? 100.0,
      sparePartsAvailability: json['spare_parts_availability'] ?? 'FULL',
      techniciansAvailable: (json['technicians_available'] as num?)?.toInt() ?? 2,
      demandVariationPct: (json['demand_variation_pct'] as num?)?.toDouble() ?? 0.0,
      shiftDurationHours: (json['shift_duration_hours'] as num?)?.toDouble() ?? 8.0,
      selectedStrategy: json['selected_strategy'] ?? 'ALL_COMPARISON',
      isDemoScenario: json['is_demo_scenario'] ?? false,
      demoCode: json['demo_code'] ?? '',
      machineChanges: json['machine_changes'] as List? ?? [],
      latestRun: json['latest_run'] != null
          ? SimulationRunModel.fromJson(json['latest_run'] as Map<String, dynamic>)
          : null,
    );
  }
}

class SimulationRunModel {
  final int id;
  final String runId;
  final String status;
  final String executedAt;
  final int executionDurationMs;
  final String errorMessage;
  final SimulationResultModel? result;
  final List<RecoveryStrategyEvaluationModel> strategyEvaluations;

  SimulationRunModel({
    required this.id,
    required this.runId,
    required this.status,
    required this.executedAt,
    required this.executionDurationMs,
    required this.errorMessage,
    this.result,
    required this.strategyEvaluations,
  });

  factory SimulationRunModel.fromJson(Map<String, dynamic> json) {
    var rawEvals = json['strategy_evaluations'] as List? ?? [];
    List<RecoveryStrategyEvaluationModel> evals = rawEvals
        .map((e) => RecoveryStrategyEvaluationModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return SimulationRunModel(
      id: json['id'] ?? 0,
      runId: json['run_id']?.toString() ?? '',
      status: json['status'] ?? 'COMPLETED',
      executedAt: json['executed_at'] ?? '',
      executionDurationMs: (json['execution_duration_ms'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message'] ?? '',
      result: json['result'] != null
          ? SimulationResultModel.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      strategyEvaluations: evals,
    );
  }
}

class SimulationResultModel {
  final int id;
  final Map<String, dynamic> baselineCapacityPerHour;
  final Map<String, dynamic> simulatedCapacityPerHour;
  final double lostMachineOperatingHours;
  final double capacityReductionPct;
  final Map<String, dynamic> estimatedOutputLoss;
  final List<dynamic> potentialOrderDelays;
  final String bottleneckDepartment;
  final List<dynamic> alternativeMachineUtilization;
  final List<dynamic> timelineEvents;
  final Map<String, dynamic> dataProvenance;

  SimulationResultModel({
    required this.id,
    required this.baselineCapacityPerHour,
    required this.simulatedCapacityPerHour,
    required this.lostMachineOperatingHours,
    required this.capacityReductionPct,
    required this.estimatedOutputLoss,
    required this.potentialOrderDelays,
    required this.bottleneckDepartment,
    required this.alternativeMachineUtilization,
    required this.timelineEvents,
    required this.dataProvenance,
  });

  factory SimulationResultModel.fromJson(Map<String, dynamic> json) {
    return SimulationResultModel(
      id: json['id'] ?? 0,
      baselineCapacityPerHour: json['baseline_capacity_per_hour'] as Map<String, dynamic>? ?? {},
      simulatedCapacityPerHour: json['simulated_capacity_per_hour'] as Map<String, dynamic>? ?? {},
      lostMachineOperatingHours: (json['lost_machine_operating_hours'] as num?)?.toDouble() ?? 0.0,
      capacityReductionPct: (json['capacity_reduction_pct'] as num?)?.toDouble() ?? 0.0,
      estimatedOutputLoss: json['estimated_output_loss'] as Map<String, dynamic>? ?? {},
      potentialOrderDelays: json['potential_order_delays'] as List? ?? [],
      bottleneckDepartment: json['bottleneck_department'] ?? 'WEV',
      alternativeMachineUtilization: json['alternative_machine_utilization'] as List? ?? [],
      timelineEvents: json['timeline_events'] as List? ?? [],
      dataProvenance: json['data_provenance'] as Map<String, dynamic>? ?? {},
    );
  }
}

class RecoveryStrategyEvaluationModel {
  final int id;
  final String strategyCode;
  final String strategyName;
  final bool isFeasible;
  final String effectivenessLevel;
  final List<String> infeasibilityReasons;
  final double estimatedDowntimeHours;
  final double capacityRecoveredPct;
  final Map<String, dynamic> unmitigatedBaselineLoss;
  final Map<String, dynamic> estimatedOutputLoss;
  final Map<String, dynamic> volumeProtectedUnits;
  final double recoveryTimeHours;
  final Map<String, dynamic> resourceUtilization;
  final Map<String, dynamic> estimatedCost;
  final int rank;
  final bool isTied;
  final String tieBreakerNote;
  final List<String> pros;
  final List<String> cons;

  RecoveryStrategyEvaluationModel({
    required this.id,
    required this.strategyCode,
    required this.strategyName,
    required this.isFeasible,
    this.effectivenessLevel = 'HIGH_EFFECTIVENESS',
    required this.infeasibilityReasons,
    required this.estimatedDowntimeHours,
    required this.capacityRecoveredPct,
    this.unmitigatedBaselineLoss = const {},
    required this.estimatedOutputLoss,
    this.volumeProtectedUnits = const {},
    required this.recoveryTimeHours,
    required this.resourceUtilization,
    required this.estimatedCost,
    required this.rank,
    this.isTied = false,
    this.tieBreakerNote = '',
    required this.pros,
    required this.cons,
  });

  factory RecoveryStrategyEvaluationModel.fromJson(Map<String, dynamic> json) {
    return RecoveryStrategyEvaluationModel(
      id: json['id'] ?? 0,
      strategyCode: json['strategy_code'] ?? 'STRATEGY_A',
      strategyName: json['strategy_name'] ?? 'Strategy A',
      isFeasible: json['is_feasible'] ?? true,
      effectivenessLevel: json['effectiveness_level'] ?? (json['is_feasible'] == true ? 'HIGH_EFFECTIVENESS' : 'INFEASIBLE'),
      infeasibilityReasons: (json['infeasibility_reasons'] as List?)?.map((e) => e.toString()).toList() ?? [],
      estimatedDowntimeHours: (json['estimated_downtime_hours'] as num?)?.toDouble() ?? 0.0,
      capacityRecoveredPct: (json['capacity_recovered_pct'] as num?)?.toDouble() ?? 0.0,
      unmitigatedBaselineLoss: json['unmitigated_baseline_loss'] as Map<String, dynamic>? ?? {},
      estimatedOutputLoss: json['estimated_output_loss'] as Map<String, dynamic>? ?? {},
      volumeProtectedUnits: json['volume_protected_units'] as Map<String, dynamic>? ?? {},
      recoveryTimeHours: (json['recovery_time_hours'] as num?)?.toDouble() ?? 0.0,
      resourceUtilization: json['resource_utilization'] as Map<String, dynamic>? ?? {},
      estimatedCost: json['estimated_cost'] as Map<String, dynamic>? ?? {},
      rank: (json['rank'] as num?)?.toInt() ?? 1,
      isTied: json['is_tied'] ?? false,
      tieBreakerNote: json['tie_breaker_note'] ?? '',
      pros: (json['pros'] as List?)?.map((e) => e.toString()).toList() ?? [],
      cons: (json['cons'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class AIStrategyExplanationModel {
  final String executiveSummary;
  final String recommendedStrategyCode;
  final String recommendedStrategyTitle;
  final String recommendationRationale;
  final List<dynamic> alternativeStrategiesAssessment;
  final List<String> operationalRisks;
  final List<String> underlyingAssumptions;
  final bool isLiveGemini;
  final String provider;
  final String modelName;
  final int latencyMs;
  final String source;

  AIStrategyExplanationModel({
    required this.executiveSummary,
    required this.recommendedStrategyCode,
    required this.recommendedStrategyTitle,
    required this.recommendationRationale,
    required this.alternativeStrategiesAssessment,
    required this.operationalRisks,
    required this.underlyingAssumptions,
    required this.isLiveGemini,
    required this.provider,
    required this.modelName,
    required this.latencyMs,
    required this.source,
  });

  factory AIStrategyExplanationModel.fromJson(Map<String, dynamic> json) {
    return AIStrategyExplanationModel(
      executiveSummary: json['executive_summary'] ?? '',
      recommendedStrategyCode: json['recommended_strategy_code'] ?? 'STRATEGY_C',
      recommendedStrategyTitle: json['recommended_strategy_title'] ?? 'Hybrid Recovery',
      recommendationRationale: json['recommendation_rationale'] ?? '',
      alternativeStrategiesAssessment: json['alternative_strategies_assessment'] as List? ?? [],
      operationalRisks: (json['operational_risks'] as List?)?.map((e) => e.toString()).toList() ?? [],
      underlyingAssumptions: (json['underlying_assumptions'] as List?)?.map((e) => e.toString()).toList() ?? [],
      isLiveGemini: json['is_live_gemini'] ?? false,
      provider: json['provider'] ?? 'gemini',
      modelName: json['model_name'] ?? 'gemini-3.5-flash',
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      source: json['source'] ?? 'AI_INFERENCE',
    );
  }
}

class DemoScenarioModel {
  final String demoCode;
  final String title;
  final String targetMachine;
  final String department;
  final String description;
  final String failureDuration;
  final String repairDuration;
  final String spareParts;
  final int technicians;

  DemoScenarioModel({
    required this.demoCode,
    required this.title,
    required this.targetMachine,
    required this.department,
    required this.description,
    required this.failureDuration,
    required this.repairDuration,
    required this.spareParts,
    required this.technicians,
  });

  factory DemoScenarioModel.fromJson(Map<String, dynamic> json) {
    return DemoScenarioModel(
      demoCode: json['demo_code'] ?? '',
      title: json['title'] ?? '',
      targetMachine: json['target_machine'] ?? '',
      department: json['department'] ?? '',
      description: json['description'] ?? '',
      failureDuration: json['failure_duration'] ?? '',
      repairDuration: json['repair_duration'] ?? '',
      spareParts: json['spare_parts'] ?? 'FULL',
      technicians: (json['technicians'] as num?)?.toInt() ?? 2,
    );
  }
}
