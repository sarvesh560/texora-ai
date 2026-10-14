import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../models/health_status_model.dart';
import '../models/simulation_model.dart';
import '../models/incident_model.dart';
import '../models/ai_agent_model.dart';
import '../models/recovery_models.dart';
import '../models/digital_twin_models.dart';

class ApiService {
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches basic API health from GET /api/v1/health/
  Future<HealthStatusModel> checkHealth() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/health/');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      final rawBody = response.body;

      if (response.statusCode == 200) {
        final data = json.decode(rawBody) as Map<String, dynamic>;
        return HealthStatusModel.fromJson(data, latencyMs: latency, rawJson: rawBody);
      } else {
        return HealthStatusModel.error(
          errorMessage: 'Server responded with HTTP ${response.statusCode}',
          latencyMs: latency,
          rawJson: rawBody,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return HealthStatusModel.error(
        errorMessage: 'Connection failed: ${e.toString()}',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Fetches database readiness from GET /api/v1/health/readiness/
  Future<HealthStatusModel> checkReadiness() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/health/readiness/');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      final rawBody = response.body;

      if (response.statusCode == 200) {
        final data = json.decode(rawBody) as Map<String, dynamic>;
        return HealthStatusModel.fromJson(data, latencyMs: latency, rawJson: rawBody);
      } else {
        return HealthStatusModel.error(
          errorMessage: 'Database readiness check returned status ${response.statusCode}',
          latencyMs: latency,
          rawJson: rawBody,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return HealthStatusModel.error(
        errorMessage: 'Readiness check failed: ${e.toString()}',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Fetches daemon heartbeat and worker health status from GET /api/v1/health/workers/
  Future<SystemHealthSummaryModel?> fetchWorkerHealth() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/health/workers/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return SystemHealthSummaryModel.fromJson(data);
      }
    } catch (e) {
      // Fallback null
    }
    return null;
  }

  /// Fetches simulation and live factory summary from GET /api/v1/simulation/summary/
  Future<SimulationSummaryModel?> fetchSimulationSummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return SimulationSummaryModel.fromJson(data);
      }
    } catch (e) {
      // Return null on failure
    }
    return null;
  }

