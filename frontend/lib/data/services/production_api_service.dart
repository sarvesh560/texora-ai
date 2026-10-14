import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../models/production_models.dart';

class ProductionApiService {
  final http.Client _client;

  ProductionApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Retrieves high-level production overview, capacities, and bottlenecks.
  Future<ProductionOverviewModel?> fetchProductionOverview() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/overview/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ProductionOverviewModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves list of production orders, optionally filtered.
  Future<List<ProductionOrderModel>> fetchOrders({
    String? status,
    String? priority,
    String? riskLevel,
  }) async {
    final params = <String, String>{};
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (priority != null && priority.isNotEmpty) params['priority'] = priority;
    if (riskLevel != null && riskLevel.isNotEmpty) params['delay_risk_level'] = riskLevel;

    final uri = Uri.parse('${AppConfig.baseUrl}/production/orders/').replace(
      queryParameters: params.isNotEmpty ? params : null,
    );

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
            .map((e) => ProductionOrderModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Retrieves single order detail with assignments and history.
  Future<ProductionOrderModel?> fetchOrderDetail(int orderId) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/orders/$orderId/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ProductionOrderModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Retrieves department capacity profiles.
  Future<List<DepartmentCapacityModel>> fetchDepartmentCapacities() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/department-capacity/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final list = json.decode(response.body) as List;
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => DepartmentCapacityModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Retrieves active bottlenecks.
  Future<List<ProductionBottleneckModel>> fetchBottlenecks() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/bottlenecks/');
    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final list = json.decode(response.body) as List;
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => ProductionBottleneckModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Retrieves machine assignments.
  Future<List<MachineAssignmentModel>> fetchMachineAssignments() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/assignments/');
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
            .map((e) => MachineAssignmentModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Retrieves latest production impact assessments.
  Future<List<ProductionImpactAssessmentModel>> fetchImpactAssessments() async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/impact/');
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
            .map((e) => ProductionImpactAssessmentModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Triggers controlled simulation operations: 'advance', 'breakdown', 'recover', or 'seed'.
  Future<Map<String, dynamic>?> triggerSimulationAction({
    required String action,
    double hours = 2.0,
    String? machineCode,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/production/simulate-progression/');
    final payload = <String, dynamic>{
      'action': action,
      'hours': hours,
    };
    if (machineCode != null) payload['machine_code'] = machineCode;

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
