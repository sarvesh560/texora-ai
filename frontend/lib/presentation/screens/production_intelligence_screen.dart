import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/production_models.dart';
import '../../data/services/production_api_service.dart';
import 'factory_recovery_screen.dart';

class ProductionIntelligenceScreen extends StatefulWidget {
  final ProductionApiService? apiService;
  final Function(int, {String? targetMachine})? onNavigate;

  const ProductionIntelligenceScreen({
    super.key,
    this.apiService,
    this.onNavigate,
  });

  @override
  State<ProductionIntelligenceScreen> createState() => _ProductionIntelligenceScreenState();
}

class _ProductionIntelligenceScreenState extends State<ProductionIntelligenceScreen> {
  late final ProductionApiService _apiService;
  bool _isLoading = true;
  String? _errorMessage;

  ProductionOverviewModel? _overview;
  List<ProductionOrderModel> _orders = [];
  List<DepartmentCapacityModel> _capacities = [];
  List<ProductionBottleneckModel> _bottlenecks = [];
  List<MachineAssignmentModel> _assignments = [];
  List<ProductionImpactAssessmentModel> _impactAssessments = [];

  // Filter state
  int _selectedTabIndex = 0; // 0: Overview, 1: Orders, 2: Assignments, 3: Bottlenecks & AI Impact, 4: Factory Recovery
  String _orderFilter = 'ALL'; // ALL, IN_PROGRESS, AT_RISK, COMPLETED
  String _searchQuery = '';
  bool _isActionRunning = false;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ProductionApiService();
    _loadProductionData();
  }

  Future<void> _loadProductionData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final overviewFuture = _apiService.fetchProductionOverview();
      final ordersFuture = _apiService.fetchOrders();
      final assignsFuture = _apiService.fetchMachineAssignments();
      final impactsFuture = _apiService.fetchImpactAssessments();

      final results = await Future.wait([overviewFuture, ordersFuture, assignsFuture, impactsFuture]);

      final overview = results[0] as ProductionOverviewModel?;
      final orders = results[1] as List<ProductionOrderModel>;
      final assigns = results[2] as List<MachineAssignmentModel>;
      final impacts = results[3] as List<ProductionImpactAssessmentModel>;

      if (mounted) {
        setState(() {
          _overview = overview;
          _orders = orders;
          _assignments = assigns;
          _impactAssessments = impacts;
          _capacities = overview?.departmentCapacities ?? [];
          _bottlenecks = overview?.activeBottlenecks ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load production data: $e';
        });
      }
    }
  }

  Future<void> _triggerSimAction(String action, {double hours = 2.0, String? machineCode}) async {
    setState(() => _isActionRunning = true);
    try {
      final res = await _apiService.triggerSimulationAction(
        action: action,
        hours: hours,
        machineCode: machineCode,
      );
      if (mounted) {
        final success = res?['success'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? TexoraColors.cardBg : TexoraColors.criticalBg,
            content: Text(
              success
                  ? 'Simulation action "$action" completed successfully.'
                  : 'Simulation action "$action" failed.',
              style: TextStyle(color: success ? TexoraColors.textPrimary : TexoraColors.criticalText),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        await _loadProductionData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: TexoraColors.criticalBg,
            content: Text('Simulation error: $e', style: const TextStyle(color: TexoraColors.criticalText)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final isNarrow = screenWidth < 700;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(isNarrow),
                _buildTabBar(isNarrow),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: TexoraColors.primaryBlue))
                      : _errorMessage != null
                          ? _buildErrorView()
                          : _buildSelectedTabContent(screenWidth),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(bool isNarrow) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 20, vertical: 12),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TexoraColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: TexoraColors.primaryLightBorder),
            ),
            child: const Icon(
              Icons.factory_rounded,
              color: TexoraColors.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Production Intelligence',
                        style: TextStyle(
                          color: TexoraColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: TexoraColors.successBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: TexoraColors.successBorder),
                      ),
                      child: const Text(
                        'PHASE 15',
                        style: TextStyle(
                          color: TexoraColors.successText,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Multi-Department Simulated Capacity Routing, Bottlenecks & Delivery Commitments',
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _isActionRunning ? null : _loadProductionData,
            tooltip: 'Refresh Production State',
            icon: const Icon(Icons.refresh_rounded, color: TexoraColors.textSecondary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isNarrow) {
    final tabs = [
      {'title': 'Command Overview', 'icon': Icons.dashboard_outlined},
      {'title': 'Orders & Deadlines', 'icon': Icons.assignment_outlined},
      {'title': 'Machine Assignments', 'icon': Icons.precision_manufacturing_outlined},
      {'title': 'Bottlenecks & AI Impact', 'icon': Icons.warning_amber_rounded},
      {'title': 'Factory Recovery & Rescheduling', 'icon': Icons.auto_mode_outlined},
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 16, vertical: 4),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (idx) {
            final isSelected = _selectedTabIndex == idx;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedTabIndex = idx),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? TexoraColors.primaryLight : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? TexoraColors.primaryLightBorder : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[idx]['icon'] as IconData,
                        size: 15,
                        color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tabs[idx]['title'] as String,
                        style: TextStyle(
                          color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: TexoraColors.criticalText, size: 40),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Unknown error',
              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadProductionData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TexoraColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedTabContent(double screenWidth) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildOverviewTab(screenWidth);
      case 1:
        return _buildOrdersTab(screenWidth);
      case 2:
        return _buildAssignmentsTab(screenWidth);
      case 3:
        return _buildBottlenecksAndImpactTab(screenWidth);
      case 4:
        return const FactoryRecoveryScreen();
      default:
        return _buildOverviewTab(screenWidth);
    }
  }

  // -------------------------------------------------------------------------
  // TAB 0: COMMAND OVERVIEW & CAPACITIES
  // -------------------------------------------------------------------------
  Widget _buildOverviewTab(double screenWidth) {
    final metrics = _overview?.metrics ?? {};
    final activeOrders = metrics['active_orders'] ?? 0;
    final totalTarget = metrics['total_target_units'] ?? 0.0;
    final totalDone = metrics['total_completed_units'] ?? 0.0;
    final progressPct = metrics['overall_progress_pct'] ?? 0.0;
    final plantUtil = metrics['plant_utilization_pct'] ?? 0.0;
    final atRiskCount = metrics['at_risk_orders_count'] ?? 0;
    final activeBottlenecks = metrics['active_bottlenecks_count'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simulation Control Bar
          _buildSimulationControlBar(screenWidth),
          const SizedBox(height: 16),

          // KPI Metrics Grid
          _buildKpiMetricsGrid(
            screenWidth: screenWidth,
            activeOrders: activeOrders,
            totalTarget: totalTarget,
            totalDone: totalDone,
            progressPct: progressPct,
            plantUtil: plantUtil,
            atRiskCount: atRiskCount,
            activeBottlenecks: activeBottlenecks,
          ),
          const SizedBox(height: 20),

          // Department Capacity Load Cards
          Row(
            children: const [
              Icon(Icons.pie_chart_outline_rounded, color: TexoraColors.primaryBlue, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Department Capacity Matrix & Bottlenecks',
                  style: TextStyle(
                    color: TexoraColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildDepartmentCapacitiesGrid(screenWidth),

          const SizedBox(height: 24),

          // Quick summary of at-risk orders
          if (atRiskCount > 0) ...[
            _buildAtRiskAlertBanner(),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSimulationControlBar(double screenWidth) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.tune_rounded, color: Color(0xFFF59E0B), size: 16),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Simulation Sandbox Controls:',
                  style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildSimBtn(
                label: '+2h Shift Output',
                icon: Icons.fast_forward_rounded,
                color: const Color(0xFF10B981),
                onTap: _isActionRunning ? null : () => _triggerSimAction('advance', hours: 2.0),
              ),
              _buildSimBtn(
                label: 'Break Down Loom',
                icon: Icons.broken_image_rounded,
                color: const Color(0xFFEF4444),
                onTap: _isActionRunning ? null : () => _triggerSimAction('breakdown', machineCode: 'WEV-AJ-02', hours: 3.0),
              ),
              _buildSimBtn(
                label: 'Restore Capacity',
                icon: Icons.build_circle_rounded,
                color: TexoraColors.primaryBlue,
                onTap: _isActionRunning ? null : () => _triggerSimAction('recover', machineCode: 'WEV-AJ-02'),
              ),
              _buildSimBtn(
                label: 'Seed Baseline',
                icon: Icons.restart_alt_rounded,
                color: TexoraColors.textSecondary,
                onTap: _isActionRunning ? null : () => _triggerSimAction('seed'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiMetricsGrid({
    required double screenWidth,
    required dynamic activeOrders,
    required dynamic totalTarget,
    required dynamic totalDone,
    required dynamic progressPct,
    required dynamic plantUtil,
    required dynamic atRiskCount,
    required dynamic activeBottlenecks,
  }) {
    int crossAxisCount = 4;
    if (screenWidth < 600) {
      crossAxisCount = 1;
    } else if (screenWidth < 1000) {
      crossAxisCount = 2;
    }

    final cards = [
      _buildMetricCard(
        title: 'Active Orders',
        value: '$activeOrders Orders',
        subtitle: 'Target: ${totalTarget.toStringAsFixed(0)} units',
        icon: Icons.assignment_turned_in_rounded,
        accentColor: TexoraColors.primaryBlue,
      ),
      _buildMetricCard(
        title: 'Target Completion',
        value: '${progressPct.toStringAsFixed(1)}%',
        subtitle: '${totalDone.toStringAsFixed(0)} units produced',
        icon: Icons.analytics_outlined,
        accentColor: const Color(0xFF10B981),
      ),
      _buildMetricCard(
        title: 'Plant Utilization',
        value: '${plantUtil.toStringAsFixed(1)}%',
        subtitle: 'Headroom: ${(100.0 - plantUtil).clamp(0.0, 100.0).toStringAsFixed(1)}%',
        icon: Icons.speed_rounded,
        accentColor: plantUtil > 85.0 ? const Color(0xFFF59E0B) : TexoraColors.primaryBlue,
      ),
      _buildMetricCard(
        title: 'Delivery Commitments',
        value: atRiskCount > 0 ? '$atRiskCount At Risk' : 'All On Track',
        subtitle: '$activeBottlenecks active bottlenecks',
        icon: atRiskCount > 0 ? Icons.error_outline_rounded : Icons.verified_outlined,
        accentColor: atRiskCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      ),
    ];

    if (crossAxisCount == 1) {
      return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList());
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: crossAxisCount == 4 ? 2.1 : 2.5,
      children: cards,
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentCapacitiesGrid(double screenWidth) {
    if (_capacities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TexoraColors.cardBorder),
        ),
        child: const Text(
          'No department capacity profiles loaded. Trigger Seed Baseline to initialize.',
          style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
        ),
      );
    }

    int cols = 5;
    if (screenWidth < 650) {
      cols = 1;
    } else if (screenWidth < 1100) {
      cols = 2;
    } else if (screenWidth < 1350) {
      cols = 3;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _capacities.map((cap) {
            return SizedBox(
              width: itemWidth,
              child: _buildDepartmentCapacityCard(cap),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDepartmentCapacityCard(DepartmentCapacityModel cap) {
    Color utilColor = const Color(0xFF10B981);
    if (cap.utilizationPct >= 90.0) {
      utilColor = const Color(0xFFEF4444);
    } else if (cap.utilizationPct >= 75.0) {
      utilColor = const Color(0xFFF59E0B);
    }

    final hasBottleneck = cap.bottleneckSeverity == 'CRITICAL' || cap.bottleneckSeverity == 'SEVERE';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasBottleneck ? const Color(0xFFEF4444).withAlpha(120) : TexoraColors.cardBorder,
          width: hasBottleneck ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: TexoraColors.primaryLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        cap.departmentCode,
                        style: const TextStyle(
                          color: TexoraColors.primaryBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        cap.departmentName,
                        style: const TextStyle(
                          color: TexoraColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasBottleneck)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: TexoraColors.criticalBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'BOTTLENECK',
                    style: TextStyle(
                      color: TexoraColors.criticalText,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Utilization:', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
              Text(
                '${cap.utilizationPct.toStringAsFixed(1)}%',
                style: TextStyle(color: utilColor, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (cap.utilizationPct / 100.0).clamp(0.0, 1.0),
              backgroundColor: TexoraColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(utilColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 10),
          _buildCompactDataRow('Active Machinery', '${cap.activeMachines}/${cap.totalMachines} online'),
          _buildCompactDataRow('Effective Capacity', '${cap.effectiveCapacityDaily.toStringAsFixed(0)} u/day'),
          _buildCompactDataRow('Headroom Buffer', '${cap.availableHeadroomUnits.toStringAsFixed(0)} units'),
          if (cap.downMachines > 0)
            _buildCompactDataRow('Down Machinery', '${cap.downMachines} offline', valueColor: const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _buildCompactDataRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAtRiskAlertBanner() {
    final atRiskOrders = _orders.where((o) => o.delayRiskLevel == 'HIGH' || o.delayRiskLevel == 'CRITICAL').toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.criticalBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.criticalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: TexoraColors.criticalText, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Critical Production Deadline Risk Alert (${atRiskOrders.length} orders threatened)',
                  style: const TextStyle(color: TexoraColors.criticalText, fontSize: 13, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...atRiskOrders.take(3).map((ord) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.arrow_right_rounded, color: TexoraColors.criticalText, size: 16),
                  Flexible(
                    child: Text(
                      '${ord.orderNumber} — ${ord.clientName} (Due: ${ord.dueDate ?? 'N/A'}, Est. Delay: +${ord.estimatedDelayHours.toStringAsFixed(1)}h)',
                      style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // TAB 1: ORDERS & DELIVERY COMMITMENTS
  // -------------------------------------------------------------------------
  Widget _buildOrdersTab(double screenWidth) {
    final filteredOrders = _orders.where((o) {
      if (_orderFilter == 'IN_PROGRESS' && o.status != 'IN_PROGRESS') return false;
      if (_orderFilter == 'AT_RISK' && (o.delayRiskLevel != 'HIGH' && o.delayRiskLevel != 'CRITICAL')) return false;
      if (_orderFilter == 'COMPLETED' && o.status != 'COMPLETED') return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return o.orderNumber.toLowerCase().contains(q) ||
            o.clientName.toLowerCase().contains(q) ||
            o.fabricOrYarnSpec.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Toolbar
          _buildOrdersFilterToolbar(screenWidth),
          const SizedBox(height: 12),

          if (filteredOrders.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                'No orders matching current filter "$_orderFilter".',
                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 13),
              ),
            )
          else
            ...filteredOrders.map((ord) => _buildOrderCard(ord, screenWidth)),
        ],
      ),
    );
  }

  Widget _buildOrdersFilterToolbar(double screenWidth) {
    final filterOptions = [
      {'key': 'ALL', 'label': 'All Orders (${_orders.length})'},
      {'key': 'IN_PROGRESS', 'label': 'In Progress'},
      {'key': 'AT_RISK', 'label': 'At Risk'},
      {'key': 'COMPLETED', 'label': 'Completed'},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          width: 220,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: TexoraColors.cardBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: TexoraColors.cardBorder),
          ),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11),
            decoration: const InputDecoration(
              icon: Icon(Icons.search, size: 14, color: TexoraColors.textMuted),
              hintText: 'Search order or client...',
              hintStyle: TextStyle(color: TexoraColors.textMuted, fontSize: 11),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        ...filterOptions.map((f) {
          final isSel = _orderFilter == f['key'];
          return ChoiceChip(
            label: Text(f['label']!),
            selected: isSel,
            onSelected: (_) => setState(() => _orderFilter = f['key']!),
            selectedColor: TexoraColors.primaryLight,
            backgroundColor: TexoraColors.cardBg,
            side: BorderSide(color: isSel ? TexoraColors.primaryBlue : TexoraColors.cardBorder),
            labelStyle: TextStyle(
              color: isSel ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
              fontSize: 11,
              fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOrderCard(ProductionOrderModel ord, double screenWidth) {
    Color riskColor = const Color(0xFF10B981);
    if (ord.delayRiskLevel == 'CRITICAL') {
      riskColor = const Color(0xFFEF4444);
    } else if (ord.delayRiskLevel == 'HIGH') {
      riskColor = const Color(0xFFF97316);
    } else if (ord.delayRiskLevel == 'MEDIUM') {
      riskColor = const Color(0xFFF59E0B);
    }

    return Card(
      color: TexoraColors.cardBg,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ord.delayRiskLevel == 'CRITICAL' ? riskColor.withAlpha(120) : TexoraColors.cardBorder),
      ),
      elevation: 0,
      child: InkWell(
        onTap: () => _showOrderDetailDialog(ord),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: TexoraColors.primaryLight,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: TexoraColors.primaryLightBorder),
                          ),
                          child: Text(
                            ord.orderNumber,
                            style: const TextStyle(color: TexoraColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            ord.clientName,
                            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: riskColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: riskColor.withAlpha(80)),
                    ),
                    child: Text(
                      ord.estimatedDelayHours > 0
                          ? '${ord.delayRiskLevel} (+${ord.estimatedDelayHours.toStringAsFixed(0)}h)'
                          : ord.delayRiskLevel,
                      style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                ord.fabricOrYarnSpec,
                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Progress: ${ord.completedQuantity.toStringAsFixed(0)} / ${ord.targetQuantity.toStringAsFixed(0)} ${ord.unit}',
                      style: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${ord.progressPct.toStringAsFixed(1)}%',
                    style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (ord.progressPct / 100.0).clamp(0.0, 1.0),
                  backgroundColor: TexoraColors.cardBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _buildInlineTag(Icons.calendar_today_rounded, 'Due: ${ord.dueDate ?? 'N/A'}'),
                  _buildInlineTag(Icons.schedule_rounded, 'Est. Finish: ${ord.projectedCompletionDate ?? 'N/A'}'),
                  _buildInlineTag(Icons.route_rounded, 'Stage: ${ord.currentStage}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineTag(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: TexoraColors.textMuted),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10)),
      ],
    );
  }

  void _showOrderDetailDialog(ProductionOrderModel ord) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: TexoraColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: TexoraColors.cardBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.assignment_outlined, color: TexoraColors.primaryBlue, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${ord.orderNumber} — ${ord.clientName}',
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Specification: ${ord.fabricOrYarnSpec}', style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12)),
                  if (ord.customerPoNumber.isNotEmpty)
                    Text('Customer PO: ${ord.customerPoNumber}', style: const TextStyle(color: TexoraColors.textMuted, fontSize: 11)),
                  const SizedBox(height: 12),
                  const Divider(color: TexoraColors.cardBorder),
                  const SizedBox(height: 8),
                  const Text('Manufacturing Routing Stages:', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ord.routingStages.map((stage) {
                      final isCurrent = stage == ord.departmentCode;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCurrent ? TexoraColors.primaryLight : TexoraColors.workspaceBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isCurrent ? TexoraColors.primaryLightBorder : TexoraColors.cardBorder,
                          ),
                        ),
                        child: Text(
                          stage,
                          style: TextStyle(
                            color: isCurrent ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: TexoraColors.cardBorder),
                  const SizedBox(height: 8),
                  const Text('Delivery Intelligence:', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _buildCompactDataRow('Due Date', ord.dueDate ?? 'N/A'),
                  _buildCompactDataRow('Projected Completion', ord.projectedCompletionDate ?? 'N/A'),
                  _buildCompactDataRow('Remaining Production Time', '${ord.estimatedRemainingHours.toStringAsFixed(1)} hours'),
                  _buildCompactDataRow('Estimated Delay', '+${ord.estimatedDelayHours.toStringAsFixed(1)} hours'),
                  _buildCompactDataRow('Delay Risk Level', ord.delayRiskLevel, valueColor: const Color(0xFFF97316)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close', style: TextStyle(color: TexoraColors.primaryBlue)),
            ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // TAB 2: MACHINE ASSIGNMENTS
  // -------------------------------------------------------------------------
  Widget _buildAssignmentsTab(double screenWidth) {
    if (_assignments.isEmpty) {
      return const Center(
        child: Text('No active machine assignments recorded.', style: TextStyle(color: TexoraColors.textSecondary)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Machine Asset Production Allocation Matrix',
            style: TextStyle(color: TexoraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ..._assignments.map((assign) {
            final isRunning = assign.status == 'RUNNING';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isRunning ? const Color(0xFF10B981).withAlpha(80) : TexoraColors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TexoraColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.precision_manufacturing_rounded, color: TexoraColors.primaryBlue, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              assign.machineCode,
                              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: isRunning ? const Color(0xFF10B981).withAlpha(20) : const Color(0xFFEF4444).withAlpha(20),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                assign.status,
                                style: TextStyle(
                                  color: isRunning ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Order: ${assign.orderNumber} • Stage: ${assign.stageName}',
                          style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${assign.actualRunHours.toStringAsFixed(0)}/${assign.plannedRunHours.toStringAsFixed(0)}h',
                    style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // TAB 3: BOTTLENECKS & AI PRODUCTION IMPACT INTELLIGENCE
  // -------------------------------------------------------------------------
  Widget _buildBottlenecksAndImpactTab(double screenWidth) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Bottlenecks
          Row(
            children: const [
              Icon(Icons.report_problem_outlined, color: Color(0xFFEF4444), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Detected Manufacturing Bottlenecks',
                  style: TextStyle(color: TexoraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_bottlenecks.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TexoraColors.cardBorder),
              ),
              child: const Text(
                'No active bottlenecks detected across production departments.',
                style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            )
          else
            ..._bottlenecks.map(_buildBottleneckCard),

          const SizedBox(height: 24),

          // Section 2: AI Production Impact Assessments
          Row(
            children: const [
              Icon(Icons.psychology_rounded, color: Color(0xFFA855F7), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Production Impact Agent Disruption Assessments',
                  style: TextStyle(color: TexoraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_impactAssessments.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TexoraColors.cardBorder),
              ),
              child: const Text(
                'No active machinery breakdown impact assessments logged.',
                style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
              ),
            )
          else
            ..._impactAssessments.map(_buildImpactCard),
        ],
      ),
    );
  }

  Widget _buildBottleneckCard(ProductionBottleneckModel b) {
    Color sevColor = const Color(0xFFEF4444);
    if (b.severity == 'HIGH') sevColor = const Color(0xFFF97316);
    if (b.severity == 'MEDIUM') sevColor = const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sevColor.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: sevColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${b.departmentCode} • ${b.severity}',
                        style: TextStyle(color: sevColor, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (b.machineCode != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          b.machineCode!,
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '-${b.deficitPerHour.toStringAsFixed(1)} units/hr deficit',
                style: TextStyle(color: sevColor, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(b.primaryCause, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            'Affected Orders: ${b.affectedOrdersCount} • Estimated Delay Impact: +${b.estimatedDelayHours.toStringAsFixed(1)}h',
            style: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildImpactCard(ProductionImpactAssessmentModel imp) {
    Color riskColor = const Color(0xFFEF4444);
    if (imp.overallDelayRisk == 'HIGH') riskColor = const Color(0xFFF97316);
    if (imp.overallDelayRisk == 'MEDIUM') riskColor = const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA855F7).withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA855F7).withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        imp.assessmentCode,
                        style: const TextStyle(color: Color(0xFF9333EA), fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        imp.machineCode,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: riskColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: riskColor.withAlpha(80)),
                ),
                child: Text(
                  imp.overallDelayRisk,
                  style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            imp.aiExplanation.isNotEmpty ? imp.aiExplanation : 'Deterministic disruption assessment logged.',
            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, height: 1.3),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _buildInlineTag(Icons.timer_outlined, '${imp.estimatedDowntimeHours}h Downtime'),
              _buildInlineTag(Icons.trending_down_rounded, '${imp.outputQuantityAtRisk.toStringAsFixed(0)} units lost'),
              _buildInlineTag(Icons.currency_rupee_rounded, '₹${imp.deterministicLossInr.toStringAsFixed(0)} deficit'),
              _buildInlineTag(Icons.assignment_outlined, '${imp.ordersAffectedCount} orders affected'),
            ],
          ),
          if (imp.recommendations.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Recommendations:', style: TextStyle(color: TexoraColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ...imp.recommendations.take(2).map((rec) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(color: TexoraColors.primaryBlue)),
                      Expanded(
                        child: Text(rec, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
