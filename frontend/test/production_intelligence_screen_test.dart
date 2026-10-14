import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/production_models.dart';
import 'package:frontend/data/services/production_api_service.dart';
import 'package:frontend/presentation/screens/production_intelligence_screen.dart';

class FakeProductionApiService extends ProductionApiService {
  ProductionOverviewModel? mockOverview;
  List<ProductionOrderModel> mockOrders = [];
  List<MachineAssignmentModel> mockAssignments = [];
  List<ProductionImpactAssessmentModel> mockImpacts = [];
  List<DepartmentCapacityModel> mockCapacities = [];
  List<ProductionBottleneckModel> mockBottlenecks = [];
  bool triggerSimSuccess = true;
  String? lastActionTriggered;

  @override
  Future<ProductionOverviewModel?> fetchProductionOverview() async {
    return mockOverview;
  }

  @override
  Future<List<ProductionOrderModel>> fetchOrders({
    String? status,
    String? priority,
    String? riskLevel,
  }) async {
    return mockOrders;
  }

  @override
  Future<List<MachineAssignmentModel>> fetchMachineAssignments({String? department, String? status}) async {
    return mockAssignments;
  }

  @override
  Future<List<ProductionImpactAssessmentModel>> fetchImpactAssessments({String? machineCode}) async {
    return mockImpacts;
  }

  @override
  Future<List<DepartmentCapacityModel>> fetchDepartmentCapacities() async {
    return mockCapacities;
  }

  @override
  Future<List<ProductionBottleneckModel>> fetchBottlenecks() async {
    return mockBottlenecks;
  }

  @override
  Future<Map<String, dynamic>?> triggerSimulationAction({
    required String action,
    double hours = 2.0,
    String? machineCode,
  }) async {
    lastActionTriggered = action;
    return {'success': triggerSimSuccess, 'action': action, 'hours': hours};
  }
}