  /// Starts the backend simulation engine
  Future<bool> startSimulation({double speedMultiplier = 1.0, double intervalSeconds = 3.0}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/start/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'speed_multiplier': speedMultiplier,
          'tick_interval_seconds': intervalSeconds,
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Pauses the simulation engine
  Future<bool> pauseSimulation() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/pause/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Resumes the simulation engine
  Future<bool> resumeSimulation() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/resume/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Stops the simulation engine
  Future<bool> stopSimulation() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/stop/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Manually executes 1 discrete simulation tick
  Future<bool> triggerManualTick() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/tick/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Injects an operational scenario
  Future<bool> injectScenario({
    required String scenarioType,
    String machineCode = '',
    String departmentCode = '',
    String severity = 'HIGH',
    String description = '',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/inject-scenario/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'scenario_type': scenarioType,
          'target_machine_code': machineCode,
          'target_department_code': departmentCode,
          'severity': severity,
          'description': description,
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  /// Clears all active scenarios
  Future<bool> clearScenarios({int? scenarioId}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/simulation/clear-scenarios/');
    try {
      final body = scenarioId != null ? {'scenario_id': scenarioId} : <String, dynamic>{};
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Fetches incidents and anomaly detection summary from GET /api/v1/incidents/summary/
  Future<IncidentsSummaryModel?> fetchIncidentsSummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/incidents/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return IncidentsSummaryModel.fromJson(data);
      }
    } catch (e) {
      // return null on failure
    }
    return null;
  }

  /// Fetches raw list of incidents from GET /api/v1/incidents/
  Future<List<dynamic>> fetchIncidents() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/incidents/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map<String, dynamic> && data['results'] is List) {
          return data['results'] as List<dynamic>;
        }
      }
    } catch (e) {
      // return empty
    }
    return [];
  }

  /// Fetches raw list of agent executions from GET /api/v1/executions/
  Future<List<dynamic>> fetchAgentExecutions() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/executions/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map<String, dynamic> && data['results'] is List) {
          return data['results'] as List<dynamic>;
        }
      }
    } catch (e) {
      // return empty
    }
    return [];
  }

  /// Manually triggers 1 anomaly evaluation cycle
  Future<bool> triggerDetectionEval({int batchSize = 100}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/incidents/run-eval/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'batch_size': batchSize}),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Manually marks an incident as resolved
  Future<bool> resolveIncident(int incidentId, {String notes = 'Manually resolved'}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/incidents/$incidentId/resolve/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'resolution_notes': notes}),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Fetches AI Agent operations summary from GET /api/v1/executions/summary/
  Future<AgentSummaryModel?> fetchAgentSummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/executions/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return AgentSummaryModel.fromJson(data);
      }
    } catch (e) {
      // return null on failure
    }
    return null;
  }

  /// Triggers on-demand Machine Health Agent investigation for an incident
  Future<Map<String, dynamic>> triggerInvestigation(int incidentId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/executions/investigate/$incidentId/');
    try {
      final response = await _client.post(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200 || response.statusCode == 400) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}: ${response.body}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Triggers an autonomous evaluation cycle across pending incidents
  Future<Map<String, dynamic>> triggerAgentCycle() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/executions/run-cycle/');
    try {
      final response = await _client.post(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'error': 'HTTP ${response.statusCode}'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetches pending approval requests from GET /api/v1/approvals/
  Future<List<ApprovalRequestModel>> fetchApprovals() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/?status=PENDING');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> list = (data is List) ? data : (data['results'] as List<dynamic>? ?? []);
        return list.map((e) => ApprovalRequestModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // return empty
    }
    return [];
  }

  /// Approves an action request with role-based parameters
  Future<bool> approveRequest(
    int approvalId, {
    String approvedBy = 'Operations Manager',
    String userRole = 'MAINTENANCE_MANAGER',
    String notes = 'Approved via Dashboard',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/approve/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'approved_by': approvedBy,
          'user_role': userRole,
          'response_notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Rejects an action request with role-based parameters
  Future<bool> rejectRequest(
    int approvalId, {
    String rejectedBy = 'Operations Manager',
    String userRole = 'MAINTENANCE_MANAGER',
    String notes = 'Rejected by Manager',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/reject/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'approved_by': rejectedBy,
          'user_role': userRole,
          'response_notes': notes,
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // PHASE 6: RECOVERY COORDINATION APIS
  // ==========================================

  /// Fetches summary metrics for Factory Recovery Command Center
  Future<Map<String, dynamic>> fetchRecoverySummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/recovery-cases/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // return empty on error
    }
    return {};
  }

  /// Fetches recovery metrics summary
  Future<RecoverySummaryModel> getRecoverySummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/recovery-cases/summary/');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return RecoverySummaryModel.fromJson(data);
    }
    throw Exception('Failed to load recovery summary (HTTP ${response.statusCode})');
  }

  /// Fetches list of Recovery Cases as typed models
  Future<List<RecoveryCaseModel>> getRecoveryCases({String? statusFilter}) async {
    String url = '${AppConfig.baseUrl}/recovery-cases/';
    if (statusFilter != null && statusFilter.isNotEmpty && statusFilter != 'ALL') {
      url += '?status=$statusFilter';
    }
    final uri = Uri.parse(url);
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      List<dynamic> list = [];
      if (data is List) list = data;
      if (data is Map && data.containsKey('results')) list = data['results'] as List<dynamic>;
      return list.map((item) => RecoveryCaseModel.fromJson(item as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load recovery cases (HTTP ${response.statusCode})');
  }

  /// Fetches single Recovery Case with steps and multi-agent findings
  Future<RecoveryCaseModel> getRecoveryCaseDetail(int caseId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/recovery-cases/$caseId/');
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return RecoveryCaseModel.fromJson(json.decode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to load recovery case detail: ${response.statusCode}');
  }

  /// Approves a sensitive recovery action with RBAC identity
  Future<Map<String, dynamic>> approveAction(
    int approvalId,
    String role,
    String managerName,
    String notes,
  ) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/approve/');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'approved_by': '$managerName [$role]',
        'response_notes': notes,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final data = json.decode(response.body);
      throw Exception(data is Map && data.containsKey('error') ? data['error'] : 'Approval failed with HTTP ${response.statusCode}');
    }
  }

  /// Rejects a sensitive recovery action with RBAC identity
  Future<Map<String, dynamic>> rejectAction(
    int approvalId,
    String role,
    String managerName,
    String reason,
  ) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/reject/');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'approved_by': '$managerName [$role]',
        'response_notes': reason,
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final data = json.decode(response.body);
      throw Exception(data is Map && data.containsKey('error') ? data['error'] : 'Rejection failed with HTTP ${response.statusCode}');
    }
  }

  /// Fetches list of Recovery Cases
  Future<List<dynamic>> fetchRecoveryCases({String? statusFilter}) async {
    String url = '${AppConfig.baseUrl}/recovery-cases/';
    if (statusFilter != null && statusFilter.isNotEmpty) {
      url += '?status=$statusFilter';
    }
    final uri = Uri.parse(url);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map && data.containsKey('results')) return data['results'] as List<dynamic>;
      }
    } catch (e) {
      // return empty
    }
    return [];
  }

  /// Fetches single Recovery Case with steps and multi-agent findings
  Future<Map<String, dynamic>> fetchRecoveryCaseDetail(int caseId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/recovery-cases/$caseId/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // error
    }
    return {};
  }

  /// Triggers multi-agent factory recovery orchestration for an incident
  Future<Map<String, dynamic>> orchestrateRecovery(int incidentId, {bool forceReanalyze = false}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/recovery-cases/orchestrate/$incidentId/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'force_reanalyze': forceReanalyze}),
      ).timeout(const Duration(seconds: 35));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        return {'success': false, 'error': 'Server responded with status ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetches Factory Digital Twin Snapshot
  Future<DigitalTwinSnapshotModel?> fetchDigitalTwinSnapshot({bool refresh = false}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/snapshot/?refresh=$refresh');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['data'] != null) {
          return DigitalTwinSnapshotModel.fromJson(data['data'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      // return null on error
    }
    return null;
  }

  /// Fetches specific machine digital twin details
  Future<MachineTwinModel?> fetchDigitalTwinMachineDetail(String machineCode) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/machines/$machineCode/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['machine'] != null) {
          return MachineTwinModel.fromJson(data['machine'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      // error
    }
    return null;
  }

  /// Fetches factory material flow dependency graph topology
  Future<Map<String, dynamic>> fetchFactoryDependencyGraph() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/dependency-graph/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // error
    }
    return {};
  }

  /// Fetches What-If scenario history
  Future<List<WhatIfScenarioModel>> fetchWhatIfScenarios() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/what-if/scenarios/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        var list = data['scenarios'] as List? ?? [];
        return list.map((s) => WhatIfScenarioModel.fromJson(s as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // error
    }
    return [];
  }

  /// Creates and immediately simulates a What-If scenario
  Future<Map<String, dynamic>> createWhatIfScenario(Map<String, dynamic> payload) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/what-if/scenarios/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 201) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        return {'status': 'error', 'message': 'HTTP ${response.statusCode}: ${response.body}'};
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  /// Fetches What-If simulation results, strategy evaluations, and timeline playback
  Future<Map<String, dynamic>> fetchWhatIfResults(String scenarioId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/what-if/scenarios/$scenarioId/results/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // error
    }
    return {};
  }

  /// Requests AI Strategy Explanation from Gemini (with fallback)
  Future<AIStrategyExplanationModel?> requestAIStrategyExplanation(String scenarioId, {String? forceProvider}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/what-if/scenarios/$scenarioId/ai-explain/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(forceProvider != null ? {'force_provider': forceProvider} : {}),
      ).timeout(const Duration(seconds: 40));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['ai_explanation'] != null) {
          return AIStrategyExplanationModel.fromJson(data['ai_explanation'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      // error
    }
    return null;
  }

  /// Fetches the 3 Expo demonstration scenarios
  Future<List<DemoScenarioModel>> fetchWhatIfDemoScenarios() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/what-if/demo-scenarios/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        var list = data['demo_scenarios'] as List? ?? [];
        return list.map((d) => DemoScenarioModel.fromJson(d as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // error
    }
    return [];
  }

  /// Loads and executes one of the 3 Expo Demo Scenarios
  Future<Map<String, dynamic>> loadWhatIfDemoScenario(String demoCode) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/digital-twin/what-if/demo-scenarios/$demoCode/load/');
    try {
      final response = await _client.post(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
    return {'status': 'error', 'message': 'Failed to load demo scenario'};
  }

  // ==========================================
  // PHASE 9: AUTONOMOUS FACTORY ORCHESTRATION
  // ==========================================

  /// Fetches Autonomous Operations Status & Worker Health from GET /api/v1/autonomous/status/
  Future<Map<String, dynamic>> fetchAutonomousStatus() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/status/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // error
    }
    return {};
  }

  /// Fetches list of Autonomous Workflow Runs from GET /api/v1/autonomous/
  Future<List<dynamic>> fetchAutonomousRuns() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map<String, dynamic> && data['results'] is List) {
          return data['results'] as List<dynamic>;
        }
      }
    } catch (e) {
      // error
    }
    return [];
  }

  /// Triggers full autonomous pipeline for an incident
  Future<Map<String, dynamic>> triggerAutonomousIncident(int incidentId, {String? forceProvider}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/trigger-incident/');
    try {
      final Map<String, dynamic> bodyPayload = {
        'incident_id': incidentId,
      };
      if (forceProvider != null) {
        bodyPayload['force_provider'] = forceProvider;
      }
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyPayload),
      ).timeout(const Duration(seconds: 45));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Launches the One-Click PSG Expo Demo Scenario
  Future<Map<String, dynamic>> launchAutonomousExpoDemo({String machineCode = 'WEV-RAP-01'}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/expo-demo/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'machine_code': machineCode}),
      ).timeout(const Duration(seconds: 45));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Advances workflow post-manager approval with selected strategy
  Future<Map<String, dynamic>> advanceAutonomousApproval({
    required int recoveryCaseId,
    int? approvalRequestId,
    String approvedBy = 'Operations Manager',
    String? selectedStrategy,
    String? responseNotes,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/advance-approval/');
    try {
      final Map<String, dynamic> bodyPayload = {
        'recovery_case_id': recoveryCaseId,
        'approved_by': approvedBy,
      };
      if (approvalRequestId != null) {
        bodyPayload['approval_request_id'] = approvalRequestId;
      }
      if (selectedStrategy != null) {
        bodyPayload['selected_strategy'] = selectedStrategy;
      }
      if (responseNotes != null) {
        bodyPayload['response_notes'] = responseNotes;
      }

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyPayload),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Performs technician recovery verification check
  Future<Map<String, dynamic>> verifyTechnicianRecovery({
    required int recoveryCaseId,
    String technicianName = 'Lead Maintenance Technician',
    String repairNotes = 'Physical inspection completed, bearings replaced.',
    bool checkFreshness = true,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/verify-recovery/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'recovery_case_id': recoveryCaseId,
          'technician_name': technicianName,
          'repair_notes': repairNotes,
          'check_freshness': checkFreshness,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'verified': false, 'error': e.toString()};
    }
  }

  /// Request revision on an approval request
  Future<bool> requestApprovalRevision(int approvalId, {String? notes, String? requestedBy}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/request-revision/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'approved_by': requestedBy ?? 'Operations Director',
          'response_notes': notes ?? 'Revision requested: evaluate alternate machine reroute.',
        }),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Fetches rich multi-panel intelligence workspace data for a specific incident
  Future<Map<String, dynamic>?> fetchIncidentIntelligence(int incidentId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/incidents/$incidentId/intelligence/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetches immutable operational and AI governance audit logs
  Future<List<Map<String, dynamic>>> fetchAuditLogs({
    String? entityType,
    String? action,
    String? actorType,
    String? search,
  }) async {
    final queryParams = <String, String>{};
    if (entityType != null && entityType.isNotEmpty && entityType != 'ALL') {
      queryParams['entity_type'] = entityType;
    }
    if (action != null && action.isNotEmpty && action != 'ALL') {
      queryParams['action'] = action;
    }
    if (actorType != null && actorType.isNotEmpty && actorType != 'ALL') {
      queryParams['actor_type'] = actorType;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/audit-logs/').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('results')) {
          return List<Map<String, dynamic>>.from(data['results']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetches all manager approval requests with optional status filtering
  Future<List<Map<String, dynamic>>> fetchApprovalRequestsList({String? status, String? search}) async {
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty && status != 'ALL') {
      queryParams['status'] = status;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('results')) {
          return List<Map<String, dynamic>>.from(data['results']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Directly approve an approval request
  Future<Map<String, dynamic>> approveApprovalRequest(
    int approvalId, {
    required String approvedBy,
    required String responseNotes,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/approve/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'approved_by': approvedBy,
          'response_notes': responseNotes,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Directly reject an approval request
  Future<Map<String, dynamic>> rejectApprovalRequest(
    int approvalId, {
    required String rejectedBy,
    required String responseNotes,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/reject/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'approved_by': rejectedBy,
          'response_notes': responseNotes,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Request revision on an approval request
  Future<Map<String, dynamic>> requestRevisionApprovalRequest(
    int approvalId, {
    required String reviewedBy,
    required String revisionNotes,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/approvals/$approvalId/request-revision/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'approved_by': reviewedBy,
          'response_notes': revisionNotes,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Fetches typed list of FactoryIncidents
  Future<List<FactoryIncidentModel>> getFactoryIncidents() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/incidents/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is Map && data.containsKey('results')) {
          list = data['results'] as List<dynamic>;
        }
        return list.map((item) => FactoryIncidentModel.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // return empty
    }
    return [];
  }

  /// Fetches recent time-series telemetry readings for a specific machine
  Future<List<Map<String, dynamic>>> fetchMachineTelemetry(int machineId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/machines/$machineId/telemetry/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('results')) {
          return List<Map<String, dynamic>>.from(data['results']);
        }
      }
    } catch (e) {
      // return empty
    }
    return [];
  }

  /// Fetches operations overview for the four specialist agents
  Future<Map<String, dynamic>?> getAgentOperationsOverview() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/ai-agents/operations-overview/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Return null on failure
    }
    return null;
  }

  /// Fetches all registered AI agents from /agents/
  Future<List<Map<String, dynamic>>> getRegisteredAgents() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/agents/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return List<Map<String, dynamic>>.from(decoded);
        } else if (decoded is Map && decoded['results'] is List) {
          return List<Map<String, dynamic>>.from(decoded['results']);
        }
      }
    } catch (e) {
      // Return empty on failure
    }
    return [];
  }

  /// Fetches deep audit details for a specific agent execution
  Future<Map<String, dynamic>?> getAgentExecutionAuditDetails(String execId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/ai-agents/audit-details/$execId/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Return null on failure
    }
    return null;
  }

  /// Fetches the live 12-stage workflow progress for an incident
  Future<Map<String, dynamic>?> getIncidentWorkflow(int incidentId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/incident-workflow/$incidentId/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Return null on failure
    }
    return null;
  }

  /// Fetches financial and operational business impact for an incident
  Future<Map<String, dynamic>?> getBusinessImpact(int incidentId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/business-impact/$incidentId/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Return null on failure
    }
    return null;
  }

  /// Fetches readiness and status for the controlled demonstration mode
  Future<Map<String, dynamic>?> getDemoStatus() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/demo-status/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Return null on failure
    }
    return null;
  }

  /// Triggers a controlled commercial demonstration run
  Future<Map<String, dynamic>> triggerExpoDemo({
    String machineCode = 'WEV-AJ-02',
    String? forceProvider,
    bool forceReanalyze = true,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/autonomous/expo-demo/');
    try {
      final payload = {
        'machine_code': machineCode,
        'force_provider': forceProvider,
        'force_reanalyze': forceReanalyze,
      };
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'Server returned HTTP ${response.statusCode}: ${response.body}',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ==========================================
  // PHASE 12: MAINTENANCE EXECUTION & VERIFICATION
  // ==========================================

  /// Fetches maintenance tickets with optional status and priority filter
  Future<List<Map<String, dynamic>>> fetchMaintenanceTickets({
    String? status,
    String? priority,
    String? search,
  }) async {
    final queryParams = <String, String>{};
    if (status != null && status.isNotEmpty && status != 'ALL') {
      queryParams['status'] = status;
    }
    if (priority != null && priority.isNotEmpty && priority != 'ALL') {
      queryParams['priority'] = priority;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else if (data is Map && data.containsKey('results')) {
          return List<Map<String, dynamic>>.from(data['results']);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetches comprehensive execution detail for a work order ticket
  Future<Map<String, dynamic>?> fetchWorkOrderExecutionDetail(int ticketId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/execution-detail/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // return null
    }
    return null;
  }

  /// Executes state transition for a work order ticket
  Future<Map<String, dynamic>> transitionWorkOrder(
    int ticketId, {
    required String newState,
    required String actor,
    String actorRole = 'Technician',
    String reason = '',
    Map<String, dynamic>? payload,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/transition/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'new_state': newState,
          'actor': actor,
          'actor_role': actorRole,
          'reason': reason,
          'payload': payload ?? {},
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Submits guided inspection results and confirms physical fault
  Future<Map<String, dynamic>> submitWorkOrderInspection(
    int ticketId, {
    required List<Map<String, dynamic>> checklist,
    required String confirmedFault,
    String notes = '',
    required String actor,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/submit-inspection/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'checklist': checklist,
          'confirmed_fault': confirmedFault,
          'notes': notes,
          'actor': actor,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Consumes spare parts safely with transaction guard
  Future<Map<String, dynamic>> consumeWorkOrderParts(
    int ticketId, {
    required List<Map<String, dynamic>> parts,
    required String actor,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/consume-parts/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'parts': parts,
          'actor': actor,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Documents physical repair completion
  Future<Map<String, dynamic>> completeWorkOrderRepair(
    int ticketId, {
    required String repairPerformed,
    required int durationMinutes,
    String remainingIssues = '',
    required String actor,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/complete-repair/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'repair_performed': repairPerformed,
          'actual_duration_minutes': durationMinutes,
          'remaining_issues': remainingIssues,
          'actor': actor,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Triggers Recovery Verification Engine evaluation
  Future<Map<String, dynamic>> verifyWorkOrderRecovery(
    int ticketId, {
    int observationWindow = 5,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/verify-recovery/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'observation_window': observationWindow}),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Authorized return to service sign-off
  Future<Map<String, dynamic>> authorizeReturnToService(
    int ticketId, {
    required String authorizedBy,
    String role = 'Plant Operations Manager',
    String notes = '',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/authorize-return-to-service/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'authorized_by': authorizedBy,
          'role': role,
          'notes': notes,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Closes incident only with verified evidence
  Future<Map<String, dynamic>> closeWorkOrderWithEvidence(
    int ticketId, {
    required String closedBy,
    String notes = '',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/close-with-evidence/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'closed_by': closedBy,
          'notes': notes,
        }),
      ).timeout(const Duration(seconds: 15));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Simulates guided technician repair flow for expo demo
  Future<Map<String, dynamic>> simulateTechnicianFlow(
    int ticketId, {
    String mode = 'HEALTHY',
    String actor = 'R. Sharma (Senior Diagnostic Tech)',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/maintenance/tickets/$ticketId/simulate-technician-flow/');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'mode': mode,
          'actor': actor,
        }),
      ).timeout(const Duration(seconds: 20));
      return json.decode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // ==========================================
  // QUALITY INSPECTION & LABORATORY APIS
  // ==========================================

  Future<Map<String, dynamic>?> getQualitySummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/inspections/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getQualityInspections({String? status}) async {
    String url = '${AppConfig.baseUrl}/inspections/';
    if (status != null && status.isNotEmpty && status != 'ALL') {
      url += '?status=$status';
    }
    final uri = Uri.parse(url);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        } else if (decoded is Map && decoded['results'] is List) {
          return (decoded['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ==========================================
  // INVENTORY & SPARE PARTS APIS
  // ==========================================

  Future<Map<String, dynamic>?> getInventorySummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/items/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getInventoryItems({String? category}) async {
    String url = '${AppConfig.baseUrl}/items/';
    if (category != null && category.isNotEmpty && category != 'ALL') {
      url += '?category=$category';
    }
    final uri = Uri.parse(url);
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        } else if (decoded is Map && decoded['results'] is List) {
          return (decoded['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getInventoryTransactions() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/transactions/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        } else if (decoded is Map && decoded['results'] is List) {
          return (decoded['results'] as List).cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ==========================================
  // ELECTRICAL ENERGY & SUB-METERING APIS
  // ==========================================

  Future<Map<String, dynamic>?> getEnergySummary() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/readings/summary/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getEnergyReadings({int limit = 50}) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/readings/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded.take(limit).toList().cast<Map<String, dynamic>>();
        } else if (decoded is Map && decoded['results'] is List) {
          return (decoded['results'] as List).take(limit).toList().cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ==========================================
  // UNIFIED FACTORY REPORTS & ANALYTICS APIS
  // ==========================================

  Future<Map<String, dynamic>?> getReportsOverview({
    String category = 'factory_overview',
    String range = 'today',
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/reports/overview/?category=$category&range=$range');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String getReportsExportCsvUrl({String category = 'factory_overview', String range = 'today'}) {
    return '${AppConfig.baseUrl}/reports/export/?category=$category&range=$range';
  }

  Future<String?> fetchReportsCsv({
    String category = 'factory_overview',
    String range = 'today',
  }) async {
    final uri = Uri.parse(getReportsExportCsvUrl(category: category, range: range));
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return response.body;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}


