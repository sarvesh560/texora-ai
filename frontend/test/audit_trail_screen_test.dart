import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/audit_trail_screen.dart';

void main() {
  testWidgets('AuditTrailScreen renders title, entity dropdown, and search field', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AuditTrailScreen(),
        ),
      ),
    );
    await tester.pump();

    // Verify Title & Governance badge
    expect(find.text('Immutable Audit Trail & Governance'), findsOneWidget);
    expect(find.text('Append-Only Cryptographic Log'), findsOneWidget);

    // Verify Dropdowns & Search
    expect(find.text('All Entities'), findsOneWidget);
    expect(find.text('All Actors'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
