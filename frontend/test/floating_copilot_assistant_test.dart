import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/copilot_models.dart';
import 'package:frontend/presentation/widgets/floating_copilot_assistant.dart';

void main() {
  group('FloatingCopilotAssistant RenderFlex Overflow Regression Tests', () {
    final longReferencesMessage = CopilotMessageModel(
      role: 'assistant',
      content: 'Here are the diagnostic records and linked factory entities for the current machine event.',
      provider: 'groqcloud',
      model: 'llama-3.3-70b-versatile',
      latencyMs: 385,
      createdAt: DateTime(2026, 10, 13, 14, 30),
      references: [
        CopilotReference(
          type: 'incident',
          id: 'INC-20261012-8A9F',
          label: 'Incident INC-20261012-8A9F (CRITICAL: Main bearing thermal runaway and severe vibration anomaly)',
        ),
        CopilotReference(
          type: 'machine',
          id: 'WEV-AJ-02',
          label: 'Machine WEV-AJ-02: Toyota JAT810 Air-Jet Loom Bay 2 High-Speed Weaving Shed',
        ),
        CopilotReference(
          type: 'ticket',
          id: 'MNT-20261012104734-3F03',
          label: 'Ticket MNT-20261012104734-3F03: Urgent Bearing Replacement & Spindle Realignment',
        ),
        CopilotReference(
          type: 'approval',
          id: 'APP-20261012-01',
          label: 'Approval APP-20261012-01: Manager Sign-off for High-Priority Loom Part Sourcing',
        ),
      ],
    );

    final longSuggestions = [
      SuggestedQuestionModel(
        id: 'sug-1',
        category: 'PLANT_HEALTH',
        prompt: 'Can you provide a comprehensive plant-wide vibration, temperature, energy consumption, and maintenance ticket diagnostic summary for all 25 machines across all five factory departments?',
        description: 'Plant-wide health summary',
      ),
      SuggestedQuestionModel(
        id: 'sug-2',
        category: 'ROOT_CAUSE',
        prompt: 'Why did WEV-AJ-02 fail after high-speed operation, and what were the specialist AI agents diagnostic findings regarding bearing temperature and lubrication degradation?',
        description: 'Loom failure investigation',
      ),
      SuggestedQuestionModel(
        id: 'sug-3',
        category: 'PARTS',
        prompt: 'What is the stock level and lead time for SKF-6205 bearing kits?',
        description: 'Inventory check',
      ),
    ];

    final testWidths = [320.0, 360.0, 400.0, 480.0];

    for (final width in testWidths) {
      testWidgets('FloatingCopilotAssistant renders long references without overflow at width ${width.toInt()}px', (tester) async {
        tester.view.physicalSize = Size(width + 100, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FloatingCopilotAssistant(
                    onOpenFullScreen: () {},
                    panelWidth: width,
                    initialExpanded: true,
                    initialMessages: [longReferencesMessage],
                    initialSuggestions: longSuggestions,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        // Crucial requirement: No RenderFlex overflow exception
        expect(tester.takeException(), isNull, reason: 'RenderFlex overflowed at panel width ${width}px');

        // Verify elements are present and readable
        expect(find.text('Texora Factory Copilot'), findsOneWidget);
        expect(find.text('Here are the diagnostic records and linked factory entities for the current machine event.'), findsOneWidget);
        expect(find.byType(Wrap), findsWidgets);
      });
    }

    testWidgets('FloatingCopilotAssistant handles long model provenance badge and user message at 320px', (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final longProvenanceMsg = CopilotMessageModel(
        role: 'assistant',
        content: 'Autonomous root-cause analysis completed.',
        provider: 'groqcloud-enterprise-multicloud',
        model: 'llama-3.3-70b-versatile-speculative-decoding-v2',
        latencyMs: 1420,
        createdAt: DateTime(2026, 10, 13, 15, 45),
        references: [
          CopilotReference(type: 'machine', id: 'SPN-RF-01', label: 'Ring Frame SPN-RF-01 Bay 1'),
        ],
      );

      final userMsg = CopilotMessageModel(
        role: 'user',
        content: 'Please evaluate the vibration anomalies and supply chain stock for all spinning machines in Bay 1.',
        createdAt: DateTime(2026, 10, 13, 15, 44),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingCopilotAssistant(
                  onOpenFullScreen: () {},
                  panelWidth: 320,
                  initialExpanded: true,
                  initialMessages: [userMsg, longProvenanceMsg],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Please evaluate the vibration anomalies and supply chain stock for all spinning machines in Bay 1.'), findsOneWidget);
      expect(find.text('Autonomous root-cause analysis completed.'), findsOneWidget);
    });

    testWidgets('FloatingCopilotAssistant interactive chat input and send button', (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingCopilotAssistant(
                  onOpenFullScreen: () {},
                  panelWidth: 400,
                  initialExpanded: true,
                  initialSuggestions: longSuggestions,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);

      // Verify chat input field
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      // Enter text into input field
      await tester.enterText(textFieldFinder, 'What is the vibration level of WEV-AJ-02?');
      expect(find.text('What is the vibration level of WEV-AJ-02?'), findsOneWidget);

      // Tap Send button
      final sendBtnFinder = find.byIcon(Icons.send_rounded);
      expect(sendBtnFinder, findsOneWidget);
      await tester.tap(sendBtnFinder);
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Verify optimistic message was added to chat
      expect(find.text('What is the vibration level of WEV-AJ-02?'), findsOneWidget);
    });

    testWidgets('FloatingCopilotAssistant renders loading indicator bubble without overflow across narrow widths', (tester) async {
      for (final width in [320.0, 360.0, 400.0]) {
        tester.view.physicalSize = Size(width + 100, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  FloatingCopilotAssistant(
                    onOpenFullScreen: () {},
                    panelWidth: width,
                    initialExpanded: true,
                    initialLoading: true,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Grounding query in factory records...'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      }
    });
  });
}
