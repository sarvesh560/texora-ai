class SimulationStateModel {
  final bool isRunning;
  final bool isPaused;
  final double speedMultiplier;
  final double tickIntervalSeconds;
  final int totalTicksGenerated;
  final String? lastTickAt;
  final String? startedAt;
  final bool isThreadAlive;

  SimulationStateModel({
    required this.isRunning,
    required this.isPaused,
    required this.speedMultiplier,
    required this.tickIntervalSeconds,
    required this.totalTicksGenerated,
    this.lastTickAt,
    this.startedAt,
    required this.isThreadAlive,
  });

  factory SimulationStateModel.fromJson(Map<String, dynamic> json) {
    return SimulationStateModel(
      isRunning: json['is_running'] ?? false,
      isPaused: json['is_paused'] ?? false,
      speedMultiplier: (json['speed_multiplier'] as num?)?.toDouble() ?? 1.0,
      tickIntervalSeconds: (json['tick_interval_seconds'] as num?)?.toDouble() ?? 3.0,
      totalTicksGenerated: json['total_ticks_generated'] ?? 0,
      lastTickAt: json['last_tick_at'],
      startedAt: json['started_at'],
      isThreadAlive: json['is_thread_alive'] ?? false,
    );
  }
}

class InjectedScenarioModel {
  final int id;
  final String scenarioType;
  final String scenarioTypeDisplay;
  final String targetMachineCode;
  final String targetDepartmentCode;
  final String severity;
  final bool isActive;
  final String description;
  final String injectedAt;

  InjectedScenarioModel({
    required this.id,
    required this.scenarioType,
    required this.scenarioTypeDisplay,
    required this.targetMachineCode,
    required this.targetDepartmentCode,
    required this.severity,
    required this.isActive,
    required this.description,
    required this.injectedAt,
  });

  factory InjectedScenarioModel.fromJson(Map<String, dynamic> json) {
    return InjectedScenarioModel(
      id: json['id'] ?? 0,
      scenarioType: json['scenario_type'] ?? '',
      scenarioTypeDisplay: json['scenario_type_display'] ?? json['scenario_type'] ?? '',
      targetMachineCode: json['target_machine_code'] ?? '',
      targetDepartmentCode: json['target_department_code'] ?? '',
      severity: json['severity'] ?? 'HIGH',
      isActive: json['is_active'] ?? true,
      description: json['description'] ?? '',
      injectedAt: json['injected_at'] ?? '',
    );
  }
}

class DepartmentSummaryModel {
  final int id;
  final String code;
  final String name;
  final String departmentType;
  final int totalMachines;
  final int operationalMachines;
  final int warningMachines;
  final int criticalMachines;
  final double averageHealthScore;

  DepartmentSummaryModel({
    required this.id,
    required this.code,
    required this.name,
    required this.departmentType,
    required this.totalMachines,
    required this.operationalMachines,
    required this.warningMachines,
    required this.criticalMachines,
    required this.averageHealthScore,
  });

  factory DepartmentSummaryModel.fromJson(Map<String, dynamic> json) {
    return DepartmentSummaryModel(
      id: json['id'] ?? 0,
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      departmentType: json['department_type'] ?? '',
      totalMachines: json['total_machines'] ?? 0,
      operationalMachines: json['operational_machines'] ?? 0,
      warningMachines: json['warning_machines'] ?? 0,
      criticalMachines: json['critical_machines'] ?? 0,
      averageHealthScore: (json['average_health_score'] as num?)?.toDouble() ?? 100.0,
    );
  }
}

class LiveTelemetryModel {
  final String timestamp;
  final double temperatureC;
  final double vibrationMms;
  final int speedRpm;
  final double powerKw;
  final double utilizationPct;
  final double outputRate;
  final String statusFlag;

  LiveTelemetryModel({
    required this.timestamp,
    required this.temperatureC,
    required this.vibrationMms,
    required this.speedRpm,
    required this.powerKw,
    required this.utilizationPct,
    required this.outputRate,
    required this.statusFlag,
  });

