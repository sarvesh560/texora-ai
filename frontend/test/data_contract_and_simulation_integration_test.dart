import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/data/services/api_service.dart';
import 'package:frontend/data/services/copilot_service.dart';
import 'package:frontend/data/services/production_api_service.dart';

void main() {
  group('Frontend-to-Backend Data Contracts & Simulation Action Integration Tests', () {
    // -------------------------------------------------------------------------
    // 1. ProductionApiService Data Contracts
    // -------------------------------------------------------------------------
    test('Contract 1: Production Overview DRF payload mapping & capacity calculation', () async {
      final mockResponse = {
        'timestamp': '2026-10-14T09:30:00Z',
        'metrics': {
          'total_orders': 6,
          'active_orders': 5,
          'paused_orders': 1,
          'completed_orders': 0,
          'at_risk_orders_count': 2,
          'total_target_units': 85500.0,
          'total_completed_units': 24000.0,
          'overall_progress_pct': 28.1,
          'plant_utilization_pct': 74.5,
          'nominal_daily_capacity_units': 98580.0,
          'effective_daily_capacity_units': 97428.0,
          'daily_downtime_loss_units': 1152.0,
          'active_bottlenecks_count': 1,
          'active_machine_assignments_count': 6,
        },
        'department_capacities': [
          {
            'department_id': 1,
            'department_code': 'SPN',
            'department_name': 'Spinning Department',
            'nominal_capacity_daily': 22500.0,
            'effective_capacity_daily': 22500.0,
            'allocated_capacity_daily': 17600.0,
            'actual_produced_daily': 17600.0,
            'utilization_pct': 78.2,
            'downtime_loss_daily': 0.0,
            'bottleneck_severity': 'NORMAL',
            'available_headroom_units': 4900.0,
            'active_machines': 7,
            'down_machines': 0,
            'total_machines': 7,
          },
          {
            'department_id': 2,
            'department_code': 'WEV',
            'department_name': 'Weaving Shed',
            'nominal_capacity_daily': 18000.0,
            'effective_capacity_daily': 14400.0,
            'allocated_capacity_daily': 13300.0,
            'actual_produced_daily': 13300.0,
            'utilization_pct': 92.4,
            'downtime_loss_daily': 3600.0,
            'bottleneck_severity': 'CRITICAL',
            'available_headroom_units': 1100.0,
            'active_machines': 5,
            'down_machines': 1,
            'total_machines': 6,
          },
        ],
        'active_bottlenecks': [
          {
            'id': 1,
            'department_code': 'WEV',
            'department_name': 'Weaving Shed',
            'machine_code': 'WEV-AJ-02',
            'bottleneck_type': 'MACHINE_DOWNTIME',
            'severity': 'CRITICAL',
            'primary_cause': 'Main drive bearing failure induced simulated downtime',
            'affected_orders_count': 2,
            'throughput_deficit_units_per_hour': 60.0,
            'estimated_delay_impact_hours': 3.5,
          },
        ],
        'recent_impact_assessments': [
          {
            'id': 101,
            'assessment_code': 'IMPACT-20261014-WEV02',
            'machine_code': 'WEV-AJ-02',
            'machine_name': 'Picanol OmniPlus-i Loom #2',
            'output_quantity_at_risk': 180.0,
            'deterministic_loss_inr': 45000.0,
            'orders_affected_count': 2,
            'overall_delay_risk': 'CRITICAL',
            'recommendations': ['Reroute to WEV-AJ-01', 'Dispatch mechanical tech'],
            'ai_explanation': 'Bearing spalling restricts loom speed. Risk avoided via reroute.',
          },
        ],
      };

      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/production/overview/'));
        return http.Response(json.encode(mockResponse), 200);
      });

      final service = ProductionApiService(client: client);
      final overview = await service.fetchProductionOverview();

      expect(overview, isNotNull);
      expect(overview!.metrics['total_orders'], equals(6));
      expect(overview.metrics['active_orders'], equals(5));
      expect(overview.metrics['at_risk_orders_count'], equals(2));
      expect(overview.metrics['plant_utilization_pct'], equals(74.5));
      expect(overview.departmentCapacities.length, equals(2));
      expect(overview.departmentCapacities.first.departmentCode, equals('SPN'));
      expect(overview.departmentCapacities.last.bottleneckSeverity, equals('CRITICAL'));
      expect(overview.activeBottlenecks.length, equals(1));
      expect(overview.activeBottlenecks.first.machineCode, equals('WEV-AJ-02'));
      expect(overview.recentImpactAssessments.first.deterministicLossInr, equals(45000.0));
    });

    test('Contract 2: Production Orders endpoint parsing and delay risk contract', () async {
      final mockOrders = [
        {
          'id': 1,
          'order_number': 'ORD-2026-KNT-303',
          'client_name': 'Tirupur Knitwear Exporters',
          'customer_po_number': 'PO-TKE-2026-904',
          'fabric_or_yarn_spec': 'Single Jersey Greige 180 GSM (95% Cotton 5% Spandex)',
          'product_category': 'SINGLE_JERSEY',
          'department_code': 'KNT',
          'department_name': 'Knitting Division',
          'target_quantity': 18000.0,
          'completed_quantity': 7200.0,
          'unit': 'KG',
          'status': 'IN_PROGRESS',
          'priority': 'URGENT',
          'routing_stages': ['SPN', 'KNT', 'DYE', 'FIN', 'QC'],
          'current_stage': 'Knitting',
          'start_date': '2026-10-10',
          'due_date': '2026-10-20',
          'progress_pct': 40.0,
          'remaining_quantity': 10800.0,
          'delay_risk_score': 82.5,
          'delay_risk_level': 'CRITICAL',
          'estimated_delay_hours': 14.5,
          'assigned_machines_count': 2,
        },
      ];

      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/production/orders/'));
        return http.Response(json.encode(mockOrders), 200);
      });

      final service = ProductionApiService(client: client);
      final orders = await service.fetchOrders();

      expect(orders.length, equals(1));
      final o = orders.first;
      expect(o.orderNumber, equals('ORD-2026-KNT-303'));
      expect(o.clientName, equals('Tirupur Knitwear Exporters'));
      expect(o.progressPct, equals(40.0));
      expect(o.remainingQuantity, equals(10800.0));
      expect(o.delayRiskLevel, equals('CRITICAL'));
      expect(o.routingStages, contains('KNT'));
      expect(o.estimatedDelayHours, equals(14.5));
    });

    test('Contract 3: Simulation Progression Action endpoint dispatch', () async {
      late String capturedAction;
      late double capturedHours;
      String? capturedMachine;

      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/production/simulate-progression/'));
        expect(request.method, equals('POST'));

        final body = json.decode(request.body) as Map<String, dynamic>;
        capturedAction = body['action'];
        capturedHours = (body['hours'] as num).toDouble();
        capturedMachine = body['machine_code'];

        return http.Response(
          json.encode({
            'success': true,
            'action': capturedAction,
            'hours_advanced': capturedHours,
            'machine_code': capturedMachine,
            'message': 'Simulation action completed on database records.',
          }),
          200,
        );
      });

      final service = ProductionApiService(client: client);

      // Advance
      final advRes = await service.triggerSimulationAction(action: 'advance', hours: 4.0);
      expect(advRes?['success'], isTrue);
      expect(capturedAction, equals('advance'));
      expect(capturedHours, equals(4.0));

      // Breakdown
      final bkdRes = await service.triggerSimulationAction(
        action: 'breakdown',
        machineCode: 'WEV-AJ-02',
        hours: 3.0,
      );
      expect(bkdRes?['success'], isTrue);
      expect(capturedAction, equals('breakdown'));
      expect(capturedMachine, equals('WEV-AJ-02'));

      // Recover
      final recRes = await service.triggerSimulationAction(
        action: 'recover',
        machineCode: 'WEV-AJ-02',
      );
      expect(recRes?['success'], isTrue);
      expect(capturedAction, equals('recover'));
    });

    // -------------------------------------------------------------------------
    // 2. CopilotService Data Contracts
    // -------------------------------------------------------------------------
    test('Contract 4: Copilot grounded conversation contract with facts & references', () async {
      final mockMessages = {
        'session_id': 'COP-A1B2C3D4E5F6',
        'title': 'Factory Consultation Session',
        'message_count': 2,
        'messages': [
          {
            'id': 1,
            'role': 'user',
            'content': 'Which orders are at risk and what happened to WEV-AJ-02?',
            'created_at': '2026-10-14T09:00:00Z',
          },
          {
            'id': 2,
            'role': 'assistant',
            'content': 'Machine WEV-AJ-02 is OPERATIONAL with health score 96.0%. Order ORD-2026-KNT-303 is at CRITICAL delay risk.',
            'facts': [
              'Machine WEV-AJ-02 status is OPERATIONAL',
              'Health score: 96.0%',
              'Order ORD-2026-KNT-303: +14.5h delay risk',
            ],
            'estimates': ['Projected completion 2 days after due date without alternate rerouting'],
            'recommendations': [
              'Reroute affected batch to parallel knitting line',
              'Check spare parts stock for loom maintenance',
            ],
            'references': [
              {'type': 'machine', 'id': 'WEV-AJ-02', 'label': 'WEV-AJ-02 (Picanol OmniPlus-i Loom #2)'},
              {'type': 'order', 'id': 'ORD-2026-KNT-303', 'label': 'ORD-2026-KNT-303 (Tirupur Knitwear)'},
            ],
            'missing_evidence': '',
            'is_simulated': true,
            'simulation_disclosure': 'Data Notice: All records are simulated industrial demonstration data.',
            'created_at': '2026-10-14T09:00:02Z',
          },
        ],
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/messages/')) {
          return http.Response(json.encode(mockMessages), 200);
        } else if (request.url.path.contains('/chat/')) {
          final body = json.decode(request.body) as Map<String, dynamic>;
          expect(body['message'], isNotEmpty);
          final msgsList = mockMessages['messages'] as List<dynamic>;
          return http.Response(json.encode(msgsList[1]), 200);
        }
        return http.Response('{}', 404);
      });

      final copilotService = CopilotService(client: client);
      final msgs = await copilotService.getSessionMessages('COP-A1B2C3D4E5F6');

      expect(msgs.length, equals(2));
      final reply = msgs.last;
      expect(reply.role, equals('assistant'));
      expect(reply.facts.length, equals(3));
      expect(reply.facts[0], contains('WEV-AJ-02'));
      expect(reply.references.length, equals(2));
      expect(reply.references.first.type, equals('machine'));
      expect(reply.references.last.type, equals('order'));
      expect(reply.isSimulated, isTrue);
      expect(reply.simulationDisclosure, contains('simulated'));

      final chatResult = await copilotService.sendMessage(
        'COP-A1B2C3D4E5F6',
        'Which orders are at risk and what happened to WEV-AJ-02?',
      );
      expect(chatResult, isNotNull);
      expect(chatResult!.content, contains('WEV-AJ-02 is OPERATIONAL'));
    });

    // -------------------------------------------------------------------------
    // 3. ApiService Simulation Actions Contract
    // -------------------------------------------------------------------------
    test('Contract 5: Technician flow simulation endpoint contract (HEALTHY vs FAULTY)', () async {
      late String capturedMode;
      late int capturedTicketId;

      final client = MockClient((request) async {
        final segments = request.url.pathSegments;
        capturedTicketId = int.parse(segments[segments.indexOf('tickets') + 1]);
        final body = json.decode(request.body) as Map<String, dynamic>;
        capturedMode = body['mode'];

        return http.Response(
          json.encode({
            'success': true,
            'ticket_id': capturedTicketId,
            'mode': capturedMode,
            'telemetry_samples_generated': 6,
            'average_vibration_mms': capturedMode == 'HEALTHY' ? 2.15 : 6.85,
            'verification_passed': capturedMode == 'HEALTHY',
            'message': 'Simulated post-repair telemetry generated ($capturedMode).',
          }),
          200,
        );
      });

      final apiService = ApiService(client: client);

      // Healthy flow
      final healthyRes = await apiService.simulateTechnicianFlow(42, mode: 'HEALTHY');
      expect(healthyRes['success'], isTrue);
      expect(capturedTicketId, equals(42));
      expect(capturedMode, equals('HEALTHY'));
      expect(healthyRes['verification_passed'], isTrue);

      // Faulty flow
      final faultyRes = await apiService.simulateTechnicianFlow(42, mode: 'FAULTY');
      expect(faultyRes['success'], isTrue);
      expect(capturedMode, equals('FAULTY'));
      expect(faultyRes['verification_passed'], isFalse);
    });

    test('Contract 6: Autonomous Expo Demo trigger contract', () async {
      late String capturedMachine;

      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/autonomous/expo-demo/'));
        final body = json.decode(request.body) as Map<String, dynamic>;
        capturedMachine = body['machine_code'];

        return http.Response(
          json.encode({
            'success': true,
            'machine_code': capturedMachine,
            'incident_id': 77,
            'incident_code': 'INC-SIM-WEV-AJ-02',
            'recommended_strategy': 'STRATEGY_A',
            'message': 'Autonomous pipeline executed and paused at approval gate.',
          }),
          200,
        );
      });

      final apiService = ApiService(client: client);
      final res = await apiService.launchAutonomousExpoDemo(machineCode: 'WEV-RAP-01');

      expect(res['success'], isTrue);
      expect(capturedMachine, equals('WEV-RAP-01'));
      expect(res['incident_id'], equals(77));
      expect(res['recommended_strategy'], equals('STRATEGY_A'));
    });
  });
}
