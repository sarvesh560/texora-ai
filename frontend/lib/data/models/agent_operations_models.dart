class AgentOperationsOverviewModel {
  final Map<String, WorkerHeartbeatModel> workerHeartbeats;
  final AgentOverallMetricsModel overallMetrics;
  final List<SpecialistAgentModel> specialistAgents;

  AgentOperationsOverviewModel({
    required this.workerHeartbeats,
    required this.overallMetrics,
    required this.specialistAgents,
  });

  factory AgentOperationsOverviewModel.fromJson(Map<String, dynamic> json) {
    final heartbeats = <String, WorkerHeartbeatModel>{};
    final rawH = json['worker_heartbeats'] as Map<String, dynamic>? ?? {};
    rawH.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        heartbeats[k] = WorkerHeartbeatModel.fromJson(v);
      }
    });

    final metrics = AgentOverallMetricsModel.fromJson(
        json['overall_metrics'] as Map<String, dynamic>? ?? {});

    final rawAgents = json['specialist_agents'] as List<dynamic>? ?? [];
    final agents = rawAgents
        .map((a) => SpecialistAgentModel.fromJson(a as Map<String, dynamic>))
        .toList();

    return AgentOperationsOverviewModel(
      workerHeartbeats: heartbeats,
      overallMetrics: metrics,
      specialistAgents: agents,
    );
  }
}

class WorkerHeartbeatModel {
  final String workerName;
  final String status;
  final int processId;
  final String? lastHeartbeatAt;
  final int processingCount;
  final String lastError;

  WorkerHeartbeatModel({
    required this.workerName,
    required this.status,
    required this.processId,
    this.lastHeartbeatAt,
    required this.processingCount,
    required this.lastError,
  });

  bool get isRunning => status == 'RUNNING';

  factory WorkerHeartbeatModel.fromJson(Map<String, dynamic> json) {
    return WorkerHeartbeatModel(
      workerName: json['worker_name'] as String? ?? 'WORKER',
      status: json['status'] as String? ?? 'STOPPED',
      processId: json['process_id'] as int? ?? 0,
      lastHeartbeatAt: json['last_heartbeat_at'] as String?,
      processingCount: json['processing_count'] as int? ?? 0,
      lastError: json['last_error'] as String? ?? '',
    );
  }
}

class AgentOverallMetricsModel {
  final int totalExecutions;
  final int completedExecutions;
  final int failedExecutions;
  final int activeIncidents;
  final int pendingApprovals;

  AgentOverallMetricsModel({
    required this.totalExecutions,
    required this.completedExecutions,
    required this.failedExecutions,
    required this.activeIncidents,
    required this.pendingApprovals,
  });

  factory AgentOverallMetricsModel.fromJson(Map<String, dynamic> json) {
    return AgentOverallMetricsModel(
      totalExecutions: json['total_executions'] as int? ?? 0,
      completedExecutions: json['completed_executions'] as int? ?? 0,
      failedExecutions: json['failed_executions'] as int? ?? 0,
      activeIncidents: json['active_incidents'] as int? ?? 0,
      pendingApprovals: json['pending_approvals'] as int? ?? 0,
    );
  }
}

class SpecialistAgentModel {
  final String agentType;
  final String name;
  final String role;
  final List<String> responsibilities;
  final String modelName;
  final bool isEnabled;
  final List<String> permittedActions;
  final String currentStatus; // IDLE, QUEUED, RUNNING, COMPLETED, FAILED, WAITING_FOR_DEPENDENCY, WAITING_FOR_APPROVAL
  final SpecialistAgentMetricsModel metrics;
  final AgentLatestExecutionModel? latestExecution;
  final List<AgentRecentExecutionSummaryModel> recentExecutions;

  SpecialistAgentModel({
    required this.agentType,
    required this.name,
    required this.role,
    required this.responsibilities,
    required this.modelName,
    required this.isEnabled,
    required this.permittedActions,
    required this.currentStatus,
    required this.metrics,
    this.latestExecution,
    required this.recentExecutions,
  });

  factory SpecialistAgentModel.fromJson(Map<String, dynamic> json) {
    final rawResp = json['responsibilities'] as List<dynamic>? ?? [];
    final responsibilities = rawResp.map((e) => e.toString()).toList();

    final rawActs = json['permitted_actions'] as List<dynamic>? ?? [];
    final permittedActions = rawActs.map((e) => e.toString()).toList();

    final rawRecent = json['recent_executions'] as List<dynamic>? ?? [];
    final recent = rawRecent
        .map((e) =>
            AgentRecentExecutionSummaryModel.fromJson(e as Map<String, dynamic>))
        .toList();

    return SpecialistAgentModel(
      agentType: json['agent_type'] as String? ?? 'SPECIALIST',
      name: json['name'] as String? ?? 'Specialist Agent',
      role: json['role'] as String? ?? 'Autonomous Specialist',
      responsibilities: responsibilities,
      modelName: json['model_name'] as String? ?? 'deterministic-engine',
      isEnabled: json['is_enabled'] as bool? ?? true,
      permittedActions: permittedActions,
      currentStatus: json['current_status'] as String? ?? 'IDLE',
      metrics: SpecialistAgentMetricsModel.fromJson(
          json['metrics'] as Map<String, dynamic>? ?? {}),
      latestExecution: json['latest_execution'] != null
          ? AgentLatestExecutionModel.fromJson(
              json['latest_execution'] as Map<String, dynamic>)
          : null,
      recentExecutions: recent,
    );
  }
}

