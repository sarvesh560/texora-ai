class IncidentWorkflowModel {
  final Map<String, dynamic> incident;
  final String? workflowRunId;
  final String currentStage;
  final String? recommendedStrategy;
  final String approvalStatus;
  final List<WorkflowStageModel> stages;

  IncidentWorkflowModel({
    required this.incident,
    this.workflowRunId,
    required this.currentStage,
    this.recommendedStrategy,
    required this.approvalStatus,
    required this.stages,
  });

  factory IncidentWorkflowModel.fromJson(Map<String, dynamic> json) {
    final inc = json['incident'] as Map<String, dynamic>? ?? {};
    final rawStages = json['stages'] as List<dynamic>? ?? [];
    final stages = rawStages
        .map((s) => WorkflowStageModel.fromJson(s as Map<String, dynamic>))
        .toList();

    return IncidentWorkflowModel(
      incident: inc,
      workflowRunId: json['workflow_run_id'] as String?,
      currentStage: json['current_stage'] as String? ?? 'NEW_INCIDENT',
      recommendedStrategy: json['recommended_strategy'] as String?,
      approvalStatus: json['approval_status'] as String? ?? 'NOT_REQUESTED',
      stages: stages,
    );
  }
}

class WorkflowStageModel {
  final int stageIndex;
  final String stageKey;
  final String title;
  final String component;
  final String status; // NOT_STARTED, PENDING, RUNNING, COMPLETED, FAILED, BLOCKED, SKIPPED, WAITING_FOR_APPROVAL
  final String? timestamp;
  final int? durationMs;
  final String outputSummary;
  final Map<String, dynamic> evidence;
  final String provenance;
  final String? errorReason;
  final Map<String, dynamic>? databaseRecord;

  WorkflowStageModel({
    required this.stageIndex,
    required this.stageKey,
    required this.title,
    required this.component,
    required this.status,
    this.timestamp,
    this.durationMs,
    required this.outputSummary,
    required this.evidence,
    required this.provenance,
    this.errorReason,
    this.databaseRecord,
  });

  bool get isCompleted => status == 'COMPLETED';
  bool get isRunning => status == 'RUNNING';
  bool get isWaitingApproval => status == 'WAITING_FOR_APPROVAL';
  bool get isFailed => status == 'FAILED';
  bool get isBlocked => status == 'BLOCKED';
  bool get isSkipped => status == 'SKIPPED';
  bool get isPending => status == 'PENDING';
  bool get isNotStarted => status == 'NOT_STARTED';

  factory WorkflowStageModel.fromJson(Map<String, dynamic> json) {
    return WorkflowStageModel(
      stageIndex: json['stage_index'] as int? ?? 1,
      stageKey: json['stage_key'] as String? ?? '',
      title: json['title'] as String? ?? 'Stage',
      component: json['component'] as String? ?? 'Orchestrator',
      status: json['status'] as String? ?? 'NOT_STARTED',
      timestamp: json['timestamp'] as String?,
      durationMs: json['duration_ms'] as int?,
      outputSummary: json['output_summary'] as String? ?? '',
      evidence: json['evidence'] as Map<String, dynamic>? ?? {},
      provenance: json['provenance'] as String? ?? '',
      errorReason: json['error_reason'] as String?,
      databaseRecord: json['database_record'] as Map<String, dynamic>?,
    );
  }
}

class BusinessImpactModel {
  final Map<String, dynamic> incident;
  final BusinessImpactKpisModel kpis;
  final List<StrategyComparisonModel> strategyComparison;
  final Map<String, dynamic> dataProvenance;

  BusinessImpactModel({
    required this.incident,
    required this.kpis,
    required this.strategyComparison,
    required this.dataProvenance,
  });

