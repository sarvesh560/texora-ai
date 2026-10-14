import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/core/theme/texora_design_system.dart';
import 'package:frontend/presentation/screens/quality_monitoring_screen.dart';
import 'package:frontend/presentation/screens/inventory_management_screen.dart';
import 'package:frontend/presentation/screens/energy_management_screen.dart';
import 'package:frontend/presentation/screens/reports_analytics_screen.dart';
import 'package:frontend/data/services/api_service.dart';
import 'package:http/http.dart' as http;

class MockReportsHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;

    if (path.contains('/inspections/summary/')) {
      final body = '''{
        "total_inspections": 7,
        "passed_count": 6,
        "failed_count": 1,
        "pass_rate_pct": 85.7,
        "average_quality_score": 93.8,
        "total_defects_logged": 8,
        "defects_by_type": [
          {"type": "WEFT_MISSING_PICK", "display": "Weft Missing Pick", "count": 3},
          {"type": "BARRE_STREAK", "display": "Barre Streak", "count": 2}
        ]
      }''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/inspections/')) {
      final body = '''[
        {
          "id": 1,
          "inspection_code": "QA-20261014-001",
          "batch_number": "BAT-COT-2026-088",
          "machine_code": "SPN-01",
          "department_name": "Spinning",
          "inspector_name": "Dr. R. Ramanathan",
          "overall_score": 98.5,
          "status": "PASSED",
          "sample_size": 20,
          "inspected_quantity": 200,
          "accepted_quantity": 200,
          "rejected_quantity": 0,
          "notes": "Optimal yarn tensile strength.",
          "defects": []
        }
      ]''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/items/summary/')) {
      final body = '''{
        "total_items": 11,
        "total_inventory_valuation": 2845000.0,
        "low_stock_count": 2,
        "critical_outage_count": 0,
        "categories_breakdown": [
          {"category": "SPARE_PARTS", "count": 5},
          {"category": "RAW_MATERIAL", "count": 3}
        ],
        "ai_recommendations": [
          {"name": "SKF Bearing 6309-2RS", "urgency": "HIGH", "reason": "MTBF warning threshold reached"}
        ]
      }''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/items/')) {
      final body = '''[
        {
          "id": 1,
          "item_code": "SPR-BRG-6309",
          "name": "High-Precision Deep Groove Bearing",
          "category": "SPARE_PARTS",
          "current_stock": 4.0,
          "reorder_point": 8.0,
          "minimum_safety_stock": 3.0,
          "unit_cost": 4200.0,
          "unit": "units",
          "is_low_stock": true
        }
      ]''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/readings/summary/')) {
      final body = '''{
        "total_consumption_kwh": 11981.0,
        "average_power_kw": 498.5,
        "peak_demand_kw": 612.0,
        "estimated_cost_inr": 98244.2,
        "total_carbon_emission_kg": 9824.4,
        "average_power_factor": 0.94,
        "department_breakdown": [
          {"dept_code": "SPN", "name": "Spinning", "kwh": 5240.0, "active_kw": 218.0}
        ],
        "hourly_trend": [
          {"timestamp": "08:00", "power_kw": 480.0},
          {"timestamp": "12:00", "power_kw": 510.0}
        ],
        "ai_recommendations": [
          {"title": "Peak Shaving Loom Shed", "department": "Weaving", "action": "Stagger startup by 15 mins", "impact": "SAVE ₹12,000"}
        ]
      }''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/readings/')) {
      final body = '''[
        {
          "id": 1,
          "machine_code": "SPN-01",
          "department_name": "Spinning",
          "active_power_kw": 18.5,
          "energy_kwh": 312.0,
          "power_factor": 0.95,
          "voltage_v": 415.0,
          "is_peak_hour": false
        }
      ]''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    if (path.contains('/reports/export/')) {
      const csv = 'TEXORA AI — FACTORY EXECUTIVE OPERATIONS\\nOrder,Client,Target,Status\\nORD-101,Vardhman,10000,IN_PROGRESS';
      return http.StreamedResponse(
        Stream.value(csv.codeUnits),
        200,
        headers: {'content-type': 'text/csv'},
      );
    }

    if (path.contains('/reports/overview/')) {
      final body = '''{
        "category": "factory_overview",
        "category_label": "Factory Executive Operations & Output Report",
        "range": "today",
        "generated_at": "2026-10-14 14:00:00 UTC",
        "kpis": [
          {"label": "Production Output", "value": "12,450 kg", "subtext": "98% of target"},
          {"label": "Active Orders", "value": "14 Orders", "subtext": "Commercial commitments"}
        ],
        "columns": ["Order Number", "Client Name", "Target", "Status"],
        "row_keys": ["order_number", "client", "target", "status"],
        "rows": [
          {"order_number": "ORD-101", "client": "Vardhman Textiles", "target": "10,000 kg", "status": "IN_PROGRESS"}
        ]
      }''';
      return http.StreamedResponse(
        Stream.value(body.codeUnits),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    return http.StreamedResponse(Stream.value('{}'.codeUnits), 200, headers: {'content-type': 'application/json'});
  }
}

void main() {
  late ApiService mockApi;

  setUp(() {
    mockApi = ApiService(client: MockReportsHttpClient());
  });

  group('Priority 3 — Quality Monitoring Screen Tests', () {
    testWidgets('renders Quality KPIs, pass rate, and inspection records', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: TexoraColors.workspaceBg),
          home: QualityMonitoringScreen(apiService: mockApi),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Assert Header and KPIs
      expect(find.text('Quality Monitoring & Laboratory Inspection'), findsOneWidget);
      expect(find.text('7 Audits'), findsOneWidget);
      expect(find.text('85.7%'), findsOneWidget);
      expect(find.text('QA-20261014-001'), findsOneWidget);
      expect(find.text('Dr. R. Ramanathan'), findsOneWidget);

      // Tap on View QA to open detail drawer
      await tester.tap(find.text('View QA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Batch Quality Inspection Details'), findsOneWidget);
      expect(find.text('Sample Size Tested'), findsOneWidget);
    });
  });

  group('Priority 4 — Inventory Management Screen Tests', () {
    testWidgets('renders Inventory valuation, low stock SKUs, and items catalog', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: TexoraColors.workspaceBg),
          home: InventoryManagementScreen(apiService: mockApi),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Warehouse Inventory & Spare Parts'), findsOneWidget);
      expect(find.text('11 Items'), findsOneWidget);
      expect(find.text('2 SKUs'), findsOneWidget);
      expect(find.text('SPR-BRG-6309'), findsOneWidget);

      // Tap Details to open SKU detail drawer
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('SKU Inventory Details'), findsOneWidget);
      expect(find.text('LOW STOCK ALERT'), findsOneWidget);
      expect(find.text('Current Stock Available'), findsOneWidget);
    });
  });

  group('Priority 5 — Energy Management Screen Tests', () {
    testWidgets('renders electrical power, load trend, sub-metered table', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: TexoraColors.workspaceBg),
          home: EnergyManagementScreen(apiService: mockApi),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Electrical Energy & Sub-Metered Load'), findsOneWidget);
      expect(find.text('11981 kWh'), findsOneWidget);
      expect(find.text('498.5 kW'), findsOneWidget);
      expect(find.text('Active Power Demand Trend (kW)'), findsOneWidget);
      expect(find.text('Sub-Metered Machine Telemetry Log'), findsOneWidget);
      expect(find.text('SPN-01'), findsOneWidget);
    });
  });

  group('Priority 6 — Reports & Operational Analytics Screen Tests', () {
    testWidgets('renders category filter, date ranges, and CSV export dialog', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: TexoraColors.workspaceBg),
          home: ReportsAnalyticsScreen(apiService: mockApi),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Operational Reports & Analytics'), findsOneWidget);
      expect(find.text('12,450 kg'), findsOneWidget);
      expect(find.text('ORD-101'), findsOneWidget);
      expect(find.text('Vardhman Textiles'), findsOneWidget);

      // Tap Export CSV
      final exportBtn = find.text('Export CSV');
      expect(exportBtn, findsOneWidget);
      await tester.tap(exportBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Assert CSV Export dialog opened
      expect(find.text('CSV Export Generated'), findsOneWidget);
      expect(find.text('Copy to Clipboard'), findsOneWidget);
    });
  });

  group('Priority 8 — MainShellScreen All Sidebar Destinations', () {
    testWidgets('all sidebar destinations open real functional screens in light theme', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(const TexoraApp());
      await tester.pump();

      // Navigate to Quality
      final qualityNav = find.text('Quality');
      expect(qualityNav, findsWidgets);
      await tester.tap(qualityNav.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(QualityMonitoringScreen), findsOneWidget);

      // Navigate to Inventory
      final inventoryNav = find.text('Inventory');
      expect(inventoryNav, findsWidgets);
      await tester.tap(inventoryNav.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(InventoryManagementScreen), findsOneWidget);

      // Navigate to Energy
      final energyNav = find.text('Energy');
      expect(energyNav, findsWidgets);
      await tester.tap(energyNav.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(EnergyManagementScreen), findsOneWidget);

      // Navigate to Reports
      final reportsNav = find.text('Reports');
      expect(reportsNav, findsWidgets);
      await tester.tap(reportsNav.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ReportsAnalyticsScreen), findsOneWidget);
    });
  });
}
