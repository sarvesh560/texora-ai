import '../../core/utils/numeric_parser.dart';

class DepartmentCapacityModel {
  final int departmentId;
  final String departmentCode;
  final String departmentName;
  final int totalMachines;
  final int activeMachines;
  final int downMachines;
  final double nominalCapacityDaily;
  final double effectiveCapacityDaily;
  final double allocatedCapacityDaily;
  final double actualProducedDaily;
  final double utilizationPct;
  final double downtimeLossDaily;
  final String bottleneckSeverity;
  final double availableHeadroomUnits;

  const DepartmentCapacityModel({
    required this.departmentId,
    required this.departmentCode,
    required this.departmentName,
    required this.totalMachines,
    required this.activeMachines,
    required this.downMachines,
    required this.nominalCapacityDaily,
    required this.effectiveCapacityDaily,
    required this.allocatedCapacityDaily,
    required this.actualProducedDaily,
    required this.utilizationPct,
    required this.downtimeLossDaily,
    required this.bottleneckSeverity,
    required this.availableHeadroomUnits,
  });

  factory DepartmentCapacityModel.fromJson(Map<String, dynamic> json) {
    return DepartmentCapacityModel(
      departmentId: (json['department_id'] as num?)?.toInt() ?? 0,
      departmentCode: json['department_code'] as String? ?? '',
      departmentName: json['department_name'] as String? ?? json['department_code'] as String? ?? '',
      totalMachines: (json['total_machines'] as num?)?.toInt() ?? 0,
      activeMachines: (json['active_machines'] as num?)?.toInt() ?? 0,
      downMachines: (json['down_machines'] as num?)?.toInt() ?? 0,
      nominalCapacityDaily: NumericParser.parseDoubleWithFallback(
        json['nominal_capacity_daily'] ?? json['nominal_capacity_units'],
        0.0,
      ),
      effectiveCapacityDaily: NumericParser.parseDoubleWithFallback(
        json['effective_capacity_daily'] ?? json['effective_capacity_units'],
        0.0,
      ),
      allocatedCapacityDaily: NumericParser.parseDoubleWithFallback(
        json['allocated_capacity_daily'] ?? json['allocated_capacity_units'],
        0.0,
      ),
      actualProducedDaily: NumericParser.parseDoubleWithFallback(
        json['actual_produced_daily'] ?? json['actual_produced_units'],
        0.0,
      ),
      utilizationPct: NumericParser.parseDoubleWithFallback(
        json['utilization_pct'],
        0.0,
      ),
      downtimeLossDaily: NumericParser.parseDoubleWithFallback(
        json['downtime_loss_daily'] ?? json['downtime_loss_units'],
        0.0,
      ),
      bottleneckSeverity: json['bottleneck_severity'] as String? ?? 'NORMAL',
      availableHeadroomUnits: NumericParser.parseDoubleWithFallback(
        json['available_headroom_units'],
        0.0,
      ),
    );
  }
}

class ProductionBatchModel {
  final int id;
  final String batchNumber;
  final String orderNumber;
  final String? machineCode;
  final String? machineName;
  final double plannedQuantity;
  final double actualQuantity;
  final double defectQuantity;
  final String status;
  final double effectiveSpeedPct;
  final double progressPct;

  const ProductionBatchModel({
    required this.id,
    required this.batchNumber,
    required this.orderNumber,
    this.machineCode,
    this.machineName,
    required this.plannedQuantity,
    required this.actualQuantity,
    required this.defectQuantity,
    required this.status,
    required this.effectiveSpeedPct,
    required this.progressPct,
  });

