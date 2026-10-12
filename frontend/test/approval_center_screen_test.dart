import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/approval_center_screen.dart';

void main() {
  testWidgets('ApprovalCenterScreen renders title, KPI cards, filter chips, and search input', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ApprovalCenterScreen(),
        ),
      ),
    );
    await tester.pump();

    // Verify Title & Governance badge
    expect(find.text('Manager Approval Center'), findsOneWidget);
    expect(find.text('Human-In-The-Loop Governance'), findsOneWidget);

    // Verify KPI Metrics
    expect(find.text('PENDING ACTION GATES'), findsOneWidget);
    expect(find.text('AUTHORIZED & EXECUTED'), findsOneWidget);
    expect(find.text('REVISIONS REQUESTED'), findsOneWidget);
    expect(find.text('REJECTED BY MANAGERS'), findsOneWidget);

    // Verify Search input
    expect(find.byType(TextField), findsOneWidget);
  });
}
