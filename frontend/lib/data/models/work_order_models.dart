class ChecklistItem {
  final int stepId;
  final String task;
  String status; // PENDING, PASS, DEFECT_FOUND, SKIPPED
  final String expectedThreshold;
  String observedValue;
  String notes;

  ChecklistItem({
    required this.stepId,
    required this.task,
    this.status = 'PENDING',
    this.expectedThreshold = '',
    this.observedValue = '',
    this.notes = '',
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      stepId: json['step_id'] as int? ?? 1,
      task: json['task'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      expectedThreshold: json['expected_threshold'] as String? ?? '',
      observedValue: json['observed_value'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'step_id': stepId,
      'task': task,
      'status': status,
      'expected_threshold': expectedThreshold,
      'observed_value': observedValue,
      'notes': notes,
    };
  }
}

class WorkOrderTransitionItem {
  final int id;
  final String actor;
  final String actorRole;
  final String previousState;
  final String newState;
  final String reason;
  final DateTime timestamp;

  WorkOrderTransitionItem({
    required this.id,
    required this.actor,
    required this.actorRole,
    required this.previousState,
    required this.newState,
    required this.reason,
    required this.timestamp,
  });

  factory WorkOrderTransitionItem.fromJson(Map<String, dynamic> json) {
    return WorkOrderTransitionItem(
      id: json['id'] as int? ?? 0,
      actor: json['actor'] as String? ?? 'Technician',
      actorRole: json['actor_role'] as String? ?? 'Technician',
      previousState: json['previous_state'] as String? ?? '',
      newState: json['new_state'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class TelemetryTrendPoint {
  final int id;
  final DateTime timestamp;
  final double vibrationMms;
  final double temperatureC;
  final double speedRpm;
  final double powerKw;

  TelemetryTrendPoint({
    required this.id,
    required this.timestamp,
    required this.vibrationMms,
    required this.temperatureC,
    required this.speedRpm,
    required this.powerKw,
  });

  factory TelemetryTrendPoint.fromJson(Map<String, dynamic> json) {
    return TelemetryTrendPoint(
      id: json['id'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      vibrationMms: (json['vibration_mms'] as num?)?.toDouble() ?? 0.0,
      temperatureC: (json['temperature_c'] as num?)?.toDouble() ?? 0.0,
      speedRpm: (json['speed_rpm'] as num?)?.toDouble() ?? 0.0,
      powerKw: (json['power_kw'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MachineOperatingLimitsData {
  final double warningVibrationMms;
  final double maxVibrationMms;
  final double warningTempC;
  final double maxTempC;
  final int minRpm;
  final int maxRpm;

  MachineOperatingLimitsData({
    required this.warningVibrationMms,
    required this.maxVibrationMms,
    required this.warningTempC,
    required this.maxTempC,
    required this.minRpm,
    required this.maxRpm,
  });

  factory MachineOperatingLimitsData.fromJson(Map<String, dynamic> json) {
    return MachineOperatingLimitsData(
      warningVibrationMms: (json['warning_vibration_mms'] as num?)?.toDouble() ?? 4.0,
      maxVibrationMms: (json['max_vibration_mms'] as num?)?.toDouble() ?? 5.5,
      warningTempC: (json['warning_temp_c'] as num?)?.toDouble() ?? 75.0,
      maxTempC: (json['max_temp_c'] as num?)?.toDouble() ?? 85.0,
      minRpm: (json['min_rpm'] as num?)?.toInt() ?? 10000,
      maxRpm: (json['max_rpm'] as num?)?.toInt() ?? 22000,
    );
  }
}

class VerificationEvaluationData {
  final String outcome;
  final String summary;
  final bool isHealthy;
  final int readingsCount;
  final double avgVibration;
  final double maxVibration;
  final double limitVibration;
  final double avgTemp;
  final double maxTemp;
  final double limitTemp;
  final bool isStable;
  final Map<String, dynamic> checks;

  VerificationEvaluationData({
    required this.outcome,
    required this.summary,
    required this.isHealthy,
    required this.readingsCount,
    required this.avgVibration,
    required this.maxVibration,
    required this.limitVibration,
    required this.avgTemp,
    required this.maxTemp,
    required this.limitTemp,
    required this.isStable,
    required this.checks,
  });

  factory VerificationEvaluationData.fromJson(Map<String, dynamic> json) {
    return VerificationEvaluationData(
      outcome: json['outcome'] as String? ?? 'PENDING_EVIDENCE',
      summary: json['summary'] as String? ?? '',
      isHealthy: json['is_healthy'] as bool? ?? false,
      readingsCount: (json['readings_count'] as num?)?.toInt() ?? 0,
      avgVibration: (json['avg_vibration'] as num?)?.toDouble() ?? 0.0,
      maxVibration: (json['max_vibration'] as num?)?.toDouble() ?? 0.0,
      limitVibration: (json['limit_vibration'] as num?)?.toDouble() ?? 4.0,
      avgTemp: (json['avg_temp'] as num?)?.toDouble() ?? 0.0,
      maxTemp: (json['max_temp'] as num?)?.toDouble() ?? 0.0,
      limitTemp: (json['limit_temp'] as num?)?.toDouble() ?? 75.0,
      isStable: json['is_stable'] as bool? ?? false,
      checks: json['checks'] is Map ? Map<String, dynamic>.from(json['checks'] as Map) : {},
    );
  }
}

class WorkOrderTicket {
  final int id;
  final String ticketNumber;
  final int machineId;
  final String machineCode;
  final String machineName;
  final String machineTypeName;
  final String departmentName;
  final String departmentCode;
  final String incidentReference;
  final String title;
  final String description;
  final String priority;
  final String status;
  final String assignedTechnician;
  final String createdByAgent;
  final String rootCause;
  final double partsCost;
  final double laborHours;
  final int actualRepairDurationMinutes;
  final List<Map<String, dynamic>> aiSuspectedCauses;
  final List<ChecklistItem> inspectionChecklist;
  final String confirmedFault;
  final String faultConfirmationNotes;
  final String repairPerformed;
  final List<Map<String, dynamic>> partsReplaced;
  final String remainingIssues;
  final DateTime? repairCompletedAt;
  final String verificationStatus;
  final String verificationSummary;
  final Map<String, dynamic> verificationData;
  final String authorizedSignoffBy;
  final DateTime? authorizedSignoffAt;
  final String signoffNotes;
  final bool isSimulation;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<WorkOrderTransitionItem> transitions;

  WorkOrderTicket({
    required this.id,
    required this.ticketNumber,
    required this.machineId,
    required this.machineCode,
    required this.machineName,
    required this.machineTypeName,
    required this.departmentName,
    required this.departmentCode,
    required this.incidentReference,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.assignedTechnician,
    required this.createdByAgent,
    required this.rootCause,
    required this.partsCost,
    required this.laborHours,
    required this.actualRepairDurationMinutes,
    required this.aiSuspectedCauses,
    required this.inspectionChecklist,
    required this.confirmedFault,
    required this.faultConfirmationNotes,
    required this.repairPerformed,
    required this.partsReplaced,
    required this.remainingIssues,
    this.repairCompletedAt,
    required this.verificationStatus,
    required this.verificationSummary,
    required this.verificationData,
    required this.authorizedSignoffBy,
    this.authorizedSignoffAt,
    required this.signoffNotes,
    required this.isSimulation,
    required this.createdAt,
    this.resolvedAt,
    required this.transitions,
  });

  factory WorkOrderTicket.fromJson(Map<String, dynamic> json) {
    var rawChecklist = json['inspection_checklist'] as List? ?? [];
    var checklist = rawChecklist
        .map((item) => ChecklistItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();

    var rawCauses = json['ai_suspected_causes'] as List? ?? [];
    var causes = rawCauses.map((c) => Map<String, dynamic>.from(c as Map)).toList();

    var rawParts = json['parts_replaced'] as List? ?? [];
    var parts = rawParts.map((p) => Map<String, dynamic>.from(p as Map)).toList();

    var rawTrans = json['transitions'] as List? ?? [];
    var transitions = rawTrans
        .map((t) => WorkOrderTransitionItem.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList();

    return WorkOrderTicket(
      id: json['id'] as int? ?? 0,
      ticketNumber: json['ticket_number'] as String? ?? '',
      machineId: json['machine'] as int? ?? 0,
      machineCode: json['machine_code'] as String? ?? 'MACH-01',
      machineName: json['machine_name'] as String? ?? '',
      machineTypeName: json['machine_type_name'] as String? ?? 'Industrial Loom',
      departmentName: json['department_name'] as String? ?? 'Production',
      departmentCode: json['department_code'] as String? ?? 'WEV',
      incidentReference: json['incident_reference'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      priority: json['priority'] as String? ?? 'MEDIUM',
      status: json['status'] as String? ?? 'CREATED',
      assignedTechnician: json['assigned_technician'] as String? ?? 'Mechanical Team',
      createdByAgent: json['created_by_agent'] as String? ?? '',
      rootCause: json['root_cause'] as String? ?? '',
      partsCost: (json['parts_cost'] as num?)?.toDouble() ?? 0.0,
      laborHours: (json['labor_hours'] as num?)?.toDouble() ?? 0.0,
      actualRepairDurationMinutes: (json['actual_repair_duration_minutes'] as num?)?.toInt() ?? 0,
      aiSuspectedCauses: causes,
      inspectionChecklist: checklist,
      confirmedFault: json['confirmed_fault'] as String? ?? '',
      faultConfirmationNotes: json['fault_confirmation_notes'] as String? ?? '',
      repairPerformed: json['repair_performed'] as String? ?? '',
      partsReplaced: parts,
      remainingIssues: json['remaining_issues'] as String? ?? '',
      repairCompletedAt: json['repair_completed_at'] != null
          ? DateTime.tryParse(json['repair_completed_at'] as String)
          : null,
      verificationStatus: json['verification_status'] as String? ?? 'PENDING_EVIDENCE',
      verificationSummary: json['verification_summary'] as String? ?? '',
      verificationData: json['verification_data'] is Map
          ? Map<String, dynamic>.from(json['verification_data'] as Map)
          : {},
      authorizedSignoffBy: json['authorized_signoff_by'] as String? ?? '',
      authorizedSignoffAt: json['authorized_signoff_at'] != null
          ? DateTime.tryParse(json['authorized_signoff_at'] as String)
          : null,
      signoffNotes: json['signoff_notes'] as String? ?? '',
      isSimulation: json['is_simulation'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'] as String)
          : null,
      transitions: transitions,
    );
  }
}

class ExecutionDetailResponse {
  final WorkOrderTicket ticket;
  final MachineOperatingLimitsData limits;
  final List<TelemetryTrendPoint> telemetryTrend;
  final Map<String, dynamic>? incident;
  final List<Map<String, dynamic>> sparePartsCatalog;
  final List<Map<String, dynamic>> maintenanceHistory;
  final VerificationEvaluationData verificationEvaluation;

  ExecutionDetailResponse({
    required this.ticket,
    required this.limits,
    required this.telemetryTrend,
    this.incident,
    required this.sparePartsCatalog,
    required this.maintenanceHistory,
    required this.verificationEvaluation,
  });

  factory ExecutionDetailResponse.fromJson(Map<String, dynamic> json) {
    var rawTrend = json['telemetry_trend'] as List? ?? [];
    var trend = rawTrend
        .map((p) => TelemetryTrendPoint.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList();

    var rawParts = json['spare_parts_catalog'] as List? ?? [];
    var parts = rawParts.map((p) => Map<String, dynamic>.from(p as Map)).toList();

    var rawHist = json['maintenance_history'] as List? ?? [];
    var hist = rawHist.map((h) => Map<String, dynamic>.from(h as Map)).toList();

    return ExecutionDetailResponse(
      ticket: WorkOrderTicket.fromJson(Map<String, dynamic>.from(json['ticket'] as Map)),
      limits: MachineOperatingLimitsData.fromJson(
        Map<String, dynamic>.from(json['machine_limits'] as Map? ?? {}),
      ),
      telemetryTrend: trend,
      incident: json['incident'] is Map ? Map<String, dynamic>.from(json['incident'] as Map) : null,
      sparePartsCatalog: parts,
      maintenanceHistory: hist,
      verificationEvaluation: VerificationEvaluationData.fromJson(
        Map<String, dynamic>.from(json['verification_evaluation'] as Map? ?? {}),
      ),
    );
  }
}