  factory ProductionBatchModel.fromJson(Map<String, dynamic> json) {
    return ProductionBatchModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      batchNumber: json['batch_number'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '',
      machineCode: json['machine_code'] as String?,
      machineName: json['machine_name'] as String?,
      plannedQuantity: NumericParser.parseDoubleWithFallback(json['planned_quantity'], 0.0),
      actualQuantity: NumericParser.parseDoubleWithFallback(json['actual_quantity'], 0.0),
      defectQuantity: NumericParser.parseDoubleWithFallback(json['defect_quantity'], 0.0),
      status: json['status'] as String? ?? 'STAGED',
      effectiveSpeedPct: NumericParser.parseDoubleWithFallback(json['effective_speed_pct'], 100.0),
      progressPct: NumericParser.parseDoubleWithFallback(json['progress_pct'], 0.0),
    );
  }
}

class MachineAssignmentModel {
  final int id;
  final String machineCode;
  final String machineName;
  final String orderNumber;
  final String stageName;
  final String status;
  final String shift;
  final double plannedRunHours;
  final double actualRunHours;

  const MachineAssignmentModel({
    required this.id,
    required this.machineCode,
    required this.machineName,
    required this.orderNumber,
    required this.stageName,
    required this.status,
    required this.shift,
    required this.plannedRunHours,
    required this.actualRunHours,
  });

  factory MachineAssignmentModel.fromJson(Map<String, dynamic> json) {
    return MachineAssignmentModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      machineCode: json['machine_code'] as String? ?? '',
      machineName: json['machine_name'] as String? ?? json['machine_code'] as String? ?? '',
      orderNumber: json['order_number'] as String? ?? '',
      stageName: json['stage_name'] as String? ?? 'Production',
      status: json['status'] as String? ?? 'ASSIGNED',
      shift: json['shift'] as String? ?? 'SHIFT_1',
      plannedRunHours: NumericParser.parseDoubleWithFallback(json['planned_run_hours'], 8.0),
      actualRunHours: NumericParser.parseDoubleWithFallback(json['actual_run_hours'], 0.0),
    );
  }
}

class ProductionOrderModel {
  final int id;
  final String orderNumber;
  final String clientName;
  final String customerPoNumber;
  final String fabricOrYarnSpec;
  final String productCategory;
  final String departmentName;
  final String departmentCode;
  final double targetQuantity;
  final String unit;
  final double completedQuantity;
  final double remainingQuantity;
  final String status;
  final String priority;
  final List<String> routingStages;
  final String currentStage;
  final String? startDate;
  final String? dueDate;
  final String? targetDeliveryDate;
  final String? projectedCompletionDate;
  final double estimatedRemainingHours;
  final double delayRiskScore;
  final String delayRiskLevel;
  final double estimatedDelayHours;
  final double progressPct;
  final List<ProductionBatchModel> batches;
  final List<MachineAssignmentModel> machineAssignments;

  const ProductionOrderModel({
    required this.id,
    required this.orderNumber,
    required this.clientName,
    required this.customerPoNumber,
    required this.fabricOrYarnSpec,
    required this.productCategory,
    required this.departmentName,
    required this.departmentCode,
    required this.targetQuantity,
    required this.unit,
    required this.completedQuantity,
    required this.remainingQuantity,
    required this.status,
    required this.priority,
    required this.routingStages,
    required this.currentStage,
    this.startDate,
    this.dueDate,
    this.targetDeliveryDate,
    this.projectedCompletionDate,
    required this.estimatedRemainingHours,
    required this.delayRiskScore,
    required this.delayRiskLevel,
    required this.estimatedDelayHours,
    required this.progressPct,
    this.batches = const [],
    this.machineAssignments = const [],
  });

  factory ProductionOrderModel.fromJson(Map<String, dynamic> json) {
    final stagesRaw = json['routing_stages'];
    List<String> parsedStages = [];
    if (stagesRaw is List) {
      parsedStages = stagesRaw.map((e) => e.toString()).toList();
    }

    final batchesRaw = json['batches'];
    List<ProductionBatchModel> parsedBatches = [];
    if (batchesRaw is List) {
      parsedBatches = batchesRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => ProductionBatchModel.fromJson(e))
          .toList();
    }

