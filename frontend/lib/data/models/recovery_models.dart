class RecoveryPlanStepModel {
  final int id;
  final int stepOrder;
  final String title;
  final String description;
  final String agentType;
  final String actionType;
  final String status;
  final List<dynamic> dependencies;
  final int? approvalId;
  final String? approvalCode;
  final String? approvalStatus;
  final String? approvalTitle;
  final String? actionStatus;
  final Map<String, dynamic> actionPayload;
  final Map<String, dynamic> outputPayload;
  final String? completedAt;

  RecoveryPlanStepModel({
    required this.id,
    required this.stepOrder,
    required this.title,
    required this.description,
    required this.agentType,
    required this.actionType,
    required this.status,
    required this.dependencies,
    this.approvalId,
    this.approvalCode,
    this.approvalStatus,
    this.approvalTitle,
    this.actionStatus,
    required this.actionPayload,
    required this.outputPayload,
    this.completedAt,
  });

  factory RecoveryPlanStepModel.fromJson(Map<String, dynamic> json) {
    return RecoveryPlanStepModel(
      id: json['id'] ?? 0,
      stepOrder: json['step_order'] ?? 1,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      agentType: json['agent_type'] ?? 'MAINTENANCE',
      actionType: json['action_type'] ?? 'CREATE_MAINTENANCE_TICKET',
      status: json['status'] ?? 'PENDING_DEPENDENCY',
      dependencies: json['dependencies'] ?? [],
      approvalId: json['approval_id'],
      approvalCode: json['approval_code'],
      approvalStatus: json['approval_status'],
      approvalTitle: json['approval_title'],
      actionStatus: json['action_status'],
      actionPayload: json['action_payload'] is Map<String, dynamic> ? json['action_payload'] : {},
      outputPayload: json['output_payload'] is Map<String, dynamic> ? json['output_payload'] : {},
      completedAt: json['completed_at'],
    );
  }
}

class RecoveryCaseModel {
  final int id;
  final String caseCode;
  final int incidentId;
  final String incidentCode;
  final String incidentSeverity;
  final String incidentSummary;
  final int machineId;
  final String machineCode;
  final String machineName;
  final String departmentName;
  final String status;
  final String priority;
  final double priorityScore;
  final double targetResolutionHours;
  final double estimatedDowntimeHours;
  final Map<String, dynamic> healthDiagnosis;
  final Map<String, dynamic> maintenanceRecommendation;
  final Map<String, dynamic> inventoryAssessment;
  final Map<String, dynamic> productionImpactAssessment;
  final String summary;
  final int pendingApprovalsCount;
  final bool isAllStepsCompleted;
  final List<RecoveryPlanStepModel> steps;
  final String createdAt;
  final String updatedAt;
  final String? recoveredAt;

  RecoveryCaseModel({
    required this.id,
    required this.caseCode,
    required this.incidentId,
    required this.incidentCode,
    required this.incidentSeverity,
    required this.incidentSummary,
    required this.machineId,
    required this.machineCode,
    required this.machineName,
    required this.departmentName,
    required this.status,
    required this.priority,
    required this.priorityScore,
    required this.targetResolutionHours,
    required this.estimatedDowntimeHours,
    required this.healthDiagnosis,
    required this.maintenanceRecommendation,
    required this.inventoryAssessment,
    required this.productionImpactAssessment,
    required this.summary,
    required this.pendingApprovalsCount,
    required this.isAllStepsCompleted,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
    this.recoveredAt,
  });

