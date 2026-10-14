import '../../core/utils/numeric_parser.dart';

class QualityDefectModel {
  final int id;
  final int inspectionId;
  final String defectType;
  final String defectTypeDisplay;
  final String severity;
  final int count;
  final String defectLocation;
  final String rootCauseCategory;
  final String imageUrl;

  QualityDefectModel({
    required this.id,
    this.inspectionId = 0,
    required this.defectType,
    this.defectTypeDisplay = '',
    this.severity = 'MINOR',
    this.count = 1,
    this.defectLocation = '',
    this.rootCauseCategory = '',
    this.imageUrl = '',
  });

  factory QualityDefectModel.fromJson(Map<String, dynamic> json) {
    return QualityDefectModel(
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
      inspectionId: parseIntWithFallback(json['inspection'], 0, fieldName: 'inspection'),
      defectType: (json['defect_type'] ?? 'DEFECT').toString(),
      defectTypeDisplay: (json['defect_type_display'] ?? json['display'] ?? json['label'] ?? json['defect_type'] ?? '').toString(),
      severity: (json['severity'] ?? 'MINOR').toString(),
      count: parseIntWithFallback(json['count'], 1, fieldName: 'count'),
      defectLocation: (json['defect_location'] ?? '').toString(),
      rootCauseCategory: (json['root_cause_category'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'inspection': inspectionId,
    'defect_type': defectType,
    'defect_type_display': defectTypeDisplay,
    'severity': severity,
    'count': count,
    'defect_location': defectLocation,
    'root_cause_category': rootCauseCategory,
    'image_url': imageUrl,
  };
}

class QualityInspectionModel {
  final int id;
  final String inspectionCode;
  final int? productionBatch;
  final String batchNumber;
  final int? machine;
  final String machineCode;
  final String inspectorName;
  final double sampleSize;
  final double inspectedQuantity;
  final double acceptedQuantity;
  final double rejectedQuantity;
  final String status;
  final double overallScore;
  final String inspectedAt;
  final String notes;
  final List<QualityDefectModel> defects;

  QualityInspectionModel({
    required this.id,
    required this.inspectionCode,
    this.productionBatch,
    this.batchNumber = '',
    this.machine,
    this.machineCode = '',
    this.inspectorName = 'QA Lab',
    required this.sampleSize,
    required this.inspectedQuantity,
    required this.acceptedQuantity,
    this.rejectedQuantity = 0.0,
    this.status = 'PASSED',
    this.overallScore = 98.0,
    this.inspectedAt = '',
    this.notes = '',
    this.defects = const [],
  });

  factory QualityInspectionModel.fromJson(Map<String, dynamic> json) {
    final rawDefects = json['defects'] as List? ?? [];
    final defectsList = rawDefects
        .whereType<Map<String, dynamic>>()
        .map((d) => QualityDefectModel.fromJson(d))
        .toList();

    return QualityInspectionModel(
      id: parseIntWithFallback(json['id'], 0, fieldName: 'id'),
      inspectionCode: (json['inspection_code'] ?? '').toString(),
      productionBatch: parseNullableInt(json['production_batch'], fieldName: 'production_batch'),
      batchNumber: (json['batch_number'] ?? '').toString(),
      machine: parseNullableInt(json['machine'], fieldName: 'machine'),
      machineCode: (json['machine_code'] ?? '').toString(),
      inspectorName: (json['inspector_name'] ?? 'QA Lab').toString(),
      sampleSize: parseDoubleWithFallback(json['sample_size'], 0.0, fieldName: 'sample_size'),
      inspectedQuantity: parseDoubleWithFallback(json['inspected_quantity'], 0.0, fieldName: 'inspected_quantity'),
      acceptedQuantity: parseDoubleWithFallback(json['accepted_quantity'], 0.0, fieldName: 'accepted_quantity'),
      rejectedQuantity: parseDoubleWithFallback(json['rejected_quantity'], 0.0, fieldName: 'rejected_quantity'),
      status: (json['status'] ?? 'PASSED').toString(),
      overallScore: parseDoubleWithFallback(json['overall_score'], 98.0, fieldName: 'overall_score'),
      inspectedAt: (json['inspected_at'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      defects: defectsList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'inspection_code': inspectionCode,
    'production_batch': productionBatch,
    'batch_number': batchNumber,
    'machine': machine,
    'machine_code': machineCode,
    'inspector_name': inspectorName,
    'sample_size': sampleSize,
    'inspected_quantity': inspectedQuantity,
    'accepted_quantity': acceptedQuantity,
    'rejected_quantity': rejectedQuantity,
    'status': status,
    'overall_score': overallScore,
    'inspected_at': inspectedAt,
    'notes': notes,
    'defects': defects.map((d) => d.toJson()).toList(),
  };
}

class QualitySummaryModel {
  final int totalInspections;
  final int passedCount;
  final int failedCount;
  final int conditionalCount;
  final double passRatePct;
  final double averageQualityScore;
  final int totalDefectsLogged;
  final List<Map<String, dynamic>> defectsByType;
  final Map<String, dynamic> defectsBySeverity;

  QualitySummaryModel({
    required this.totalInspections,
    required this.passedCount,
    required this.failedCount,
    required this.conditionalCount,
    required this.passRatePct,
    required this.averageQualityScore,
    required this.totalDefectsLogged,
    required this.defectsByType,
    required this.defectsBySeverity,
  });

  factory QualitySummaryModel.fromJson(Map<String, dynamic> json) {
    final rawTypes = json['defects_by_type'] as List? ?? [];
    final types = rawTypes.whereType<Map<String, dynamic>>().toList();

    final sev = json['defects_by_severity'] is Map<String, dynamic>
        ? json['defects_by_severity'] as Map<String, dynamic>
        : <String, dynamic>{};

    return QualitySummaryModel(
      totalInspections: parseIntWithFallback(json['total_inspections'], 0, fieldName: 'total_inspections'),
      passedCount: parseIntWithFallback(json['passed_count'], 0, fieldName: 'passed_count'),
      failedCount: parseIntWithFallback(json['failed_count'], 0, fieldName: 'failed_count'),
      conditionalCount: parseIntWithFallback(json['conditional_count'], 0, fieldName: 'conditional_count'),
      passRatePct: parseDoubleWithFallback(json['pass_rate_pct'], 100.0, fieldName: 'pass_rate_pct'),
      averageQualityScore: parseDoubleWithFallback(json['average_quality_score'], 0.0, fieldName: 'average_quality_score'),
      totalDefectsLogged: parseIntWithFallback(json['total_defects_logged'], 0, fieldName: 'total_defects_logged'),
      defectsByType: types,
      defectsBySeverity: sev,
    );
  }
}
