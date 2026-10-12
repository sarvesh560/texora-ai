class AgentSummaryModel {
  final ProviderStatusModel providerStatus;
  final AgentMetricsModel metrics;
  final List<AgentPendingIncidentModel> pendingIncidents;
  final List<AgentExecutionModel> recentExecutions;

  AgentSummaryModel({
    required this.providerStatus,
    required this.metrics,
    required this.pendingIncidents,
    required this.recentExecutions,
  });

  factory AgentSummaryModel.fromJson(Map<String, dynamic> json) {
    final prov = ProviderStatusModel.fromJson(json['provider_status'] as Map<String, dynamic>? ?? {});
    final met = AgentMetricsModel.fromJson(json['metrics'] as Map<String, dynamic>? ?? {});

    final rawPending = json['pending_incidents_list'] as List<dynamic>? ?? [];
    final pending = rawPending.map((e) => AgentPendingIncidentModel.fromJson(e as Map<String, dynamic>)).toList();

    final rawExec = json['recent_executions'] as List<dynamic>? ?? [];
    final execs = rawExec.map((e) => AgentExecutionModel.fromJson(e as Map<String, dynamic>)).toList();

    return AgentSummaryModel(
      providerStatus: prov,
      metrics: met,
      pendingIncidents: pending,
      recentExecutions: execs,
    );
  }
}

class ProviderStatusModel {
  final String provider;
  final String model;
  final bool isConfigured;
  final String error;

  ProviderStatusModel({
    required this.provider,
    required this.model,
    required this.isConfigured,
    required this.error,
  });

  factory ProviderStatusModel.fromJson(Map<String, dynamic> json) {
    return ProviderStatusModel(
      provider: json['provider'] as String? ?? 'gemini',
      model: json['model'] as String? ?? 'gemini-2.5-flash',
      isConfigured: json['is_configured'] as bool? ?? false,
      error: json['error'] as String? ?? '',
    );
  }
}

class AgentMetricsModel {
  final int pendingIncidents;
  final int totalExecutions;
  final int completedExecutions;
  final int failedExecutions;
  final int pendingApprovals;

  AgentMetricsModel({
    required this.pendingIncidents,
    required this.totalExecutions,
    required this.completedExecutions,
    required this.failedExecutions,
    required this.pendingApprovals,
  });

  factory AgentMetricsModel.fromJson(Map<String, dynamic> json) {
    return AgentMetricsModel(
      pendingIncidents: json['pending_incidents'] as int? ?? 0,
      totalExecutions: json['total_executions'] as int? ?? 0,
      completedExecutions: json['completed_executions'] as int? ?? 0,
      failedExecutions: json['failed_executions'] as int? ?? 0,
      pendingApprovals: json['pending_approvals'] as int? ?? 0,
    );
  }
}

class AgentPendingIncidentModel {
  final int id;
  final String incidentCode;
  final String machineCode;
  final String machineName;
  final String departmentCode;
  final String severity;
  final String summary;
  final String detectedAt;

  AgentPendingIncidentModel({
    required this.id,
    required this.incidentCode,
    required this.machineCode,
    required this.machineName,
    required this.departmentCode,
    required this.severity,
    required this.summary,
    required this.detectedAt,
  });

  factory AgentPendingIncidentModel.fromJson(Map<String, dynamic> json) {
    return AgentPendingIncidentModel(
      id: json['id'] as int? ?? 0,
      incidentCode: json['incident_code'] as String? ?? '',
      machineCode: json['machine_code'] as String? ?? 'WEV-AJ-02',
      machineName: json['machine_name'] as String? ?? '',
      departmentCode: json['department_code'] as String? ?? 'WEV',
      severity: json['severity'] as String? ?? 'MEDIUM',
      summary: json['summary'] as String? ?? '',
      detectedAt: json['detected_at'] as String? ?? '',
    );
  }
}

class AgentExecutionModel {
  final String executionId;
  final String agentName;
  final String triggerEvent;
  final String status;
  final String executionSummary;
  final int tokenCount;
  final int latencyMs;
  final String startedAt;
  final List<AgentDecisionModel> decisions;
  final List<AgentActionModel> actions;
  final Map<String, dynamic> contextPayload;

  AgentExecutionModel({
    required this.executionId,
    required this.agentName,
    required this.triggerEvent,
    required this.status,
    required this.executionSummary,
    required this.tokenCount,
    required this.latencyMs,
    required this.startedAt,
    required this.decisions,
    required this.actions,
    required this.contextPayload,
  });

