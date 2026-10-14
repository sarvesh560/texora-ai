class CopilotReference {
  final String type; // machine, incident, ticket, inventory, approval
  final String id;
  final String label;

  const CopilotReference({
    required this.type,
    required this.id,
    required this.label,
  });

  factory CopilotReference.fromJson(Map<String, dynamic> json) {
    return CopilotReference(
      type: json['type'] as String? ?? 'general',
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? json['id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'label': label,
      };
}

class CopilotMessageModel {
  final int? id;
  final String role; // user, assistant, system
  final String content;
  final List<String> facts;
  final List<String> estimates;
  final List<String> recommendations;
  final List<CopilotReference> references;
  final List<dynamic> evidenceRecords;
  final String missingEvidence;
  final bool isSimulated;
  final String simulationDisclosure;
  final String provider;
  final String model;
  final int latencyMs;
  final String reasoningSource;
  final DateTime createdAt;

  const CopilotMessageModel({
    this.id,
    required this.role,
    required this.content,
    this.facts = const [],
    this.estimates = const [],
    this.recommendations = const [],
    this.references = const [],
    this.evidenceRecords = const [],
    this.missingEvidence = '',
    this.isSimulated = true,
    this.simulationDisclosure = '',
    this.provider = 'deterministic_fallback',
    this.model = 'fallback-rules-v1',
    this.latencyMs = 0,
    this.reasoningSource = 'DETERMINISTIC_FALLBACK',
    required this.createdAt,
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  factory CopilotMessageModel.fromJson(Map<String, dynamic> json) {
    final rawRefs = json['references'] as List<dynamic>? ?? [];
    final references = rawRefs
        .whereType<Map<String, dynamic>>()
        .map((e) => CopilotReference.fromJson(e))
        .toList();

    final factsList = (json['facts'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final estimatesList = (json['estimates'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final recsList = (json['recommendations'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    DateTime parsedDate;
    try {
      parsedDate = json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return CopilotMessageModel(
      id: json['id'] as int?,
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      facts: factsList,
      estimates: estimatesList,
      recommendations: recsList,
      references: references,
      evidenceRecords: json['evidence_records'] as List<dynamic>? ?? [],
      missingEvidence: json['missing_evidence'] as String? ?? '',
      isSimulated: json['is_simulated'] as bool? ?? true,
      simulationDisclosure: json['simulation_disclosure'] as String? ??
          'Simulated factory demonstration data.',
      provider: json['provider'] as String? ?? 'groq',
      model: json['model'] as String? ?? 'qwen/qwen3.8-27b',
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      reasoningSource: json['reasoning_source'] as String? ?? 'GROQ_LIVE',
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'role': role,
        'content': content,
        'facts': facts,
        'estimates': estimates,
        'recommendations': recommendations,
        'references': references.map((r) => r.toJson()).toList(),
        'evidence_records': evidenceRecords,
        'missing_evidence': missingEvidence,
        'is_simulated': isSimulated,
        'simulation_disclosure': simulationDisclosure,
        'provider': provider,
        'model': model,
        'latency_ms': latencyMs,
        'reasoning_source': reasoningSource,
        'created_at': createdAt.toIso8601String(),
      };
}

class CopilotSessionModel {
  final int? id;
  final String sessionId;
  final String title;
  final String? activeMachineCode;
  final String? activeIncidentCode;
  final int messageCount;
  final String? latestMessageSnippet;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CopilotSessionModel({
    this.id,
    required this.sessionId,
    required this.title,
    this.activeMachineCode,
    this.activeIncidentCode,
    this.messageCount = 0,
    this.latestMessageSnippet,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CopilotSessionModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    String? snippet;
    if (json['latest_message'] is Map<String, dynamic>) {
      snippet = json['latest_message']['content'] as String?;
    }

    return CopilotSessionModel(
      id: json['id'] as int?,
      sessionId: json['session_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Factory Consultation',
      activeMachineCode: json['active_machine_code'] as String?,
      activeIncidentCode: json['active_incident_code'] as String?,
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
      latestMessageSnippet: snippet,
      createdAt: parseDate(json['created_at']),
      updatedAt: parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'title': title,
        'active_machine_code': activeMachineCode,
        'active_incident_code': activeIncidentCode,
        'message_count': messageCount,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class SuggestedQuestionModel {
  final String id;
  final String category;
  final String prompt;
  final String description;
  final String? targetEntity;

  const SuggestedQuestionModel({
    required this.id,
    required this.category,
    required this.prompt,
    required this.description,
    this.targetEntity,
  });

  factory SuggestedQuestionModel.fromJson(Map<String, dynamic> json) {
    return SuggestedQuestionModel(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? 'GENERAL',
      prompt: json['prompt'] as String? ?? '',
      description: json['description'] as String? ?? '',
      targetEntity: json['target_entity'] as String?,
    );
  }
}