    final assignsRaw = json['machine_assignments'];
    List<MachineAssignmentModel> parsedAssigns = [];
    if (assignsRaw is List) {
      parsedAssigns = assignsRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => MachineAssignmentModel.fromJson(e))
          .toList();
    }

    return ProductionOrderModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      orderNumber: json['order_number'] as String? ?? '',
      clientName: json['client_name'] as String? ?? '',
      customerPoNumber: json['customer_po_number'] as String? ?? '',
      fabricOrYarnSpec: json['fabric_or_yarn_spec'] as String? ?? '',
      productCategory: json['product_category'] as String? ?? 'COMBED_YARN',
      departmentName: json['department_name'] as String? ?? '',
      departmentCode: json['department_code'] as String? ?? '',
      targetQuantity: NumericParser.parseDoubleWithFallback(json['target_quantity'], 0.0),
      unit: json['unit'] as String? ?? 'KG',
      completedQuantity: NumericParser.parseDoubleWithFallback(json['completed_quantity'], 0.0),
      remainingQuantity: NumericParser.parseDoubleWithFallback(json['remaining_quantity'], 0.0),
      status: json['status'] as String? ?? 'PLANNED',
      priority: json['priority'] as String? ?? 'MEDIUM',
      routingStages: parsedStages,
      currentStage: json['current_stage'] as String? ?? '',
      startDate: json['start_date'] as String?,
      dueDate: json['due_date'] as String?,
      targetDeliveryDate: json['target_delivery_date'] as String?,
      projectedCompletionDate: json['projected_completion_date'] as String?,
      estimatedRemainingHours: NumericParser.parseDoubleWithFallback(json['estimated_remaining_hours'], 0.0),
      delayRiskScore: NumericParser.parseDoubleWithFallback(json['delay_risk_score'], 0.0),
      delayRiskLevel: json['delay_risk_level'] as String? ?? 'LOW',
      estimatedDelayHours: NumericParser.parseDoubleWithFallback(json['estimated_delay_hours'], 0.0),
      progressPct: NumericParser.parseDoubleWithFallback(json['progress_pct'], 0.0),
      batches: parsedBatches,
      machineAssignments: parsedAssigns,
    );
  }
}

class ProductionBottleneckModel {
  final int id;
  final String departmentCode;
  final String departmentName;
  final String? machineCode;
  final String severity;
  final String bottleneckType;
  final String primaryCause;
  final int affectedOrdersCount;
  final double deficitPerHour;
  final double estimatedDelayHours;

  const ProductionBottleneckModel({
    required this.id,
    required this.departmentCode,
    required this.departmentName,
    this.machineCode,
    required this.severity,
    required this.bottleneckType,
    required this.primaryCause,
    required this.affectedOrdersCount,
    required this.deficitPerHour,
    required this.estimatedDelayHours,
  });

  factory ProductionBottleneckModel.fromJson(Map<String, dynamic> json) {
    return ProductionBottleneckModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      departmentCode: json['department_code'] as String? ?? json['department'] as String? ?? '',
      departmentName: json['department_name'] as String? ?? json['department_code'] as String? ?? '',
      machineCode: json['machine_code'] as String? ?? json['machine'] as String?,
      severity: json['severity'] as String? ?? 'MEDIUM',
      bottleneckType: json['bottleneck_type'] as String? ?? json['type'] as String? ?? 'CAPACITY_OVERLOAD',
      primaryCause: json['primary_cause'] as String? ?? json['cause'] as String? ?? '',
      affectedOrdersCount: (json['affected_orders_count'] as num?)?.toInt() ?? (json['affected_orders'] as num?)?.toInt() ?? 0,
      deficitPerHour: NumericParser.parseDoubleWithFallback(
        json['throughput_deficit_units_per_hour'] ?? json['deficit_per_hour'] ?? json['deficit_per_hr'],
        0.0,
      ),
      estimatedDelayHours: NumericParser.parseDoubleWithFallback(
        json['estimated_delay_impact_hours'] ?? json['estimated_delay_hours'],
        0.0,
      ),
    );
  }
}