  factory AgentExecutionModel.fromJson(Map<String, dynamic> json) {
    final rawDec = json['decisions'] as List<dynamic>? ?? [];
    final decs = rawDec.map((e) => AgentDecisionModel.fromJson(e as Map<String, dynamic>)).toList();

    final rawAct = json['actions'] as List<dynamic>? ?? [];
    final acts = rawAct.map((e) => AgentActionModel.fromJson(e as Map<String, dynamic>)).toList();

    return AgentExecutionModel(
      executionId: json['execution_id'] as String? ?? '',
      agentName: json['agent_name'] as String? ?? 'Machine Health Specialist',
      triggerEvent: json['trigger_event'] as String? ?? '',
      status: json['status'] as String? ?? 'COMPLETED',
      executionSummary: json['execution_summary'] as String? ?? '',
      tokenCount: json['token_count'] as int? ?? 0,
      latencyMs: json['latency_ms'] as int? ?? 0,
      startedAt: json['started_at'] as String? ?? '',
      decisions: decs,
      actions: acts,
      contextPayload: json['context_payload'] as Map<String, dynamic>? ?? {},
    );
  }
}

class AgentDecisionModel {
  final int id;
  final String decisionType;
  final String decisionTypeDisplay;
  final String rationale;
  final double confidenceScore;
  final String riskLevel;
  final bool requiresHumanApproval;
  final String timestamp;

  AgentDecisionModel({
    required this.id,
    required this.decisionType,
    required this.decisionTypeDisplay,
    required this.rationale,
    required this.confidenceScore,
    required this.riskLevel,
    required this.requiresHumanApproval,
    required this.timestamp,
  });

  factory AgentDecisionModel.fromJson(Map<String, dynamic> json) {
    return AgentDecisionModel(
      id: json['id'] as int? ?? 0,
      decisionType: json['decision_type'] as String? ?? '',
      decisionTypeDisplay: json['decision_type_display'] as String? ?? 'Root Cause Diagnosis',
      rationale: json['rationale'] as String? ?? '',
      confidenceScore: (json['confidence_score'] is num
          ? (json['confidence_score'] as num).toDouble()
          : double.tryParse(json['confidence_score']?.toString() ?? '') ?? 90.0),
      riskLevel: json['risk_level'] as String? ?? 'LOW',
      requiresHumanApproval: json['requires_human_approval'] as bool? ?? false,
      timestamp: json['timestamp'] as String? ?? '',
    );
  }
}

class AgentActionModel {
  final int id;
  final String idempotencyKey;
  final String actionName;
  final String toolName;
  final String status;
  final Map<String, dynamic> toolInput;
  final Map<String, dynamic> toolOutput;

  AgentActionModel({
    required this.id,
    required this.idempotencyKey,
    required this.actionName,
    required this.toolName,
    required this.status,
    required this.toolInput,
    required this.toolOutput,
  });

  factory AgentActionModel.fromJson(Map<String, dynamic> json) {
    return AgentActionModel(
      id: json['id'] as int? ?? 0,
      idempotencyKey: json['idempotency_key'] as String? ?? '',
      actionName: json['action_name'] as String? ?? '',
      toolName: json['tool_name'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING_APPROVAL',
      toolInput: json['tool_input'] as Map<String, dynamic>? ?? {},
      toolOutput: json['tool_output'] as Map<String, dynamic>? ?? {},
    );
  }
}

class ApprovalRequestModel {
  final int id;
  final String approvalCode;
  final String title;
  final String description;
  final String requestedAction;
  final String riskLevel;
  final String status;
  final String requestedByAgent;
  final String approvedBy;
  final String responseNotes;
  final String createdAt;

  ApprovalRequestModel({
    required this.id,
    required this.approvalCode,
    required this.title,
    required this.description,
    required this.requestedAction,
    required this.riskLevel,
    required this.status,
    required this.requestedByAgent,
    required this.approvedBy,
    required this.responseNotes,
    required this.createdAt,
  });

  factory ApprovalRequestModel.fromJson(Map<String, dynamic> json) {
    return ApprovalRequestModel(
      id: json['id'] as int? ?? 0,
      approvalCode: json['approval_code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      requestedAction: json['requested_action'] as String? ?? '',
      riskLevel: json['risk_level'] as String? ?? 'MEDIUM',
      status: json['status'] as String? ?? 'PENDING',
      requestedByAgent: json['requested_by_agent'] as String? ?? 'Machine Health Specialist',
      approvedBy: json['approved_by'] as String? ?? '',
      responseNotes: json['response_notes'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
