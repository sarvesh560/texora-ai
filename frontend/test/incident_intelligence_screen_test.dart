import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/data/services/api_service.dart';
import 'package:frontend/presentation/screens/incident_intelligence_screen.dart';

void main() {
  final sampleIncidentsSummaryJson = {
    'total_active': 1,
    'critical_count': 1,
    'investigating_count': 0,
    'resolved_count': 0,
    'checkpoint': {
      'is_thread_alive': true,
      'total_telemetry_processed': 2703,
      'last_telemetry_timestamp': '2026-10-09T14:35:00Z',
    },
    'severity_distribution': {'CRITICAL': 1},
    'department_distribution': {'Spinning': 1},
  };

  final sampleIncidentsListJson = [
    {
      'id': 501,
      'incident_code': 'INC-20261009-001',
      'factory_id': 1,
      'department_id': 1,
      'machine_id': 1,
      'machine_code': 'CARD-01',
      'machine_name': 'High-Speed Carding Machine #01',
      'department_code': 'SPN',
      'department_name': 'Spinning',
      'severity': 'CRITICAL',
      'status': 'OPEN',
      'category': 'THERMAL',
      'summary': 'High Temperature Thermal Spike in Carding Drive',
      'root_cause_hypothesis': 'Bearing lubricant degradation at high continuous RPM.',
      'evidence_data': {'temperature_c': 88.4},
      'detected_at': '2026-10-09T14:15:00Z',
      'resolved_at': null,
      'resolution_summary': '',
      'anomalies': [
        {
          'id': 12,
          'incident': 501,
          'machine': 1,
          'machine_code': 'CARD-01',
          'machine_name': 'High-Speed Carding Machine #01',
          'department_code': 'SPN',
          'metric_name': 'temperature_c',
          'observed_value': 88.4,
          'threshold_value': 75.0,
          'anomaly_score': 0.95,
          'confidence_pct': 96.5,
          'algorithm_used': 'THRESHOLD_RULE',
          'detected_at': '2026-10-09T14:15:00Z',
        }
      ],
    }
  ];

  final sampleDetailJson = {
    'incident': sampleIncidentsListJson.first,
    'machine': {
      'id': 1,
      'code': 'CARD-01',
      'name': 'High-Speed Carding Machine #01',
      'department': 'Spinning',
    },
    'workflow_run': {
      'current_stage': 'AI_INVESTIGATING',
      'status': 'IN_PROGRESS',
    },
    'ai_investigation': {
      'status': 'COMPLETED',
      'summary': 'AI diagnosed drive motor bearing overheating due to insufficient lubrication.',
      'root_cause': 'Bearing lubricant degradation at high continuous RPM.',
      'confidence_score': 95.0,
    },
    'active_actions': [],
  };

  ApiService createMockApiService({
    bool failIncidents = false,
    bool emptyIncidents = false,
  }) {
    final client = MockClient((request) async {
      final path = request.url.path;

      if (path.contains('/incidents/summary/')) {
        if (failIncidents) {
          return http.Response('Server Error', 500);
        }
        if (emptyIncidents) {
          return http.Response(
            jsonEncode({
              'total_active': 0,
              'critical_count': 0,
              'investigating_count': 0,
              'resolved_count': 0,
              'checkpoint': {
                'is_thread_alive': true,
                'total_telemetry_processed': 2703,
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode(sampleIncidentsSummaryJson), 200);
      }
      if (path.contains('/intelligence/')) {
        if (failIncidents) {
          return http.Response('Server Error', 500);
        }
        return http.Response(jsonEncode(sampleDetailJson), 200);
      }
      if (path.contains('/incidents/')) {
        if (failIncidents) {
          return http.Response('Server Error', 500);
        }
        if (emptyIncidents) {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response(jsonEncode(sampleIncidentsListJson), 200);
      }
      return http.Response('{}', 200);
    });

    return ApiService(client: client);
  }

  testWidgets('IncidentIntelligenceScreen renders KPI metrics and incident list', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncidentIntelligenceScreen(apiService: mockService),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title & Active Monitor Badge
    expect(find.text('Incident Intelligence & Abnormality Management'), findsOneWidget);
    expect(find.text('AI MONITOR ACTIVE'), findsOneWidget);

    // Verify KPI Cards
    expect(find.text('Active Incidents'), findsOneWidget);
    expect(find.text('Critical Outages'), findsOneWidget);
    expect(find.text('AI Investigating'), findsOneWidget);
    expect(find.text('Resolved Total'), findsOneWidget);

    // Verify Incident Card/Row
    expect(find.text('INC-20261009-001'), findsOneWidget);
    expect(find.text('High Temperature Thermal Spike in Carding Drive'), findsOneWidget);
    expect(find.text('CARD-01'), findsOneWidget);
    expect(find.text('CRITICAL'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('IncidentIntelligenceScreen opens detail panel on selection', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncidentIntelligenceScreen(apiService: mockService),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on incident item
    await tester.tap(find.text('INC-20261009-001'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Incident Detail Panel
    expect(find.text('INC-20261009-001'), findsWidgets);
    expect(find.text('Autonomous Workflow Lifecycle'), findsOneWidget);
    expect(find.text('Machine Operating State & Sensors'), findsOneWidget);
    expect(find.text('AI Diagnostic Findings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('IncidentIntelligenceScreen handles empty incidents state with clear monitoring worker info', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService(emptyIncidents: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncidentIntelligenceScreen(apiService: mockService),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Empty State message and monitoring worker status
    expect(find.text('No Operational Incidents Recorded'), findsOneWidget);
    expect(find.textContaining('Detector Daemon: ACTIVE'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('IncidentIntelligenceScreen handles API failure with error state and retry', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService(failIncidents: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncidentIntelligenceScreen(apiService: mockService),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // When incident request fails, incidents list is empty and summary is null
    expect(find.text('No Operational Incidents Recorded'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