  factory RecoveryCaseModel.fromJson(Map<String, dynamic> json) {
    var rawSteps = json['steps'] as List? ?? [];
    List<RecoveryPlanStepModel> stepsList = rawSteps
        .map((s) => RecoveryPlanStepModel.fromJson(s as Map<String, dynamic>))
        .toList();

    return RecoveryCaseModel(
      id: json['id'] ?? 0,
      caseCode: json['case_code'] ?? '',
      incidentId: json['incident'] ?? 0,
      incidentCode: json['incident_code'] ?? '',
      incidentSeverity: json['incident_severity'] ?? 'HIGH',
      incidentSummary: json['incident_summary'] ?? '',
      machineId: json['machine'] ?? 0,
      machineCode: json['machine_code'] ?? '',
      machineName: json['machine_name'] ?? '',
      departmentName: json['department_name'] ?? 'Operations',
      status: json['status'] ?? 'ANALYZING',
      priority: json['priority'] ?? 'HIGH',
      priorityScore: (json['priority_score'] != null)
          ? double.tryParse(json['priority_score'].toString()) ?? 80.0
          : 80.0,
      targetResolutionHours: (json['target_resolution_hours'] != null)
          ? double.tryParse(json['target_resolution_hours'].toString()) ?? 2.0
          : 2.0,
      estimatedDowntimeHours: (json['estimated_downtime_hours'] != null)
          ? double.tryParse(json['estimated_downtime_hours'].toString()) ?? 1.5
          : 1.5,
      healthDiagnosis: json['health_diagnosis'] is Map<String, dynamic> ? json['health_diagnosis'] : {},
      maintenanceRecommendation: json['maintenance_recommendation'] is Map<String, dynamic> ? json['maintenance_recommendation'] : {},
      inventoryAssessment: json['inventory_assessment'] is Map<String, dynamic> ? json['inventory_assessment'] : {},
      productionImpactAssessment: json['production_impact_assessment'] is Map<String, dynamic> ? json['production_impact_assessment'] : {},
      summary: json['summary'] ?? '',
      pendingApprovalsCount: json['pending_approvals_count'] ?? 0,
      isAllStepsCompleted: json['is_all_steps_completed'] ?? false,
      steps: stepsList,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      recoveredAt: json['recovered_at'],
    );
  }
}

class PendingApprovalModel {
  final int id;
  final String approvalCode;
  final String title;
  final String description;
  final String requestedAction;
  final String riskLevel;
  final String requestedByAgent;
  final String incidentCode;
  final String machineCode;
  final String createdAt;
  final Map<String, dynamic> payload;

  PendingApprovalModel({
    required this.id,
    required this.approvalCode,
    required this.title,
    required this.description,
    required this.requestedAction,
    required this.riskLevel,
    required this.requestedByAgent,
    required this.incidentCode,
    required this.machineCode,
    required this.createdAt,
    required this.payload,
  });

  factory PendingApprovalModel.fromJson(Map<String, dynamic> json) {
    return PendingApprovalModel(
      id: json['id'] ?? 0,
      approvalCode: json['approval_code'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      requestedAction: json['requested_action'] ?? '',
      riskLevel: json['risk_level'] ?? 'MEDIUM',
      requestedByAgent: json['requested_by_agent'] ?? 'AI Agent',
      incidentCode: json['incident_code'] ?? '',
      machineCode: json['machine_code'] ?? '',
      createdAt: json['created_at'] ?? '',
      payload: json['payload'] is Map<String, dynamic> ? json['payload'] : {},
    );
  }
}

class RecoverySummaryModel {
  final int totalCases;
  final int activeCases;
  final int awaitingApprovals;
  final int inRecovery;
  final int recoveredCases;
  final int criticalCases;
  final int pendingApprovalsTotal;
  final int reservedSparesCount;
  final List<RecoveryCaseModel> recentCases;
  final List<PendingApprovalModel> pendingApprovals;

  RecoverySummaryModel({
    required this.totalCases,
    required this.activeCases,
    required this.awaitingApprovals,
    required this.inRecovery,
    required this.recoveredCases,
    required this.criticalCases,
    required this.pendingApprovalsTotal,
    required this.reservedSparesCount,
    required this.recentCases,
    required this.pendingApprovals,
  });

  factory RecoverySummaryModel.fromJson(Map<String, dynamic> json) {
    var metrics = json['metrics'] as Map<String, dynamic>? ?? {};
    var rawCases = json['recent_cases'] as List? ?? [];
    var rawApprovals = json['pending_approvals'] as List? ?? [];

    return RecoverySummaryModel(
      totalCases: metrics['total_cases'] ?? 0,
      activeCases: metrics['active_cases'] ?? 0,
      awaitingApprovals: metrics['awaiting_approvals'] ?? 0,
      inRecovery: metrics['in_recovery'] ?? 0,
      recoveredCases: metrics['recovered_cases'] ?? 0,
      criticalCases: metrics['critical_cases'] ?? 0,
      pendingApprovalsTotal: metrics['pending_approvals_total'] ?? 0,
      reservedSparesCount: metrics['reserved_spares_count'] ?? 0,
      recentCases: rawCases.map((c) => RecoveryCaseModel.fromJson(c as Map<String, dynamic>)).toList(),
      pendingApprovals: rawApprovals.map((a) => PendingApprovalModel.fromJson(a as Map<String, dynamic>)).toList(),
    );
  }
}