FakeProductionApiService _buildFakeService() {
  final service = FakeProductionApiService();

  final deptCaps = [
    const DepartmentCapacityModel(
      departmentId: 1,
      departmentCode: 'SPN',
      departmentName: 'Spinning Mills',
      totalMachines: 6,
      activeMachines: 6,
      downMachines: 0,
      nominalCapacityDaily: 12000.0,
      effectiveCapacityDaily: 11400.0,
      allocatedCapacityDaily: 8500.0,
      actualProducedDaily: 8200.0,
      utilizationPct: 74.5,
      downtimeLossDaily: 0.0,
      bottleneckSeverity: 'NORMAL',
      availableHeadroomUnits: 2900.0,
    ),
    const DepartmentCapacityModel(
      departmentId: 2,
      departmentCode: 'WEV',
      departmentName: 'Weaving Shed',
      totalMachines: 6,
      activeMachines: 5,
      downMachines: 1,
      nominalCapacityDaily: 9600.0,
      effectiveCapacityDaily: 8000.0,
      allocatedCapacityDaily: 7600.0,
      actualProducedDaily: 6900.0,
      utilizationPct: 95.0,
      downtimeLossDaily: 1600.0,
      bottleneckSeverity: 'CRITICAL',
      availableHeadroomUnits: 400.0,
    ),
  ];

  final bottlenecks = [
    const ProductionBottleneckModel(
      id: 1,
      departmentCode: 'WEV',
      departmentName: 'Weaving Shed',
      machineCode: 'WEV-03',
      severity: 'CRITICAL',
      bottleneckType: 'MACHINE_BREAKDOWN',
      primaryCause: 'Main Drive Motor Bearing Seizure',
      affectedOrdersCount: 2,
      deficitPerHour: 120.0,
      estimatedDelayHours: 6.5,
    ),
  ];

  final impacts = [
    const ProductionImpactAssessmentModel(
      id: 1,
      assessmentCode: 'IMPACT-WEV-03-001',
      machineCode: 'WEV-03',
      machineName: 'Picanol Airjet Loom 03',
      incidentCode: 'INC-2026-0042',
      estimatedDowntimeHours: 4.5,
      outputQuantityAtRisk: 850.0,
      ordersAffectedCount: 2,
      overallDelayRisk: 'HIGH',
      deterministicLossInr: 127500.0,
      aiExplanation: 'Loom WEV-03 breakdown directly impacts PO-2026-1002 cotton drill weave target.',
      recommendations: [
        'Reroute batch BATCH-2026-002 to WEV-04 at 85% speed',
        'Expedite bearing replacement ticket TIC-4401',
      ],
    ),
  ];

  service.mockOverview = ProductionOverviewModel(
    timestamp: DateTime.now(),
    metrics: {
      'active_orders': 6,
      'at_risk_orders': 2,
      'total_target_units': 50000.0,
      'total_completed_units': 32400.0,
      'overall_utilization_pct': 82.4,
      'active_bottlenecks': 1,
      'total_loss_inr': 127500.0,
    },
    departmentCapacities: deptCaps,
    activeBottlenecks: bottlenecks,
    recentImpactAssessments: impacts,
  );

  service.mockCapacities = deptCaps;
  service.mockBottlenecks = bottlenecks;
  service.mockImpacts = impacts;

  service.mockOrders = [
    const ProductionOrderModel(
      id: 1,
      orderNumber: 'PO-2026-1001',
      clientName: 'Arvind Mill Fab',
      customerPoNumber: 'AMF-PO-9921',
      fabricOrYarnSpec: 'Cotton Ring Spun 30s Carded',
      productCategory: 'COMBED_YARN',
      departmentName: 'Spinning Mills',
      departmentCode: 'SPN',
      targetQuantity: 5000.0,
      unit: 'KG',
      completedQuantity: 3400.0,
      remainingQuantity: 1600.0,
      status: 'IN_PROGRESS',
      priority: 'HIGH',
      routingStages: ['SPINNING', 'QUALITY_INSPECTION', 'DISPATCH'],
      currentStage: 'SPINNING',
      startDate: '2026-10-10',
      dueDate: '2026-10-18',
      targetDeliveryDate: '2026-10-18',
      projectedCompletionDate: '2026-10-16',
      estimatedRemainingHours: 24.0,
      delayRiskScore: 18.5,
      delayRiskLevel: 'LOW',
      estimatedDelayHours: 0.0,
      progressPct: 68.0,
      batches: [
        ProductionBatchModel(
          id: 101,
          batchNumber: 'BATCH-2026-001A',
          orderNumber: 'PO-2026-1001',
          machineCode: 'SPN-01',
          machineName: 'Rieter Ring Frame 01',
          plannedQuantity: 2500.0,
          actualQuantity: 2000.0,
          defectQuantity: 12.0,
          status: 'RUNNING',
          effectiveSpeedPct: 98.0,
          progressPct: 80.0,
        ),
      ],
      machineAssignments: [
        MachineAssignmentModel(
          id: 201,
          machineCode: 'SPN-01',
          machineName: 'Rieter Ring Frame 01',
          orderNumber: 'PO-2026-1001',
          stageName: 'Spinning',
          status: 'OCCUPIED',
          shift: 'SHIFT_1',
          plannedRunHours: 16.0,
          actualRunHours: 12.0,
        ),
      ],
    ),
    const ProductionOrderModel(
      id: 2,
      orderNumber: 'PO-2026-1002',
      clientName: 'Vardhman Textiles',
      customerPoNumber: 'VT-PO-8812',
      fabricOrYarnSpec: 'Cotton Drill Twill 240 GSM',
      productCategory: 'WOVEN_FABRIC',
      departmentName: 'Weaving Shed',
      departmentCode: 'WEV',
      targetQuantity: 8000.0,
      unit: 'METERS',
      completedQuantity: 2100.0,
      remainingQuantity: 5900.0,
      status: 'IN_PROGRESS',
      priority: 'CRITICAL',
      routingStages: ['WEAVING', 'DYEING', 'FINISHING', 'DISPATCH'],
      currentStage: 'WEAVING',
      startDate: '2026-10-09',
      dueDate: '2026-10-16',
      targetDeliveryDate: '2026-10-16',
      projectedCompletionDate: '2026-10-18',
      estimatedRemainingHours: 42.0,
      delayRiskScore: 82.0,
      delayRiskLevel: 'HIGH',
      estimatedDelayHours: 14.5,
      progressPct: 26.25,
      batches: [],
      machineAssignments: [],
    ),
  ];

  service.mockAssignments = [
    const MachineAssignmentModel(
      id: 201,
      machineCode: 'SPN-01',
      machineName: 'Rieter Ring Frame 01',
      orderNumber: 'PO-2026-1001',
      stageName: 'Spinning',
      status: 'OCCUPIED',
      shift: 'SHIFT_1',
      plannedRunHours: 16.0,
      actualRunHours: 12.0,
    ),
    const MachineAssignmentModel(
      id: 202,
      machineCode: 'WEV-03',
      machineName: 'Picanol Airjet Loom 03',
      orderNumber: 'PO-2026-1002',
      stageName: 'Weaving',
      status: 'PAUSED',
      shift: 'SHIFT_2',
      plannedRunHours: 24.0,
      actualRunHours: 6.0,
    ),
  ];

  return service;
}