class SpecialistAgentMetricsModel {
  final int totalExecutions;
  final int completedExecutions;
  final int failedExecutions;
  final int avgLatencyMs;

  SpecialistAgentMetricsModel({
    required this.totalExecutions,
    required this.completedExecutions,
    required this.failedExecutions,
    required this.avgLatencyMs,
  });

  factory SpecialistAgentMetricsModel.fromJson(Map<String, dynamic> json) {
    return SpecialistAgentMetricsModel(
      totalExecutions: json['total_executions'] as int? ?? 0,
      completedExecutions: json['completed_executions'] as int? ?? 0,
      failedExecutions: json['failed_executions'] as int? ?? 0,
      avgLatencyMs: json['avg_latency_ms'] as int? ?? 0,
    );
  }
}

class AgentLatestExecutionModel {
  final String executionId;
  final int id;
  final int? incidentId;
  final String incidentCode;
  final String machineCode;
  final String machineName;
  final String departmentName;
  final String triggerEvent;
  final String status;
  final String? startedAt;
  final String? completedAt;
  final int latencyMs;
  final int tokenCount;
  final String executionSummary;
  final String latestFindings;
  final double confidenceScore;
  final String riskLevel;
  final Map<String, dynamic>? recommendedAction;
  final String provenance;

  AgentLatestExecutionModel({
    required this.executionId,
    required this.id,
    this.incidentId,
    required this.incidentCode,
    required this.machineCode,
    required this.machineName,
    required this.departmentName,
    required this.triggerEvent,
    required this.status,
    this.startedAt,
    this.completedAt,
    required this.latencyMs,
    required this.tokenCount,
    required this.executionSummary,
    required this.latestFindings,
    required this.confidenceScore,
    required this.riskLevel,
    this.recommendedAction,
    required this.provenance,
  });

  factory AgentLatestExecutionModel.fromJson(Map<String, dynamic> json) {
    return AgentLatestExecutionModel(
      executionId: json['execution_id'] as String? ?? '',
      id: json['id'] as int? ?? 0,
      incidentId: json['incident_id'] as int?,
      incidentCode: json['incident_code'] as String? ?? 'N/A',
      machineCode: json['machine_code'] as String? ?? 'N/A',
      machineName: json['machine_name'] as String? ?? 'N/A',
      departmentName: json['department_name'] as String? ?? 'N/A',
      triggerEvent: json['trigger_event'] as String? ?? '',
      status: json['status'] as String? ?? 'IDLE',
      startedAt: json['started_at'] as String?,
      completedAt: json['completed_at'] as String?,
      latencyMs: json['latency_ms'] as int? ?? 0,
      tokenCount: json['token_count'] as int? ?? 0,
      executionSummary: json['execution_summary'] as String? ?? '',
      latestFindings: json['latest_findings'] as String? ?? '',
      confidenceScore: (json['confidence_score'] is num)
          ? (json['confidence_score'] as num).toDouble()
          : 90.0,
      riskLevel: json['risk_level'] as String? ?? 'LOW',
      recommendedAction: json['recommended_action'] as Map<String, dynamic>?,
      provenance: json['provenance'] as String? ?? 'Deterministic Engine',
    );
  }
}

class AgentRecentExecutionSummaryModel {
  final String executionId;
  final int id;
  final String incidentCode;
  final String machineCode;
  final String status;
  final String? startedAt;
  final int latencyMs;
  final String summary;

  AgentRecentExecutionSummaryModel({
    required this.executionId,
    required this.id,
    required this.incidentCode,
    required this.machineCode,
    required this.status,
    this.startedAt,
    required this.latencyMs,
    required this.summary,
  });

  factory AgentRecentExecutionSummaryModel.fromJson(Map<String, dynamic> json) {
    return AgentRecentExecutionSummaryModel(
      executionId: json['execution_id'] as String? ?? '',
      id: json['id'] as int? ?? 0,
      incidentCode: json['incident_code'] as String? ?? 'N/A',
      machineCode: json['machine_code'] as String? ?? 'N/A',
      status: json['status'] as String? ?? 'COMPLETED',
      startedAt: json['started_at'] as String?,
      latencyMs: json['latency_ms'] as int? ?? 0,
      summary: json['summary'] as String? ?? '',
    );
  }
}
