class AnomalyModel {
  final int id;
  final int? incidentId;
  final int machineId;
  final String machineCode;
  final String machineName;
  final String departmentCode;
  final int? telemetryReadingId;
  final String metricName;
  final double observedValue;
  final double thresholdValue;
  final double anomalyScore;
  final double confidencePct;
  final String algorithmUsed;
  final String detectedAt;

  AnomalyModel({
    required this.id,
    this.incidentId,
    required this.machineId,
    required this.machineCode,
    required this.machineName,
    required this.departmentCode,
    this.telemetryReadingId,
    required this.metricName,
    required this.observedValue,
    required this.thresholdValue,
    required this.anomalyScore,
    required this.confidencePct,
    required this.algorithmUsed,
    required this.detectedAt,
  });

  static double parseDouble(dynamic val, double fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    if (val is String) {
      return double.tryParse(val) ?? fallback;
    }
    return fallback;
  }

  static int parseInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    if (val is String) {
      return int.tryParse(val) ?? fallback;
    }
    return fallback;
  }

  factory AnomalyModel.fromJson(Map<String, dynamic> json) {
    return AnomalyModel(
      id: parseInt(json['id'], 0),
      incidentId: json['incident'] is int ? json['incident'] : int.tryParse(json['incident']?.toString() ?? ''),
      machineId: parseInt(json['machine'], 0),
      machineCode: json['machine_code']?.toString() ?? '',
      machineName: json['machine_name']?.toString() ?? '',
      departmentCode: json['department_code']?.toString() ?? '',
      telemetryReadingId: json['telemetry_reading_id'] is int
          ? json['telemetry_reading_id']
          : int.tryParse(json['telemetry_reading_id']?.toString() ?? ''),
      metricName: json['metric_name']?.toString() ?? '',
      observedValue: parseDouble(json['observed_value'], 0.0),
      thresholdValue: parseDouble(json['threshold_value'], 0.0),
      anomalyScore: parseDouble(json['anomaly_score'], 1.0),
      confidencePct: parseDouble(json['confidence_pct'], 95.0),
      algorithmUsed: json['algorithm_used']?.toString() ?? 'THRESHOLD_RULE',
      detectedAt: json['detected_at']?.toString() ?? '',
    );
  }
}

class FactoryIncidentModel {
  final int id;
  final String incidentCode;
  final int factoryId;
  final int departmentId;
  final int? machineId;
  final String? machineCode;
  final String? machineName;
  final String departmentCode;
  final String departmentName;
  final String severity;
  final String status;
  final String category;
  final String summary;
  final String rootCauseHypothesis;
  final Map<String, dynamic> evidenceData;
  final String detectedAt;
  final String? resolvedAt;
  final String resolutionSummary;
  final List<AnomalyModel> anomalies;

  FactoryIncidentModel({
    required this.id,
    required this.incidentCode,
    required this.factoryId,
    required this.departmentId,
    this.machineId,
    this.machineCode,
    this.machineName,
    required this.departmentCode,
    required this.departmentName,
    required this.severity,
    required this.status,
    required this.category,
    required this.summary,
    required this.rootCauseHypothesis,
    required this.evidenceData,
    required this.detectedAt,
    this.resolvedAt,
    required this.resolutionSummary,
    required this.anomalies,
  });

  factory FactoryIncidentModel.fromJson(Map<String, dynamic> json) {
    final rawAnomalies = json['anomalies'];
    List<AnomalyModel> anomaliesList = [];
    if (rawAnomalies is List) {
      anomaliesList = rawAnomalies
          .map((a) => a is Map<String, dynamic> ? AnomalyModel.fromJson(a) : null)
          .whereType<AnomalyModel>()
          .toList();
    }

    return FactoryIncidentModel(
      id: AnomalyModel.parseInt(json['id'], 0),
      incidentCode: json['incident_code']?.toString() ?? '',
      factoryId: AnomalyModel.parseInt(json['factory'], 0),
      departmentId: AnomalyModel.parseInt(json['department'], 0),
      machineId: json['machine'] is int ? json['machine'] : int.tryParse(json['machine']?.toString() ?? ''),
      machineCode: json['machine_code']?.toString(),
      machineName: json['machine_name']?.toString(),
      departmentCode: json['department_code']?.toString() ?? '',
      departmentName: json['department_name']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'MEDIUM',
      status: json['status']?.toString() ?? 'OPEN',
      category: json['category']?.toString() ?? 'MACHINE_HEALTH',
      summary: json['summary']?.toString() ?? '',
      rootCauseHypothesis: json['root_cause_hypothesis']?.toString() ?? '',
      evidenceData: json['evidence_data'] as Map<String, dynamic>? ?? {},
      detectedAt: json['detected_at']?.toString() ?? '',
      resolvedAt: json['resolved_at']?.toString(),
      resolutionSummary: json['resolution_summary']?.toString() ?? '',
      anomalies: anomaliesList,
    );
  }
}

