class HealthStatusModel {
  final String status;
  final String service;
  final String version;
  final String timestamp;
  final Map<String, dynamic>? dependencies;
  final int latencyMs;
  final bool isSuccess;
  final String? errorMessage;
  final String rawJson;

  HealthStatusModel({
    required this.status,
    required this.service,
    required this.version,
    required this.timestamp,
    this.dependencies,
    required this.latencyMs,
    required this.isSuccess,
    this.errorMessage,
    required this.rawJson,
  });

  factory HealthStatusModel.fromJson(
    Map<String, dynamic> json, {
    required int latencyMs,
    required String rawJson,
  }) {
    return HealthStatusModel(
      status: json['status']?.toString() ?? 'unknown',
      service: json['service']?.toString() ?? 'Texora AI Service',
      version: json['version']?.toString() ?? '1.0.0',
      timestamp: json['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
      dependencies: json['dependencies'] as Map<String, dynamic>?,
      latencyMs: latencyMs,
      isSuccess: true,
      rawJson: rawJson,
    );
  }

  factory HealthStatusModel.error({
    required String errorMessage,
    required int latencyMs,
    String? rawJson,
  }) {
    return HealthStatusModel(
      status: 'error',
      service: 'Texora AI Backend',
      version: '1.0.0',
      timestamp: DateTime.now().toIso8601String(),
      latencyMs: latencyMs,
      isSuccess: false,
      errorMessage: errorMessage,
      rawJson: rawJson ?? '{"error": "$errorMessage"}',
    );
  }

  String get databaseStatus {
    if (dependencies != null && dependencies!.containsKey('database')) {
      return dependencies!['database'].toString();
    }
    return isSuccess ? 'connected' : 'unreachable';
  }
}

class WorkerInfo {
  final String name;
  final String status;
  final bool isRunning;
  final bool isStale;
  final String? lastHeartbeat;
  final String? lastExecution;
  final int processId;
  final int processingCount;
  final String lastError;
  final Map<String, dynamic> metrics;

  WorkerInfo({
    required this.name,
    required this.status,
    required this.isRunning,
    required this.isStale,
    this.lastHeartbeat,
    this.lastExecution,
    required this.processId,
    required this.processingCount,
    required this.lastError,
    required this.metrics,
  });

  factory WorkerInfo.fromJson(Map<String, dynamic> json) {
    return WorkerInfo(
      name: json['name']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      isRunning: json['is_running'] == true,
      isStale: json['is_stale'] == true,
      lastHeartbeat: json['last_heartbeat']?.toString(),
      lastExecution: json['last_execution']?.toString(),
      processId: (json['process_id'] as num?)?.toInt() ?? 0,
      processingCount: (json['processing_count'] as num?)?.toInt() ?? 0,
      lastError: json['last_error']?.toString() ?? '',
      metrics: (json['metrics'] as Map<String, dynamic>?) ?? {},
    );
  }
}

class SystemHealthSummaryModel {
  final String overallStatus;
  final String timestamp;
  final String service;
  final Map<String, dynamic> djangoApi;
  final Map<String, dynamic> database;
  final Map<String, dynamic> geminiProvider;
  final Map<String, WorkerInfo> workers;

  SystemHealthSummaryModel({
    required this.overallStatus,
    required this.timestamp,
    required this.service,
    required this.djangoApi,
    required this.database,
    required this.geminiProvider,
    required this.workers,
  });

  factory SystemHealthSummaryModel.fromJson(Map<String, dynamic> json) {
    final workersMap = <String, WorkerInfo>{};
    final rawWorkers = json['workers'] as Map<String, dynamic>? ?? {};
    rawWorkers.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        workersMap[key] = WorkerInfo.fromJson(value);
      }
    });

    return SystemHealthSummaryModel(
      overallStatus: json['overall_status']?.toString() ?? 'UNKNOWN',
      timestamp: json['timestamp']?.toString() ?? '',
      service: json['service']?.toString() ?? 'Texora AI',
      djangoApi: (json['django_api'] as Map<String, dynamic>?) ?? {},
      database: (json['database'] as Map<String, dynamic>?) ?? {},
      geminiProvider: (json['gemini_provider'] as Map<String, dynamic>?) ?? {},
      workers: workersMap,
    );
  }
}

