import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/widgets/app_sidebar.dart';
import 'package:frontend/presentation/screens/executive_command_center_screen.dart';

void main() {
  testWidgets('Texora AI App loads with sidebar and executive command center on desktop', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const TexoraApp());
    await tester.pump();

    // Verify Texora AI branding is rendered
    expect(find.text('Texora AI'), findsOneWidget);
    expect(find.text('Commercial Industrial AI'), findsOneWidget);

    // Verify AppSidebar is present
    expect(find.byType(AppSidebar), findsOneWidget);

    // Verify ExecutiveCommandCenterScreen is rendered at default index 0
    expect(find.byType(ExecutiveCommandCenterScreen), findsOneWidget);
    expect(find.text('Executive Factory Command Center'), findsOneWidget);
  });
}