  factory BusinessImpactModel.fromJson(Map<String, dynamic> json) {
    final inc = json['incident'] as Map<String, dynamic>? ?? {};
    final kpis = BusinessImpactKpisModel.fromJson(
        json['kpis'] as Map<String, dynamic>? ?? {});
    final rawStrat = json['strategy_comparison'] as List<dynamic>? ?? [];
    final strats = rawStrat
        .map((s) => StrategyComparisonModel.fromJson(s as Map<String, dynamic>))
        .toList();
    final prov = json['data_provenance'] as Map<String, dynamic>? ?? {};

    return BusinessImpactModel(
      incident: inc,
      kpis: kpis,
      strategyComparison: strats,
      dataProvenance: prov,
    );
  }
}

class BusinessImpactKpisModel {
  final String recommendedStrategy;
  final String recommendedStrategyName;
  final double potentialDowntimeHours;
  final dynamic productionOutputLoss;
  final double estimatedRepairCostInr;
  final double unmitigatedExposureInr;
  final double mitigatedExposureInr;
  final double netFinancialRiskAvoidedInr;

  BusinessImpactKpisModel({
    required this.recommendedStrategy,
    required this.recommendedStrategyName,
    required this.potentialDowntimeHours,
    required this.productionOutputLoss,
    required this.estimatedRepairCostInr,
    required this.unmitigatedExposureInr,
    required this.mitigatedExposureInr,
    required this.netFinancialRiskAvoidedInr,
  });

  factory BusinessImpactKpisModel.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    return BusinessImpactKpisModel(
      recommendedStrategy: json['recommended_strategy'] as String? ?? 'STRATEGY_A',
      recommendedStrategyName: json['recommended_strategy_name'] as String? ?? 'Strategy A',
      potentialDowntimeHours: toDouble(json['potential_downtime_hours']),
      productionOutputLoss: json['production_output_loss'] ?? 0,
      estimatedRepairCostInr: toDouble(json['estimated_repair_cost_inr']),
      unmitigatedExposureInr: toDouble(json['unmitigated_exposure_inr']),
      mitigatedExposureInr: toDouble(json['mitigated_exposure_inr']),
      netFinancialRiskAvoidedInr: toDouble(json['net_financial_risk_avoided_inr']),
    );
  }
}

class StrategyComparisonModel {
  final String strategyCode;
  final String strategyName;
  final int rank;
  final bool isFeasible;
  final String effectivenessLevel;
  final double estimatedDowntimeHours;
  final double capacityRecoveredPct;
  final dynamic estimatedOutputLoss;
  final double estimatedCostInr;
  final Map<String, dynamic> costBreakdown;
  final List<String> pros;
  final List<String> cons;

  StrategyComparisonModel({
    required this.strategyCode,
    required this.strategyName,
    required this.rank,
    required this.isFeasible,
    required this.effectivenessLevel,
    required this.estimatedDowntimeHours,
    required this.capacityRecoveredPct,
    required this.estimatedOutputLoss,
    required this.estimatedCostInr,
    required this.costBreakdown,
    required this.pros,
    required this.cons,
  });

  factory StrategyComparisonModel.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    final rawPros = json['pros'] as List<dynamic>? ?? [];
    final pros = rawPros.map((e) => e.toString()).toList();

    final rawCons = json['cons'] as List<dynamic>? ?? [];
    final cons = rawCons.map((e) => e.toString()).toList();

    return StrategyComparisonModel(
      strategyCode: json['strategy_code'] as String? ?? '',
      strategyName: json['strategy_name'] as String? ?? '',
      rank: json['rank'] as int? ?? 1,
      isFeasible: json['is_feasible'] as bool? ?? true,
      effectivenessLevel: json['effectiveness_level'] as String? ?? 'HIGH_EFFECTIVENESS',
      estimatedDowntimeHours: toDouble(json['estimated_downtime_hours']),
      capacityRecoveredPct: toDouble(json['capacity_recovered_pct']),
      estimatedOutputLoss: json['estimated_output_loss'] ?? 0,
      estimatedCostInr: toDouble(json['estimated_cost_inr']),
      costBreakdown: json['cost_breakdown'] as Map<String, dynamic>? ?? {},
      pros: pros,
      cons: cons,
    );
  }
}
