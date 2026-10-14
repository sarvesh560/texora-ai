import '../../core/utils/numeric_parser.dart';

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
      stepId: parseIntWithFallback(json['step_id'], 1, fieldName: 'step_id'),
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
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
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
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      vibrationMms: parseDoubleWithFallback(json['vibration_mms'], 0.0, fieldName: 'vibration_mms'),
      temperatureC: parseDoubleWithFallback(json['temperature_c'], 0.0, fieldName: 'temperature_c'),
      speedRpm: parseDoubleWithFallback(json['speed_rpm'], 0.0, fieldName: 'speed_rpm'),
      powerKw: parseDoubleWithFallback(json['power_kw'], 0.0, fieldName: 'power_kw'),
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
      warningVibrationMms: parseDoubleWithFallback(json['warning_vibration_mms'], 4.0, fieldName: 'warning_vibration_mms'),
      maxVibrationMms: parseDoubleWithFallback(json['max_vibration_mms'], 5.5, fieldName: 'max_vibration_mms'),
      warningTempC: parseDoubleWithFallback(json['warning_temp_c'], 75.0, fieldName: 'warning_temp_c'),
      maxTempC: parseDoubleWithFallback(json['max_temp_c'], 85.0, fieldName: 'max_temp_c'),
      minRpm: parseIntWithFallback(json['min_rpm'], 10000, fieldName: 'min_rpm'),
      maxRpm: parseIntWithFallback(json['max_rpm'], 22000, fieldName: 'max_rpm'),
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
      readingsCount: parseIntWithFallback(json['readings_count'], 0, fieldName: 'readings_count'),
      avgVibration: parseDoubleWithFallback(json['avg_vibration'], 0.0, fieldName: 'avg_vibration'),
      maxVibration: parseDoubleWithFallback(json['max_vibration'], 0.0, fieldName: 'max_vibration'),
      limitVibration: parseDoubleWithFallback(json['limit_vibration'], 4.0, fieldName: 'limit_vibration'),
      avgTemp: parseDoubleWithFallback(json['avg_temp'], 0.0, fieldName: 'avg_temp'),
      maxTemp: parseDoubleWithFallback(json['max_temp'], 0.0, fieldName: 'max_temp'),
      limitTemp: parseDoubleWithFallback(json['limit_temp'], 75.0, fieldName: 'limit_temp'),
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
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
      ticketNumber: json['ticket_number'] as String? ?? '',
      machineId: parseIntWithFallback(json['machine'], 0, fieldName: 'machine'),
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
      partsCost: parseDoubleWithFallback(json['parts_cost'], 0.0, fieldName: 'parts_cost'),
      laborHours: parseDoubleWithFallback(json['labor_hours'], 0.0, fieldName: 'labor_hours'),
      actualRepairDurationMinutes: parseIntWithFallback(json['actual_repair_duration_minutes'], 0, fieldName: 'actual_repair_duration_minutes'),
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