class DetectionCheckpointModel {
  final int lastProcessedTelemetryId;
  final String? lastEvaluatedAt;
  final int totalTelemetryProcessed;
  final int totalAnomaliesDetected;
  final int totalIncidentsCreated;
  final bool isWorkerRunning;
  final bool isThreadAlive;

  DetectionCheckpointModel({
    required this.lastProcessedTelemetryId,
    this.lastEvaluatedAt,
    required this.totalTelemetryProcessed,
    required this.totalAnomaliesDetected,
    required this.totalIncidentsCreated,
    required this.isWorkerRunning,
    required this.isThreadAlive,
  });

  factory DetectionCheckpointModel.fromJson(Map<String, dynamic> json) {
    return DetectionCheckpointModel(
      lastProcessedTelemetryId: AnomalyModel.parseInt(json['last_processed_telemetry_id'], 0),
      lastEvaluatedAt: json['last_evaluated_at']?.toString(),
      totalTelemetryProcessed: AnomalyModel.parseInt(json['total_telemetry_processed'], 0),
      totalAnomaliesDetected: AnomalyModel.parseInt(json['total_anomalies_detected'], 0),
      totalIncidentsCreated: AnomalyModel.parseInt(json['total_incidents_created'], 0),
      isWorkerRunning: json['is_worker_running'] == true,
      isThreadAlive: json['is_thread_alive'] == true,
    );
  }
}

class IncidentsSummaryModel {
  final int totalActiveIncidents;
  final Map<String, int> severityBreakdown;
  final Map<String, int> statusBreakdown;
  final DetectionCheckpointModel checkpoint;
  final List<FactoryIncidentModel> activeIncidents;
  final List<AnomalyModel> recentAnomalies;

  IncidentsSummaryModel({
    required this.totalActiveIncidents,
    required this.severityBreakdown,
    required this.statusBreakdown,
    required this.checkpoint,
    required this.activeIncidents,
    required this.recentAnomalies,
  });

  factory IncidentsSummaryModel.fromJson(Map<String, dynamic> json) {
    final sevRaw = json['severity_breakdown'] as Map<String, dynamic>? ?? {};
    final severityMap = sevRaw.map((k, v) => MapEntry(k, AnomalyModel.parseInt(v, 0)));

    final statRaw = json['status_breakdown'] as Map<String, dynamic>? ?? {};
    final statusMap = statRaw.map((k, v) => MapEntry(k, AnomalyModel.parseInt(v, 0)));

    final cp = DetectionCheckpointModel.fromJson(json['checkpoint'] as Map<String, dynamic>? ?? {});

    final rawIncList = json['active_incidents'];
    List<FactoryIncidentModel> incList = [];
    if (rawIncList is List) {
      incList = rawIncList
          .map((i) => i is Map<String, dynamic> ? FactoryIncidentModel.fromJson(i) : null)
          .whereType<FactoryIncidentModel>()
          .toList();
    }

    final rawAnomList = json['recent_anomalies'];
    List<AnomalyModel> anomList = [];
    if (rawAnomList is List) {
      anomList = rawAnomList
          .map((a) => a is Map<String, dynamic> ? AnomalyModel.fromJson(a) : null)
          .whereType<AnomalyModel>()
          .toList();
    }

    return IncidentsSummaryModel(
      totalActiveIncidents: AnomalyModel.parseInt(json['total_active_incidents'], incList.length),
      severityBreakdown: severityMap,
      statusBreakdown: statusMap,
      checkpoint: cp,
      activeIncidents: incList,
      recentAnomalies: anomList,
    );
  }
}