  factory LiveTelemetryModel.fromJson(Map<String, dynamic> json) {
    return LiveTelemetryModel(
      timestamp: json['timestamp'] ?? '',
      temperatureC: (json['temperature_c'] as num?)?.toDouble() ?? 0.0,
      vibrationMms: (json['vibration_mms'] as num?)?.toDouble() ?? 0.0,
      speedRpm: (json['speed_rpm'] as num?)?.toInt() ?? 0,
      powerKw: (json['power_kw'] as num?)?.toDouble() ?? 0.0,
      utilizationPct: (json['utilization_pct'] as num?)?.toDouble() ?? 0.0,
      outputRate: (json['output_rate'] as num?)?.toDouble() ?? 0.0,
      statusFlag: json['status_flag'] ?? 'NORMAL',
    );
  }
}

class LiveMachineModel {
  final int id;
  final String code;
  final String name;
  final String departmentCode;
  final String departmentName;
  final String status;
  final double healthScore;
  final double ratedCapacity;
  final LiveTelemetryModel? latestTelemetry;

  LiveMachineModel({
    required this.id,
    required this.code,
    required this.name,
    required this.departmentCode,
    required this.departmentName,
    required this.status,
    required this.healthScore,
    required this.ratedCapacity,
    this.latestTelemetry,
  });

  factory LiveMachineModel.fromJson(Map<String, dynamic> json) {
    return LiveMachineModel(
      id: json['id'] ?? 0,
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      departmentCode: json['department_code'] ?? '',
      departmentName: json['department_name'] ?? '',
      status: json['status'] ?? 'OPERATIONAL',
      healthScore: (json['current_health_score'] as num?)?.toDouble() ?? 100.0,
      ratedCapacity: (json['rated_capacity_units_per_hour'] as num?)?.toDouble() ?? 0.0,
      latestTelemetry: json['latest_telemetry'] != null
          ? LiveTelemetryModel.fromJson(json['latest_telemetry'])
          : null,
    );
  }
}

class SimulationSummaryModel {
  final SimulationStateModel state;
  final String factoryName;
  final String factoryCode;
  final int totalMachines;
  final Map<String, int> statusBreakdown;
  final double totalPowerKw;
  final int activeScenariosCount;
  final List<InjectedScenarioModel> activeScenarios;
  final int failedInspectionsCount;
  final int activeOrdersCount;
  final List<DepartmentSummaryModel> departments;
  final List<LiveMachineModel> machines;

  SimulationSummaryModel({
    required this.state,
    required this.factoryName,
    required this.factoryCode,
    required this.totalMachines,
    required this.statusBreakdown,
    required this.totalPowerKw,
    required this.activeScenariosCount,
    required this.activeScenarios,
    required this.failedInspectionsCount,
    required this.activeOrdersCount,
    required this.departments,
    required this.machines,
  });

  factory SimulationSummaryModel.fromJson(Map<String, dynamic> json) {
    final state = SimulationStateModel.fromJson(json['simulation_state'] ?? {});
    final breakdownRaw = json['status_breakdown'] as Map<String, dynamic>? ?? {};
    final statusBreakdown = breakdownRaw.map((k, v) => MapEntry(k, (v as num).toInt()));

    final scenariosList = (json['active_scenarios'] as List<dynamic>? ?? [])
        .map((s) => InjectedScenarioModel.fromJson(s as Map<String, dynamic>))
        .toList();

    final deptList = (json['departments'] as List<dynamic>? ?? [])
        .map((d) => DepartmentSummaryModel.fromJson(d as Map<String, dynamic>))
        .toList();

    final machinesList = (json['machines'] as List<dynamic>? ?? [])
        .map((m) => LiveMachineModel.fromJson(m as Map<String, dynamic>))
        .toList();

    return SimulationSummaryModel(
      state: state,
      factoryName: json['factory_name'] ?? '',
      factoryCode: json['factory_code'] ?? '',
      totalMachines: json['total_machines'] ?? 0,
      statusBreakdown: statusBreakdown,
      totalPowerKw: (json['total_power_kw'] as num?)?.toDouble() ?? 0.0,
      activeScenariosCount: json['active_scenarios_count'] ?? 0,
      activeScenarios: scenariosList,
      failedInspectionsCount: json['failed_inspections_count'] ?? 0,
      activeOrdersCount: json['active_orders_count'] ?? 0,
      departments: deptList,
      machines: machinesList,
    );
  }
}