class ProductionImpactAssessmentModel {
  final int id;
  final String assessmentCode;
  final String machineCode;
  final String machineName;
  final String? incidentCode;
  final double estimatedDowntimeHours;
  final double outputQuantityAtRisk;
  final int ordersAffectedCount;
  final String overallDelayRisk;
  final double deterministicLossInr;
  final String aiExplanation;
  final List<String> recommendations;

  const ProductionImpactAssessmentModel({
    required this.id,
    required this.assessmentCode,
    required this.machineCode,
    required this.machineName,
    this.incidentCode,
    required this.estimatedDowntimeHours,
    required this.outputQuantityAtRisk,
    required this.ordersAffectedCount,
    required this.overallDelayRisk,
    required this.deterministicLossInr,
    required this.aiExplanation,
    this.recommendations = const [],
  });

  factory ProductionImpactAssessmentModel.fromJson(Map<String, dynamic> json) {
    final recsRaw = json['recommendations'];
    List<String> recs = [];
    if (recsRaw is List) {
      recs = recsRaw.map((e) => e.toString()).toList();
    }

    return ProductionImpactAssessmentModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      assessmentCode: json['assessment_code'] as String? ?? '',
      machineCode: json['machine_code'] as String? ?? '',
      machineName: json['machine_name'] as String? ?? json['machine_code'] as String? ?? '',
      incidentCode: json['incident_code'] as String?,
      estimatedDowntimeHours: NumericParser.parseDoubleWithFallback(json['estimated_downtime_hours'], 1.5),
      outputQuantityAtRisk: NumericParser.parseDoubleWithFallback(json['output_quantity_at_risk'], 0.0),
      ordersAffectedCount: (json['orders_affected_count'] as num?)?.toInt() ?? 0,
      overallDelayRisk: json['overall_delay_risk'] as String? ?? 'MEDIUM',
      deterministicLossInr: NumericParser.parseDoubleWithFallback(json['deterministic_loss_inr'], 0.0),
      aiExplanation: json['ai_explanation'] as String? ?? '',
      recommendations: recs,
    );
  }
}

class ProductionOverviewModel {
  final DateTime timestamp;
  final Map<String, dynamic> metrics;
  final List<DepartmentCapacityModel> departmentCapacities;
  final List<ProductionBottleneckModel> activeBottlenecks;
  final List<ProductionImpactAssessmentModel> recentImpactAssessments;

  const ProductionOverviewModel({
    required this.timestamp,
    required this.metrics,
    required this.departmentCapacities,
    required this.activeBottlenecks,
    required this.recentImpactAssessments,
  });

  factory ProductionOverviewModel.fromJson(Map<String, dynamic> json) {
    final capsRaw = json['department_capacities'];
    List<DepartmentCapacityModel> caps = [];
    if (capsRaw is List) {
      caps = capsRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => DepartmentCapacityModel.fromJson(e))
          .toList();
    }

    final bottlenecksRaw = json['active_bottlenecks'];
    List<ProductionBottleneckModel> bList = [];
    if (bottlenecksRaw is List) {
      bList = bottlenecksRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => ProductionBottleneckModel.fromJson(e))
          .toList();
    }

    final impactsRaw = json['recent_impact_assessments'];
    List<ProductionImpactAssessmentModel> impacts = [];
    if (impactsRaw is List) {
      impacts = impactsRaw
          .whereType<Map<String, dynamic>>()
          .map((e) => ProductionImpactAssessmentModel.fromJson(e))
          .toList();
    }

    return ProductionOverviewModel(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      metrics: json['metrics'] as Map<String, dynamic>? ?? {},
      departmentCapacities: caps,
      activeBottlenecks: bList,
      recentImpactAssessments: impacts,
    );
  }
}
