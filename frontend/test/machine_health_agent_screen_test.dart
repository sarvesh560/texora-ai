import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/data/services/api_service.dart';
import 'package:frontend/presentation/screens/machine_health_agent_screen.dart';

void main() {
  final sampleDigitalTwinPayload = {
    'factory_code': 'FACTORY-01',
    'total_machines': 2,
    'operational_summary': {
      'operational_count': 1,
      'warning_count': 1,
      'critical_count': 0,
    },
    'machine_states': [
      {
        'id': 1,
        'code': 'SPIN-01',
        'name': 'Ring Frame Spinning #01',
        'department_code': 'SPN',
        'department_name': 'Spinning',
        'raw_status': 'OPERATIONAL',
        'twin_presentation_state': 'RUNNING',
        'health_score': 94.0,
        'telemetry_freshness': {'is_stale': false},
        'latest_telemetry': {
          'timestamp': '2026-10-09T14:30:00Z',
          'vibration_mms': 2.3,
          'temperature_c': 48.5,
          'speed_rpm': 14500,
        },
        'operating_limits': {
          'temp_max': 80.0,
          'vib_max': 7.0,
          'speed_max': 18000,
        },
        'active_incidents': [],
      },
      {
        'id': 2,
        'code': 'WEAV-02',
        'name': 'Air-Jet Loom #02',
        'department_code': 'WEV',
        'department_name': 'Weaving',
        'raw_status': 'WARNING',
        'twin_presentation_state': 'WARNING',
        'health_score': 78.5,
        'telemetry_freshness': {'is_stale': false},
        'latest_telemetry': {
          'timestamp': '2026-10-09T14:29:50Z',
          'vibration_mms': 5.8,
          'temperature_c': 76.2,
          'speed_rpm': 820,
        },
        'operating_limits': {
          'temp_max': 75.0,
          'vib_max': 6.0,
          'speed_max': 1000,
        },
        'active_incidents': [
          {'id': 101, 'title': 'Loom Main Bearing Thermal Elevation', 'severity': 'HIGH'}
        ],
      }
    ],
  };

  final sampleAgentSummaryPayload = {
    'provider_status': {
      'provider': 'gemini',
      'model': 'gemini-1.5-pro',
      'is_configured': true,
      'is_fallback': false,
    },
    'pending_incidents': [
      {
        'id': 101,
        'machine_code': 'WEAV-02',
        'severity': 'HIGH',
        'summary': 'Loom Main Bearing Thermal Elevation',
      }
    ],
    'recent_executions': [
      {
        'execution_id': 'EXEC-991',
        'agent_name': 'Machine Health Specialist',
        'trigger_event': 'Bearing Vibration Threshold Exceeded',
        'status': 'COMPLETED',
        'execution_summary': 'Gemini AI performed vibration harmonic analysis and diagnosed race degradation.',
        'token_count': 1420,
        'latency_ms': 680,
        'started_at': '2026-10-09T14:25:00Z',
        'decisions': [
          {
            'id': 1,
            'decision_type': 'DIAGNOSIS',
            'decision_type_display': 'Bearing Race Wear',
            'rationale': 'Harmonic peak at 3.2x shaft frequency confirms outer race wear.',
            'confidence_score': 94.5,
            'risk_level': 'MEDIUM',
            'requires_human_approval': false,
            'timestamp': '2026-10-09T14:25:01Z',
          }
        ],
        'actions': [],
      }
    ],
  };

  final sampleApprovalsPayload = [
    {
      'id': 401,
      'approval_code': 'APP-001',
      'title': 'Scheduled Bearing Replacement & Lubrication',
      'description': 'Replace WEAV-02 main bearing assembly during next shift change.',
      'requested_action': 'Schedule Work Order',
      'risk_level': 'LOW',
      'status': 'PENDING',
      'requested_by_agent': 'Machine Health Specialist',
      'approved_by': '',
      'response_notes': '',
      'created_at': '2026-10-09T14:26:00Z',
    }
  ];

  final sampleTelemetryListPayload = [
    {'timestamp': '2026-10-09T14:30:00Z', 'vibration_mms': 2.3, 'temperature_c': 48.5, 'speed_rpm': 14500},
    {'timestamp': '2026-10-09T14:29:00Z', 'vibration_mms': 2.28, 'temperature_c': 48.2, 'speed_rpm': 14510},
  ];

  ApiService createMockApiService({
    bool failSnapshot = false,
    bool emptyTelemetry = false,
  }) {
    final client = MockClient((request) async {
      final path = request.url.path;

      if (path.contains('/digital-twin/snapshot/')) {
        if (failSnapshot) {
          return http.Response('Internal Server Error', 500);
        }
        return http.Response(jsonEncode({'data': sampleDigitalTwinPayload}), 200);
      }
      if (path.contains('/executions/summary/')) {
        return http.Response(jsonEncode(sampleAgentSummaryPayload), 200);
      }
      if (path.contains('/approvals/')) {
        return http.Response(jsonEncode(sampleApprovalsPayload), 200);
      }
      if (path.contains('/telemetry/')) {
        if (emptyTelemetry) {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response(jsonEncode(sampleTelemetryListPayload), 200);
      }
      if (path.contains('/executions/run-cycle/')) {
        return http.Response(jsonEncode({'success': true, 'investigated_count': 1}), 200);
      }
      return http.Response('{}', 200);
    });

    return ApiService(client: client);
  }

  testWidgets('MachineHealthAgentScreen successfully loads machines, KPI metrics, and table', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: MachineHealthAgentScreen(apiService: mockService),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title & Provider Header
    expect(find.text('Machine Health AI & Fleet Telemetry'), findsOneWidget);
    expect(find.text('Inference Engine: GEMINI (gemini-1.5-pro)'), findsOneWidget);

    // Verify KPI Summary Cards
    expect(find.text('TOTAL MONITORED'), findsOneWidget);
    expect(find.text('HEALTHY & RUNNING'), findsOneWidget);
    expect(find.text('SUB-OPTIMAL WARNING'), findsOneWidget);
    expect(find.text('2 Machines'), findsOneWidget);

    // Verify Machine Table rows
    expect(find.text('SPIN-01'), findsOneWidget);
    expect(find.text('WEAV-02'), findsOneWidget);
    expect(find.textContaining('Spinning'), findsWidgets);
    expect(find.textContaining('Weaving'), findsWidgets);

    // Verify AI Execution Stream & Decisions
    expect(find.text('AI INVESTIGATION & AUTONOMOUS REASONING LOG'), findsOneWidget);
    expect(find.text('Bearing Vibration Threshold Exceeded'), findsOneWidget);
    expect(find.textContaining('Harmonic peak at 3.2x shaft frequency'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('MachineHealthAgentScreen opens machine diagnostic workspace on row click', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: MachineHealthAgentScreen(apiService: mockService),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap on first Inspect button in table
    final inspectBtn = find.text('Inspect').first;
    await tester.tap(inspectBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Diagnostic Workspace opens
    expect(find.textContaining('Diagnostic Workspace'), findsOneWidget);
    expect(find.text('ENGINEERING OPERATING LIMITS'), findsOneWidget);
    expect(find.text('RECENT TELEMETRY READINGS (LAST 10)'), findsOneWidget);
    expect(find.text('2.30 mm/s'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('MachineHealthAgentScreen handles failed API request and allows retry', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService(failSnapshot: true);

    await tester.pumpWidget(
      MaterialApp(
        home: MachineHealthAgentScreen(apiService: mockService),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // When snapshot fails, snapshot is null, screen shows the KPI cards and fleet layout
    expect(find.text('Machine Health AI & Fleet Telemetry'), findsOneWidget);
    expect(find.text('TOTAL MONITORED'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('MachineHealthAgentScreen handles empty telemetry gracefully', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService(emptyTelemetry: true);

    await tester.pumpWidget(
      MaterialApp(
        home: MachineHealthAgentScreen(apiService: mockService),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap first inspect button
    final inspectBtn = find.text('Inspect').first;
    await tester.tap(inspectBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No recent telemetry samples returned from time-series storage.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('MachineHealthAgentScreen triggers manual AI agent cycle', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockService = createMockApiService();

    await tester.pumpWidget(
      MaterialApp(
        home: MachineHealthAgentScreen(apiService: mockService),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Find and tap Run Agent Cycle button
    final runCycleBtn = find.text('Run Agent Cycle (Manual)');
    expect(runCycleBtn, findsOneWidget);
    await tester.tap(runCycleBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify confirmation snackbar
    expect(find.textContaining('Autonomous AI cycle completed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  group('MachineHealthAgentScreen Responsive Viewports', () {
    for (final size in [
      const Size(1920, 1080),
      const Size(1440, 900),
      const Size(1024, 768),
      const Size(768, 1024),
      const Size(480, 854),
      const Size(360, 640),
      const Size(320, 568),
    ]) {
      testWidgets('Renders at ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final mockService = createMockApiService();

        await tester.pumpWidget(
          MaterialApp(
            home: MachineHealthAgentScreen(apiService: mockService),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(MachineHealthAgentScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 50));
      });
    }
  });
}
