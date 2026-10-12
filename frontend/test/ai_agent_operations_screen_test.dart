import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/ai_agent_operations_screen.dart';

void main() {
  testWidgets('AiAgentOperationsScreen renders and handles state gracefully', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiAgentOperationsScreen(),
        ),
      ),
    );
    await tester.pump();

    // In a widget test without network, it either renders loading indicator or retry connection button
    expect(
      find.byWidgetPredicate((w) =>
          (w is Text && (w.data?.contains('Loading') == true ||
                         w.data?.contains('Operations') == true ||
                         w.data?.contains('Retry') == true)) ||
          w is CircularProgressIndicator ||
          (w is Icon && w.icon == Icons.cloud_off_rounded)),
      findsWidgets,
    );
  });
}
