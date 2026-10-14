import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../models/copilot_models.dart';

class CopilotService {
  final http.Client _client;

  CopilotService({http.Client? client}) : _client = client ?? http.Client();

  /// Retrieves all conversation sessions.
  Future<List<CopilotSessionModel>> getSessions() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/copilot/sessions/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final list = decoded is List
            ? decoded
            : (decoded is Map<String, dynamic> && decoded.containsKey('results')
                ? decoded['results'] as List
                : []);
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => CopilotSessionModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Creates a new conversation session.
  Future<CopilotSessionModel?> createSession({
    String title = 'Factory Operations Consultation',
    String? activeMachineCode,
    String? activeIncidentCode,
  }) async {
    final payload = <String, dynamic>{'title': title};
    if (activeMachineCode != null) payload['active_machine_code'] = activeMachineCode;
    if (activeIncidentCode != null) payload['active_incident_code'] = activeIncidentCode;

    final uri = Uri.parse('${AppConfig.baseUrl}/copilot/sessions/');
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return CopilotSessionModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves messages for a specific session.
  Future<List<CopilotMessageModel>> getSessionMessages(String sessionId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/copilot/sessions/$sessionId/messages/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawList = data['messages'] as List<dynamic>? ?? [];
        return rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => CopilotMessageModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Sends a question to the Copilot.
  Future<CopilotMessageModel?> sendMessage(String sessionId, String text) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/copilot/sessions/$sessionId/chat/');
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'message': text}),
          )
          .timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return CopilotMessageModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves contextual prompt suggestions.
  Future<List<SuggestedQuestionModel>> getSuggestions() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/copilot/suggestions/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawList = data['suggestions'] as List<dynamic>? ?? [];
        return rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => SuggestedQuestionModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