void main() {
  group('ProductionIntelligenceScreen Tests', () {
    testWidgets('renders desktop layout (1440x900) without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Production Intelligence'), findsOneWidget);
      expect(find.text('PHASE 15'), findsOneWidget);
      expect(find.text('Command Overview'), findsOneWidget);
      expect(find.text('Orders & Deadlines'), findsOneWidget);
      expect(find.text('Machine Assignments'), findsOneWidget);
      expect(find.text('Bottlenecks & AI Impact'), findsOneWidget);

      // Verify overview KPI cards
      expect(find.text('Active Orders'), findsOneWidget);
      expect(find.text('Target Completion'), findsOneWidget);
      expect(find.text('Plant Utilization'), findsOneWidget);
      expect(find.text('Delivery Commitments'), findsOneWidget);

      // Verify Department Capacity Matrix
      expect(find.text('Department Capacity Matrix & Bottlenecks'), findsOneWidget);
      expect(find.text('SPN'), findsWidgets);
      expect(find.text('WEV'), findsWidgets);

      // Verify Simulation Sandbox
      expect(find.text('Simulation Sandbox Controls:'), findsOneWidget);
      expect(find.text('+2h Shift Output'), findsOneWidget);
      expect(find.text('Break Down Loom'), findsOneWidget);
      expect(find.text('Restore Capacity'), findsOneWidget);
    });

    testWidgets('renders tablet layout (800x600) without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Production Intelligence'), findsOneWidget);
      expect(find.text('Command Overview'), findsOneWidget);
    });

    testWidgets('renders narrow mobile layout (480x800) without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Production Intelligence'), findsOneWidget);
    });

    testWidgets('renders compact mobile layout (360x740) without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Production Intelligence'), findsOneWidget);
    });

    testWidgets('renders ultra-narrow layout (320x640) without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Production Intelligence'), findsOneWidget);
    });

    testWidgets('navigates to Orders tab, filters, and opens order details dialog', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Click "Orders & Deadlines" tab
      final ordersTab = find.text('Orders & Deadlines');
      expect(ordersTab, findsOneWidget);
      await tester.tap(ordersTab);
      await tester.pumpAndSettle();

      expect(find.text('PO-2026-1001'), findsOneWidget);
      expect(find.text('PO-2026-1002'), findsOneWidget);
      expect(find.text('Arvind Mill Fab'), findsOneWidget);

      // Tap on an order card to open details dialog
      await tester.tap(find.text('PO-2026-1001'));
      await tester.pumpAndSettle();

      // Verify order detail dialog
      expect(find.text('PO-2026-1001 — Arvind Mill Fab'), findsOneWidget);
      expect(find.text('Customer PO: AMF-PO-9921'), findsOneWidget);
      expect(find.text('Specification: Cotton Ring Spun 30s Carded'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('PO-2026-1001 — Arvind Mill Fab'), findsNothing);
    });

    testWidgets('navigates to Machine Assignments tab and verifies assignments list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Click "Machine Assignments" tab
      await tester.tap(find.text('Machine Assignments'));
      await tester.pumpAndSettle();

      expect(find.text('Machine Asset Production Allocation Matrix'), findsOneWidget);
      expect(find.text('SPN-01'), findsOneWidget);
      expect(find.text('WEV-03'), findsOneWidget);
    });

    testWidgets('navigates to Bottlenecks & AI Impact tab and verifies explanations', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      // Click "Bottlenecks & AI Impact" tab
      await tester.tap(find.text('Bottlenecks & AI Impact'));
      await tester.pumpAndSettle();

      expect(find.text('Detected Manufacturing Bottlenecks'), findsOneWidget);
      expect(find.text('Main Drive Motor Bearing Seizure'), findsOneWidget);
      expect(find.text('IMPACT-WEV-03-001'), findsOneWidget);
      expect(
        find.text('Loom WEV-03 breakdown directly impacts PO-2026-1002 cotton drill weave target.'),
        findsOneWidget,
      );
      expect(
        find.text('Reroute batch BATCH-2026-002 to WEV-04 at 85% speed'),
        findsOneWidget,
      );
    });

    testWidgets('triggers Advance +2h simulation button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = _buildFakeService();

      await tester.pumpWidget(
        MaterialApp(
          home: ProductionIntelligenceScreen(apiService: service),
        ),
      );
      await tester.pumpAndSettle();

      final advanceBtn = find.text('+2h Shift Output');
      expect(advanceBtn, findsOneWidget);
      await tester.tap(advanceBtn);
      await tester.pumpAndSettle();

      expect(service.lastActionTriggered, 'advance');
    });
  });
}
