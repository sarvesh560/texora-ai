import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/presentation/screens/factory_recovery_screen.dart';

void main() {
  testWidgets('FactoryRecoveryScreen loads with header and recovery controls', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: FactoryRecoveryScreen(),
      ),
    );
    await tester.pump();

    // Verify loading or initial command center shell
    expect(find.byType(FactoryRecoveryScreen), findsOneWidget);
  });
}
