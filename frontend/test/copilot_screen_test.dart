import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/copilot_models.dart';
import 'package:frontend/presentation/screens/factory_copilot_screen.dart';
import 'package:frontend/presentation/widgets/floating_copilot_assistant.dart';

void main() {
  group('Phase 14 Copilot Models & JSON Serialization Tests', () {
    test('CopilotReference serializes and deserializes accurately', () {
      final json = {
        'type': 'machine',
        'id': 'WEV-AJ-02',
        'label': 'Loom WEV-AJ-02',
      };
      final ref = CopilotReference.fromJson(json);
      expect(ref.type, 'machine');
      expect(ref.id, 'WEV-AJ-02');
      expect(ref.label, 'Loom WEV-AJ-02');

      final backToJson = ref.toJson();
      expect(backToJson['id'], 'WEV-AJ-02');
      expect(backToJson['type'], 'machine');
    });

    test('CopilotMessageModel parses facts, estimates, recommendations, and provenance', () {
      final json = {
        'id': 42,
        'role': 'assistant',
        'content': 'Machine WEV-AJ-02 is experiencing severe vibration due to drive bearing degradation.',
        'facts': ['Current vibration: 7.75 mm/s', 'Critical limit: 5.8 mm/s'],
        'estimates': ['Estimated repair downtime: 1.5 hours'],
        'recommendations': ['Dispatch technician with replacement bearing SPR-BRG-6204'],
        'references': [
          {'type': 'machine', 'id': 'WEV-AJ-02', 'label': 'WEV-AJ-02'},
          {'type': 'incident', 'id': 'INC-20261012-01', 'label': 'INC-20261012-01'},
        ],
        'evidence_records': [
          {'machine': 'WEV-AJ-02', 'telemetry': 'abnormal'}
        ],
        'missing_evidence': 'No oil thermal records available',
        'is_simulated': true,
        'simulation_disclosure': 'Demonstration data',
        'provider': 'groq',
        'model': 'qwen/qwen3.8-27b',
        'latency_ms': 240,
        'reasoning_source': 'GROQ_LIVE',
        'created_at': '2026-10-13T10:00:00Z',
      };

      final msg = CopilotMessageModel.fromJson(json);
      expect(msg.id, 42);
      expect(msg.isAssistant, isTrue);
      expect(msg.facts.length, 2);
      expect(msg.estimates.length, 1);
      expect(msg.recommendations.length, 1);
      expect(msg.references.length, 2);
      expect(msg.references.first.id, 'WEV-AJ-02');
      expect(msg.provider, 'groq');
      expect(msg.latencyMs, 240);
      expect(msg.reasoningSource, 'GROQ_LIVE');
    });

    test('CopilotSessionModel parses session list metadata correctly', () {
      final json = {
        'id': 10,
        'session_id': 'COP-TEST-SESSION-99',
        'title': 'Shift Morning Inspection',
        'active_machine_code': 'WEV-AJ-02',
        'active_incident_code': 'INC-20261012-01',
        'message_count': 6,
        'latest_message': {'role': 'assistant', 'content': 'Recommendation provided.'},
        'created_at': '2026-10-13T08:30:00Z',
        'updated_at': '2026-10-13T09:15:00Z',
      };

      final session = CopilotSessionModel.fromJson(json);
      expect(session.sessionId, 'COP-TEST-SESSION-99');
      expect(session.title, 'Shift Morning Inspection');
      expect(session.activeMachineCode, 'WEV-AJ-02');
      expect(session.activeIncidentCode, 'INC-20261012-01');
      expect(session.messageCount, 6);
      expect(session.latestMessageSnippet, 'Recommendation provided.');
    });

    test('SuggestedQuestionModel parses prompt and category', () {
      final json = {
        'id': 'sug-1',
        'category': 'ROOT_CAUSE',
        'prompt': 'Why did WEV-AJ-02 fail?',
        'description': 'Inspect specialist AI diagnosis',
        'target_entity': 'WEV-AJ-02',
      };
      final sug = SuggestedQuestionModel.fromJson(json);
      expect(sug.id, 'sug-1');
      expect(sug.category, 'ROOT_CAUSE');
      expect(sug.prompt, 'Why did WEV-AJ-02 fail?');
    });
  });

  group('Phase 14 Copilot UI Widget Tests', () {
    testWidgets('FloatingCopilotAssistant renders in collapsed floating state and expands on tap', (tester) async {
      bool fullScreenTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const Center(child: Text('Main Screen Content')),
                FloatingCopilotAssistant(
                  onOpenFullScreen: () {
                    fullScreenTriggered = true;
                  },
                ),
              ],
            ),
          ),
        ),
      );

      // Verify collapsed floating pill renders
      expect(find.text('Factory Copilot'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);

      // Tap to expand
      await tester.tap(find.text('Factory Copilot'));
      await tester.pumpAndSettle();

      // Verify expanded floating drawer renders with header
      expect(find.text('Texora Factory Copilot'), findsOneWidget);
      expect(find.text('Read-Only Industrial Advisory Engine'), findsOneWidget);
      expect(find.text('New Chat'), findsOneWidget);

      // Tap open full screen button
      final openFullBtn = find.byIcon(Icons.open_in_full_rounded);
      expect(openFullBtn, findsOneWidget);
      await tester.tap(openFullBtn);
      await tester.pump();

      expect(fullScreenTriggered, isTrue);
    });

    testWidgets('FactoryCopilotScreen renders full-screen workspace with responsive panels', (tester) async {
      bool exitTriggered = false;

      // Set large viewport to show evidence inspector
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: FactoryCopilotScreen(
            onExit: () {
              exitTriggered = true;
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top app bar assertions
      expect(find.text('Factory AI Copilot Workspace'), findsOneWidget);
      expect(find.text('SIMULATED DATA DEMONSTRATION'), findsOneWidget);
      expect(find.text('GroqCloud / Gemini / Fallback Active'), findsOneWidget);

      // Left pane assertions
      expect(find.text('New Consultation'), findsOneWidget);
      expect(find.text('ACTIVE CONTEXT FOCUS'), findsOneWidget);
      expect(find.text('SAVED SESSIONS'), findsOneWidget);

      // Evidence inspector assertions
      expect(find.text('GROUNDED EVIDENCE LOG'), findsOneWidget);
      expect(find.text('READ-ONLY ENFORCEMENT'), findsOneWidget);

      // Exit button
      final backBtn = find.byIcon(Icons.arrow_back_rounded);
      expect(backBtn, findsOneWidget);
      await tester.tap(backBtn);
      expect(exitTriggered, isTrue);
    });
  });
}
