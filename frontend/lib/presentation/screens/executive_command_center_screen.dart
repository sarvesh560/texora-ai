import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/models/production_models.dart';
import '../../data/services/api_service.dart';
import '../../data/services/production_api_service.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/industrial_widgets.dart';
import '../widgets/department_status_card.dart';
import '../widgets/ai_activity_center_widget.dart';
import '../widgets/autonomous_workflow_monitor.dart';

class ExecutiveCommandCenterScreen extends StatefulWidget {
  final Function(int navIndex, {String? targetMachine}) onNavigate;

  const ExecutiveCommandCenterScreen({
    super.key,
    required this.onNavigate,
  });

  @override
  State<ExecutiveCommandCenterScreen> createState() => _ExecutiveCommandCenterScreenState();
}

class _ExecutiveCommandCenterScreenState extends State<ExecutiveCommandCenterScreen> {
  final ApiService _apiService = ApiService();
  final ProductionApiService _productionApiService = ProductionApiService();

  DigitalTwinSnapshotModel? _snapshot;
  ProductionOverviewModel? _productionOverview;
  Map<String, dynamic> _recoverySummary = {};
  Map<String, dynamic> _autonomousStatus = {};
  List<dynamic> _autonomousRuns = [];
  List<dynamic> _incidents = [];
  List<dynamic> _executions = [];
  List<dynamic> _recoveryCases = [];

  bool _isLoading = true;
  bool _isExecutingPipeline = false;
  bool _isActionInProgress = false;
  String? _actionFeedback;
  String? _errorMessage;
  DateTime _lastRefreshTime = DateTime.now();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAllDashboardData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadAllDashboardData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllDashboardData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final snap = await _apiService.fetchDigitalTwinSnapshot(refresh: false);
      final recSummary = await _apiService.fetchRecoverySummary();
      final autoStatus = await _apiService.fetchAutonomousStatus();
      final autoRuns = await _apiService.fetchAutonomousRuns();
      final incs = await _apiService.fetchIncidents();
      final execs = await _apiService.fetchAgentExecutions();
      final recCases = await _apiService.fetchRecoveryCases();
      final prodOverview = await _productionApiService.fetchProductionOverview();

      if (mounted) {
        setState(() {
          _snapshot = snap;
          _productionOverview = prodOverview;
          _recoverySummary = recSummary;
          _autonomousStatus = autoStatus;
          _autonomousRuns = autoRuns;
          _incidents = incs;
          _executions = execs;
          _recoveryCases = recCases;
          _isLoading = false;
          _lastRefreshTime = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _dispatchAutonomousPipeline() async {
    setState(() {
      _isExecutingPipeline = true;
      _actionFeedback = '🚀 Injecting vibration anomaly on Loom WEV-RAP-01 and dispatching autonomous AI pipeline...';
    });

    try {
      final result = await _apiService.launchAutonomousExpoDemo(machineCode: 'WEV-RAP-01');
      if (mounted) {
        setState(() {
          _isExecutingPipeline = false;
          if (result['success'] == true) {
            _actionFeedback = '✅ Autonomous Pipeline Complete! Incident #${result['incident_id']} analyzed, What-If simulation finished. Recommended: ${result['recommended_strategy']}. Awaiting Manager Approval.';
          } else {
            _actionFeedback = '⚠️ Pipeline status: ${result['error'] ?? 'Execution completed'}';
          }
        });
        await _loadAllDashboardData(silent: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExecutingPipeline = false;
          _actionFeedback = '❌ Pipeline Error: $e';
        });
      }
    }
  }

  Future<void> _handleManagerDecision({
    required int recoveryCaseId,
    int? approvalId,
    required String action,
    String? strategy,
  }) async {
    setState(() {
      _isActionInProgress = true;
      _actionFeedback = 'Processing manager decision: $action...';
    });

    try {
      if (action == 'APPROVE') {
        final res = await _apiService.advanceAutonomousApproval(
          recoveryCaseId: recoveryCaseId,
          approvalRequestId: approvalId,
          approvedBy: 'Plant Operations Manager',
          selectedStrategy: strategy,
          responseNotes: 'Authorized by Operations Manager via Executive Command Center.',
        );
        if (mounted) {
          setState(() {
            _isActionInProgress = false;
            _actionFeedback = res['success'] == true
                ? '✅ Approved! Work order created, inventory reserved, production updated.'
                : '⚠️ ${res['error'] ?? 'Approval submitted'}';
          });
        }
      } else if (action == 'REQUEST_REVISION' && approvalId != null) {
        final ok = await _apiService.requestApprovalRevision(
          approvalId,
          requestedBy: 'Plant Operations Director',
          notes: 'Requested re-evaluation of production rerouting constraints.',
        );
        if (mounted) {
          setState(() {
            _isActionInProgress = false;
            _actionFeedback = ok ? '🔄 Revision requested. AI agents notified.' : '❌ Failed to request revision.';
          });
        }
      }
      await _loadAllDashboardData(silent: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _actionFeedback = '❌ Error: $e';
        });
      }
    }
  }

  Future<void> _handleTechnicianVerification(int recoveryCaseId) async {
    setState(() {
      _isActionInProgress = true;
      _actionFeedback = 'Checking maintenance completion and evaluating telemetry freshness...';
    });

    try {
      final res = await _apiService.verifyTechnicianRecovery(
        recoveryCaseId: recoveryCaseId,
        technicianName: 'Senior Textile Maintenance Specialist',
        repairNotes: 'Bearing replacement and alignment calibration completed.',
      );
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          if (res['verified'] == true) {
            _actionFeedback = '✅ RECOVERY VERIFIED! Telemetry is fresh & nominal (Vibration: ${res['latest_vibration_rms'] ?? 2.1} mm/s). Case closed.';
          } else {
            _actionFeedback = '⚠️ Verification Notice: ${res['message'] ?? res['error'] ?? 'Check telemetry freshness'}';
          }
        });
        await _loadAllDashboardData(silent: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isActionInProgress = false;
          _actionFeedback = '❌ Verification error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: _isLoading && _snapshot == null
          ? const Center(child: TexoraLoadingState(message: 'Loading factory operations...'))
          : _errorMessage != null && _snapshot == null
              ? Center(
                  child: TexoraErrorState(
                    message: _errorMessage!,
                    onRetry: () => _loadAllDashboardData(silent: false),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadAllDashboardData(silent: false),
                  child: ListView(
                    padding: const EdgeInsets.all(TexoraSpacing.xxl),
                    children: [
                      // 1. Reference Screen 1 Header (Factory Overview + AI Running status)
                      _buildFactoryOverviewHeader(),
                      const SizedBox(height: 16),

                      // 2. Reference Screen 1 Top 4 Compact KPI Cards
                      _buildReferenceKpiCards(),
                      const SizedBox(height: 20),

                      // 3. Reference Screen 1 Main Content (Factory Floor Schematic + Live AI Activity)
                      _buildReferenceMainContent(),
                      const SizedBox(height: 24),

                      // 4. Preserved Autonomous Operations & 1-Click Demo Studio
                      _buildAutonomousConsoleCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFactoryOverviewHeader() {
    final workerOnline = _autonomousStatus['worker_health']?['is_worker_running'] == true ||
        _autonomousStatus['is_worker_running'] == true;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Factory Overview',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: TexoraColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Autonomous Operations & Real-Time Intelligence',
              style: TextStyle(
                fontSize: 12,
                color: TexoraColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        );

        final actionWidget = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: workerOnline ? TexoraColors.successBg : TexoraColors.warningBg,
                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                  border: Border.all(
                    color: workerOnline ? TexoraColors.successBorder : TexoraColors.warningBorder,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: workerOnline ? TexoraColors.successText : TexoraColors.warningText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      workerOnline ? 'AI Running' : 'AI Standby',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: workerOnline ? TexoraColors.successText : TexoraColors.warningText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () => _loadAllDashboardData(silent: false),
                icon: const Icon(Icons.refresh_rounded, size: 20, color: TexoraColors.textSecondary),
                tooltip: 'Refresh Factory Overview',
              ),
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget,
              const SizedBox(height: 12),
              actionWidget,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleWidget),
            actionWidget,
          ],
        );
      },
    );
  }

  Widget _buildReferenceKpiCards() {
    final totalMachines = _snapshot?.totalMachines ?? 120;
    final opCount = (_snapshot?.operationalSummary['operational_count'] as num?)?.toInt() ??
        (_snapshot?.machineStates.where((m) => m.rawStatus == 'OPERATIONAL').length ?? 118);
    final runningPct = totalMachines > 0 ? ((opCount / totalMachines) * 100).round() : 98;

    double productionKg = 12450.0;
    if (_productionOverview != null && _productionOverview!.departmentCapacities.isNotEmpty) {
      final actualSum = _productionOverview!.departmentCapacities
          .fold<double>(0.0, (sum, dep) => sum + dep.actualProducedDaily);
      if (actualSum > 0) productionKg = actualSum;
    }

    double qualityPct = 98.2;
    if (_snapshot != null && _snapshot!.machineStates.isNotEmpty) {
      final avgHealth = _snapshot!.machineStates
              .fold<double>(0.0, (sum, m) => sum + m.healthScore) /
          _snapshot!.machineStates.length;
      if (avgHealth > 0) qualityPct = avgHealth;
    }

    double energyKwh = 18200.0;
    if (_snapshot != null && _snapshot!.machineStates.isNotEmpty) {
      final kwSum = _snapshot!.machineStates.fold<double>(0.0, (sum, m) {
        final power = (m.latestTelemetry?['power_kw'] as num?)?.toDouble() ?? 0.0;
        return sum + power;
      });
      if (kwSum > 0) energyKwh = kwSum * 16.0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        int crossAxisCount = 4;
        if (w < 600) {
          crossAxisCount = 1;
        } else if (w < 1050) {
          crossAxisCount = 2;
        }

        final cards = [
          TexoraKpiCard(
            label: 'Total Machines',
            value: '$totalMachines',
            subtitle: '$runningPct% Running',
            isPositive: true,
          ),
          TexoraKpiCard(
            label: 'Production Today',
            value: '${productionKg.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} kg',
            subtitle: '+8% vs yesterday',
            isPositive: true,
          ),
          TexoraKpiCard(
            label: 'Quality',
            value: '${qualityPct.toStringAsFixed(1)}%',
            subtitle: '+1.2%',
            isPositive: true,
          ),
          TexoraKpiCard(
            label: 'Energy Usage',
            value: '${energyKwh.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} kWh',
            subtitle: '-6%',
            isPositive: true,
          ),
        ];

        if (crossAxisCount == 1) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: c,
                    ))
                .toList(),
          );
        }

        final itemWidth = (w - (crossAxisCount - 1) * 16) / crossAxisCount;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildReferenceMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isStacked = constraints.maxWidth < 1050;

        final leftCard = _buildFactoryVisualizationCard();
        final rightCard = _buildLiveAiActivityCard();

        if (isStacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftCard,
              const SizedBox(height: 16),
              rightCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: leftCard,
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: rightCard,
            ),
          ],
        );
      },
    );
  }

  Widget _buildFactoryVisualizationCard() {
    final summary = _snapshot?.operationalSummary ?? {};
    final stateDist = (summary['state_distribution'] as Map<String, dynamic>?) ?? {};
    final deptSummaries = (summary['department_summaries'] as Map<String, dynamic>?) ?? {};
    final total = _snapshot?.totalMachines ?? 26;

    final runningCount = (stateDist['RUNNING'] as num?)?.toDouble() ?? 0.0;
    final warningCount = (stateDist['WARNING'] as num?)?.toDouble() ?? 0.0;
    final criticalCount = (stateDist['CRITICAL'] as num?)?.toDouble() ?? 0.0;
    final maintenanceCount = (stateDist['UNDER_MAINTENANCE'] as num?)?.toDouble() ?? 0.0;
    final idleCount = ((stateDist['IDLE'] as num?)?.toDouble() ?? 0.0) +
        ((stateDist['UNKNOWN'] as num?)?.toDouble() ?? 0.0);

    return TexoraCard(
      title: 'Factory Department Floor Map',
      subtitle: '5-Department textile operations and active asset distribution',
      trailing: TextButton.icon(
        onPressed: () => widget.onNavigate(1),
        icon: const Icon(Icons.hub_rounded, size: 14, color: TexoraColors.primaryBlue),
        label: const Text(
          'Digital Twin',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: TexoraColors.primaryBlue,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Interactive Donut Chart for Machine Status Distribution
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TexoraColors.workspaceBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: TexoraColors.borderDefault),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'FLEET STATUS DISTRIBUTION',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: TexoraColors.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      '$total Monitored Assets',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: TexoraColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: TexoraDonutChart(
                    size: 110,
                    strokeWidth: 14,
                    centerValue: '$total',
                    centerLabel: 'Machines',
                    segments: [
                      TexoraDonutSegment(
                        label: 'Running',
                        value: runningCount > 0 ? runningCount : 0.0,
                        color: TexoraColors.successText,
                        countLabel: '${runningCount.toInt()}',
                      ),
                      TexoraDonutSegment(
                        label: 'Warning',
                        value: warningCount > 0 ? warningCount : 0.0,
                        color: const Color(0xFFF59E0B),
                        countLabel: '${warningCount.toInt()}',
                      ),
                      TexoraDonutSegment(
                        label: 'Critical',
                        value: criticalCount > 0 ? criticalCount : 0.0,
                        color: TexoraColors.criticalText,
                        countLabel: '${criticalCount.toInt()}',
                      ),
                      TexoraDonutSegment(
                        label: 'Maintenance',
                        value: maintenanceCount > 0 ? maintenanceCount : 0.0,
                        color: const Color(0xFF64748B),
                        countLabel: '${maintenanceCount.toInt()}',
                      ),
                      TexoraDonutSegment(
                        label: 'Standby',
                        value: idleCount > 0
                            ? idleCount
                            : (total - runningCount - warningCount - criticalCount - maintenanceCount).clamp(0, total).toDouble(),
                        color: const Color(0xFF94A3B8),
                        countLabel: '${idleCount.toInt()}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5-Department Telemetry Grid with Live Database Counts
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final isNarrow = w < 540;
              final itemWidth = isNarrow ? w : (w - 16) / 2;

              final spnTotal = (deptSummaries['SPN']?['total_machines'] as num?)?.toInt() ?? 7;
              final wevTotal = (deptSummaries['WEV']?['total_machines'] as num?)?.toInt() ?? 7;
              final kntTotal = (deptSummaries['KNT']?['total_machines'] as num?)?.toInt() ?? 4;
              final dyeTotal = (deptSummaries['DYE']?['total_machines'] as num?)?.toInt() ?? 4;
              final finTotal = (deptSummaries['FIN']?['total_machines'] as num?)?.toInt() ?? 4;

              final departments = [
                _DepartmentNodeData(
                  code: 'SPN',
                  name: 'Spinning',
                  machineCount: spnTotal,
                  runningPct: 98,
                  icon: Icons.donut_large_rounded,
                  color: const Color(0xFF06B6D4),
                  bgColor: const Color(0xFFECFEFF),
                ),
                _DepartmentNodeData(
                  code: 'WEV',
                  name: 'Weaving',
                  machineCount: wevTotal,
                  runningPct: 96,
                  icon: Icons.grid_view_rounded,
                  color: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFEFF6FF),
                ),
                _DepartmentNodeData(
                  code: 'KNT',
                  name: 'Knitting',
                  machineCount: kntTotal,
                  runningPct: 94,
                  icon: Icons.all_inclusive_rounded,
                  color: const Color(0xFF0D9488),
                  bgColor: const Color(0xFFF0FDFA),
                ),
                _DepartmentNodeData(
                  code: 'DYE',
                  name: 'Dyeing',
                  machineCount: dyeTotal,
                  runningPct: 92,
                  icon: Icons.water_drop_rounded,
                  color: const Color(0xFF8B5CF6),
                  bgColor: const Color(0xFFFAF5FF),
                ),
                _DepartmentNodeData(
                  code: 'FIN',
                  name: 'Finishing',
                  machineCount: finTotal,
                  runningPct: 96,
                  icon: Icons.fact_check_rounded,
                  color: const Color(0xFFEC4899),
                  bgColor: const Color(0xFFFDF2F8),
                ),
              ];

              return Wrap(
                spacing: 16,
                runSpacing: 12,
                children: departments.map((dep) {
                  return SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      onTap: () => widget.onNavigate(3),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: TexoraColors.workspaceBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: TexoraColors.borderDefault),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: dep.bgColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: dep.color.withAlpha(50)),
                              ),
                              child: Icon(dep.icon, color: dep.color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dep.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: TexoraColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${dep.machineCount} Machines',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: TexoraColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TexoraStatusBadge(
                              label: '${dep.runningPct}% Running',
                              variant: TexoraBadgeVariant.running,
                              showDot: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveAiActivityCard() {
    return TexoraCard(
      title: 'Live AI Activity',
      subtitle: 'Real-time specialist agent events & automated actions',
      trailing: TextButton(
        onPressed: () => widget.onNavigate(8),
        child: const Text(
          'View All',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: TexoraColors.primaryBlue,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          if (_executions.isNotEmpty)
            ..._executions.take(5).map((exec) {
              final rawTime = exec['started_at'] ?? exec['created_at'];
              final timeStr = rawTime != null && rawTime.toString().length >= 16
                  ? rawTime.toString().substring(11, 16)
                  : '10:25';
              return _buildActivityTimelineItem(
                time: timeStr,
                dotColor: exec['status'] == 'FAILED'
                    ? TexoraColors.criticalText
                    : (exec['status'] == 'COMPLETED' ? TexoraColors.successText : TexoraColors.primaryBlue),
                title: exec['trigger_event'] ?? exec['agent_name'] ?? 'Autonomous Agent Event',
                subtitle: exec['execution_summary'] ?? '${exec['agent_name'] ?? 'Agent'} completed diagnostic cycle',
              );
            })
          else ...[
            _buildActivityTimelineItem(
              time: '10:24',
              dotColor: TexoraColors.criticalText,
              title: 'Abnormal vibration detected',
              subtitle: 'TX-102 (Spinning Department)',
            ),
            _buildActivityTimelineItem(
              time: '10:25',
              dotColor: TexoraColors.successText,
              title: 'Maintenance ticket created',
              subtitle: 'MT-458 • Rieter Ring Frame bearing check',
            ),
            _buildActivityTimelineItem(
              time: '10:26',
              dotColor: TexoraColors.primaryBlue,
              title: 'Checking production impact',
              subtitle: 'Production Agent evaluating buffer delay',
            ),
            _buildActivityTimelineItem(
              time: '10:27',
              dotColor: TexoraColors.purple,
              title: 'Inventory verified',
              subtitle: 'Required bearing 6205 available in store',
            ),
            _buildActivityTimelineItem(
              time: '10:28',
              dotColor: TexoraColors.warningText,
              title: 'Waiting for manager approval',
              subtitle: 'Recovery Case #54 • Hybrid strategy recommended',
              isLast: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityTimelineItem({
    required String time,
    required Color dotColor,
    required String title,
    required String subtitle,
    bool isLast = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: TexoraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: TexoraColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: TexoraColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutonomousConsoleCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildQuickActionBar(),
          const SizedBox(height: 16),
          _buildAutonomousOperationsPanel(),
          const SizedBox(height: 20),
          _buildOperationalKpiRow(),
          const SizedBox(height: 24),
          _buildDepartmentSection(),
          const SizedBox(height: 24),
          _buildCriticalIncidentsCard(),
          const SizedBox(height: 20),
          _buildEnergyAndProductionCard(),
          const SizedBox(height: 20),
          AiActivityCenterWidget(
            executions: _executions,
            incidents: _incidents,
            recoveryCases: _recoveryCases,
            onNavigate: (route, params) {},
          ),
        ],
      ),
    );
  }


  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;
          final titleSection = Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withAlpha(35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryBlueLight.withAlpha(120)),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: AppColors.primaryBlueLight,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        const Text(
                          'Executive Factory Command Center',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF059669)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hub_rounded, color: Color(0xFF34D399), size: 12),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'AUTONOMOUS FACTORY INTELLIGENCE',
                                  style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Autonomous multi-agent orchestration, digital twin What-If simulation, and human-in-the-loop recovery intelligence',
                      style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );

          final syncSection = FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Synced: ${_lastRefreshTime.hour.toString().padLeft(2, '0')}:${_lastRefreshTime.minute.toString().padLeft(2, '0')}:${_lastRefreshTime.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => _loadAllDashboardData(silent: false),
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 20),
                  tooltip: 'Refresh Executive Data',
                ),
              ],
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleSection,
                const SizedBox(height: 12),
                syncSection,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleSection),
              const SizedBox(width: 16),
              syncSection,
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickActionBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text(
            'DIRECT ACCESS:',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          _buildQuickActionButton(
            label: 'Production Intelligence',
            icon: Icons.factory_rounded,
            color: const Color(0xFF38BDF8),
            onTap: () => widget.onNavigate(10),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'AI Agent Operations',
            icon: Icons.hub_rounded,
            color: const Color(0xFF38BDF8),
            onTap: () => widget.onNavigate(8),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Incident Intelligence',
            icon: Icons.insights_rounded,
            color: AppColors.errorRed,
            onTap: () => widget.onNavigate(2),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Factory Digital Twin',
            icon: Icons.grid_view_rounded,
            color: const Color(0xFF38BDF8),
            onTap: () => widget.onNavigate(1),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Approval Center',
            icon: Icons.gavel_rounded,
            color: const Color(0xFFF59E0B),
            onTap: () => widget.onNavigate(5),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Factory Recovery',
            icon: Icons.build_circle_rounded,
            color: const Color(0xFF0D9488),
            onTap: () => widget.onNavigate(4),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Machine Health AI',
            icon: Icons.psychology_rounded,
            color: AppColors.accentPurple,
            onTap: () => widget.onNavigate(3),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Audit Trail',
            icon: Icons.shield_outlined,
            color: const Color(0xFF10B981),
            onTap: () => widget.onNavigate(6),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'Maintenance Execution',
            icon: Icons.handyman_rounded,
            color: const Color(0xFFEA580C),
            onTap: () => widget.onNavigate(7),
          ),
          const SizedBox(width: 8),
          _buildQuickActionButton(
            label: 'System Diagnostics',
            icon: Icons.monitor_heart_rounded,
            color: AppColors.successGreen,
            onTap: () => widget.onNavigate(9),
          ),
        ],
      ),
    );
  }

  Widget _buildAutonomousOperationsPanel() {
    final workerStatus = _autonomousStatus['orchestrator_worker'] ?? 'ACTIVE';
    final activeWorkflows = _autonomousStatus['active_workflows_count'] ?? 0;
    final pendingApprovals = _autonomousStatus['pending_approvals_count'] ?? 0;
    final latestRun = (_autonomousRuns.isNotEmpty) ? _autonomousRuns.first as Map<String, dynamic> : null;
    final activeCase = _recoveryCases.isNotEmpty ? _recoveryCases.first as Map<String, dynamic> : null;

    int? activeIncidentId;
    if (latestRun != null && latestRun['incident_id'] != null) {
      activeIncidentId = latestRun['incident_id'] is int
          ? latestRun['incident_id'] as int
          : int.tryParse(latestRun['incident_id'].toString());
    } else if (_incidents.isNotEmpty) {
      final firstInc = _incidents.first;
      if (firstInc is Map<String, dynamic> && firstInc['id'] != null) {
        activeIncidentId = firstInc['id'] is int
            ? firstInc['id'] as int
            : int.tryParse(firstInc['id'].toString());
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2563EB).withAlpha(120), width: 1.5),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF131C38)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, panelConstraints) {
          final maxTextWidth = (panelConstraints.maxWidth - 60).clamp(50.0, 580.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Wrap: Title, Worker Status, and Autonomous Trigger
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 10,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100)),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Color(0xFF38BDF8), size: 20),
                      ),
                      const SizedBox(width: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxTextWidth),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Autonomous Factory Agent Orchestrator',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Continuous closed loop: Anomaly Detection ➔ Gemini Root Cause ➔ Multi-Agent Coordination ➔ Digital Twin Simulation ➔ Manager Gate ➔ Verification',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _isExecutingPipeline ? null : _dispatchAutonomousPipeline,
                icon: _isExecutingPipeline
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_circle_fill_rounded, size: 16),
                label: Text(_isExecutingPipeline ? 'EXECUTING PIPELINE...' : 'DISPATCH AUTONOMOUS PIPELINE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Feedback Bar if any
          if (_actionFeedback != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _actionFeedback!,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _actionFeedback = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 4 Status Pills
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildStatusPill('ORCHESTRATOR WORKER', workerStatus, const Color(0xFF34D399)),
              _buildStatusPill('ANOMALY DETECTOR', 'ONLINE (MONITORING)', const Color(0xFF38BDF8)),
              _buildStatusPill('ACTIVE WORKFLOWS', '$activeWorkflows In Progress', const Color(0xFFA855F7)),
              _buildStatusPill('MANAGER APPROVALS', '$pendingApprovals Pending', pendingApprovals > 0 ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)),
            ],
          ),

          // Live Autonomous 12-Stage Workflow Pipeline (Compact Monitor)
          if (activeIncidentId != null) ...[
            const SizedBox(height: 14),
            AutonomousWorkflowMonitor(
              key: ValueKey('ecc_mon_$activeIncidentId'),
              incidentId: activeIncidentId,
              isCompact: true,
              onNavigateToApprovals: () => widget.onNavigate(5),
              onNavigateToRecovery: () => widget.onNavigate(4),
            ),
          ],

          // Active/Latest Workflow Inspector Card
          if (latestRun != null || activeCase != null) ...[
            const SizedBox(height: 14),
            _buildWorkflowInspector(latestRun: latestRun, activeCase: activeCase),
          ],
        ],
      );
    },
  ),
);
  }

  Widget _buildStatusPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('$label: ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
            Flexible(
              child: Text(
                value,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkflowInspector({Map<String, dynamic>? latestRun, Map<String, dynamic>? activeCase}) {
    final stage = latestRun?['current_stage'] ?? activeCase?['autonomous_stage'] ?? 'AWAITING_MANAGER_APPROVAL';
    final machineCode = latestRun?['machine_code'] ?? activeCase?['machine_code'] ?? 'WEV-RAP-01';
    final recommendedStrategy = latestRun?['recommended_strategy'] ?? activeCase?['recommended_strategy'] ?? 'HYBRID_RECOVERY';
    final recCaseId = latestRun?['recovery_case_id'] ?? activeCase?['id'] ?? 1;
    final approvalId = activeCase?['approval_requests'] is List && (activeCase?['approval_requests'] as List).isNotEmpty
        ? (activeCase?['approval_requests'] as List).first['id'] as int?
        : null;

    final isAwaitingApproval = stage == 'AWAITING_MANAGER_APPROVAL';
    final isAwaitingVerification = stage == 'AWAITING_VERIFICATION' || stage == 'RECOVERY_COORDINATION';
    final isVerified = stage == 'VERIFIED_RECOVERED';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141E33),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withAlpha(40),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF38BDF8).withAlpha(120)),
                    ),
                    child: Text(
                      'ACTIVE WORKFLOW • MACHINE $machineCode',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Stage: $stage',
                    style: TextStyle(
                      color: isAwaitingApproval ? const Color(0xFFF59E0B) : isVerified ? const Color(0xFF34D399) : const Color(0xFF38BDF8),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                'Case #$recCaseId',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Strategy details & Manager Actions
          if (isAwaitingApproval) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, color: Color(0xFFF59E0B), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manager Decision Gate: AI & Digital Twin Recommends "$recommendedStrategy"',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Multi-agent consensus + What-If simulation ranked Strategy C highest for minimal loss and downtime.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isActionInProgress
                        ? null
                        : () => _handleManagerDecision(
                              recoveryCaseId: recCaseId,
                              approvalId: approvalId,
                              action: 'APPROVE',
                              strategy: recommendedStrategy,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: const Text('APPROVE STRATEGY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _isActionInProgress
                        ? null
                        : () => _handleManagerDecision(
                              recoveryCaseId: recCaseId,
                              approvalId: approvalId,
                              action: 'REQUEST_REVISION',
                            ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF59E0B),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: const Text('REQUEST REVISION', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ] else if (isAwaitingVerification) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withAlpha(100)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.engineering_rounded, color: Color(0xFF38BDF8), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Awaiting Physical Repair Verification',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Maintenance work order active. Verification requires technician sign-off and fresh telemetry <180s.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isActionInProgress ? null : () => _handleTechnicianVerification(recCaseId),
                    icon: const Icon(Icons.verified_rounded, size: 14),
                    label: const Text('SIMULATE TECHNICIAN REPAIR & VERIFY', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isVerified) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF064E3B).withAlpha(60),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF059669)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 18),
                  SizedBox(width: 10),
                  Text(
                    'Recovery Complete: Physical maintenance verified and vibration normalized.',
                    style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(120)),
        backgroundColor: color.withAlpha(15),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildOperationalKpiRow() {
    final stateDistribution = _snapshot?.operationalSummary['state_distribution'] as Map<String, dynamic>? ?? {};
    final total = _snapshot?.totalMachines ?? 25;
    final running = (stateDistribution['RUNNING'] as num?)?.toInt() ?? 0;
    final warning = (stateDistribution['WARNING'] as num?)?.toInt() ?? 0;
    final critical = (stateDistribution['CRITICAL'] as num?)?.toInt() ?? 0;
    final stale = (stateDistribution['UNKNOWN'] as num?)?.toInt() ?? 0;
    final pendingApprovals = _recoverySummary['pending_approvals_total'] ?? 0;
    final activeCases = _recoverySummary['active_cases_total'] ?? _recoveryCases.length;

    final cards = [
      IndustrialMetricCard(
        title: 'Fleet Operational Status',
        value: '$running / $total',
        subtitle: '$critical Critical | $warning Warning',
        sourceProvenance: '25 Machines',
        icon: Icons.precision_manufacturing_rounded,
        accentColor: critical > 0 ? AppColors.errorRed : AppColors.successGreen,
        onTap: () => widget.onNavigate(3),
      ),
      IndustrialMetricCard(
        title: 'Telemetry Stream Status',
        value: stale > 0 ? '$stale Stale' : 'All Fresh',
        subtitle: stale > 0 ? 'Simulator Paused (>180s)' : 'Active Telemetry Stream',
        sourceProvenance: '180s Threshold',
        icon: Icons.sensors_rounded,
        accentColor: stale > 0 ? const Color(0xFF94A3B8) : AppColors.successGreen,
        onTap: () => widget.onNavigate(1),
      ),
      IndustrialMetricCard(
        title: 'Active Factory Incidents',
        value: '${_incidents.length}',
        subtitle: '${_incidents.where((i) => i['severity'] == 'CRITICAL').length} Critical Priority',
        sourceProvenance: 'Anomaly Engine',
        icon: Icons.warning_amber_rounded,
        accentColor: _incidents.isNotEmpty ? AppColors.warningOrange : AppColors.successGreen,
        onTap: () => widget.onNavigate(2),
      ),
      IndustrialMetricCard(
        title: 'Active Recovery Cases',
        value: '$activeCases',
        subtitle: '$pendingApprovals Awaiting Approval',
        sourceProvenance: 'Orchestrator',
        icon: Icons.build_circle_rounded,
        accentColor: pendingApprovals > 0 ? const Color(0xFF38BDF8) : const Color(0xFF0D9488),
        onTap: () => widget.onNavigate(5),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        const double spacing = 12.0;

        final int columns;
        if (availableWidth >= 1000) {
          columns = 4;
        } else if (availableWidth >= 520) {
          columns = 2;
        } else {
          columns = 1;
        }

        final cardWidth = (availableWidth - ((columns - 1) * spacing)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((card) => SizedBox(width: cardWidth, child: card)).toList(),
        );
      },
    );
  }

  Widget _buildDepartmentSection() {
    final deptSummaries = _snapshot?.operationalSummary['department_summaries'] as Map<String, dynamic>? ?? {};

    final departmentMeta = {
      'SPN': {'name': 'Spinning Department', 'unit': 'kg/h', 'loc': 'Bay 1 — Ring Spinning Mill'},
      'WEV': {'name': 'Weaving Shed', 'unit': 'meters/h', 'loc': 'Bay 2 — High Speed Looms'},
      'KNT': {'name': 'Knitting Division', 'unit': 'kg/h', 'loc': 'Bay 3 — Circular Knitting'},
      'DYE': {'name': 'Dyeing & Chemical', 'unit': 'kg/h', 'loc': 'Bay 4 — Soft Flow Vessels'},
      'FIN': {'name': 'Finishing & Inspection', 'unit': 'meters/h', 'loc': 'Bay 5 — Stenter & Pack'},
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IndustrialSectionHeader(
          title: 'Five-Department Performance Matrix',
          subtitle: 'Live rated capacity, operational status distribution, and active work orders',
          icon: Icons.account_tree_rounded,
          action: TextButton.icon(
            onPressed: () => widget.onNavigate(3),
            icon: const Icon(Icons.arrow_forward_rounded, size: 14),
            label: const Text('Open Digital Twin'),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            const double spacing = 12.0;

            final int columns;
            if (availableWidth >= 1150) {
              columns = 5;
            } else if (availableWidth >= 740) {
              columns = 3;
            } else if (availableWidth >= 480) {
              columns = 2;
            } else {
              columns = 1;
            }

            final cardWidth = (availableWidth - ((columns - 1) * spacing)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: departmentMeta.entries.map((entry) {
                final code = entry.key;
                final meta = entry.value;
                final dSummary = deptSummaries[code] as Map<String, dynamic>? ?? {};

                return SizedBox(
                  width: cardWidth,
                  child: DepartmentStatusCard(
                    departmentCode: code,
                    departmentName: meta['name']!,
                    floorLocation: meta['loc']!,
                    totalMachines: (dSummary['total_machines'] as num?)?.toInt() ?? 0,
                    stateCounts: dSummary['state_counts'] as Map<String, dynamic>? ?? {},
                    ratedCapacity: (dSummary['rated_capacity_total'] as num?)?.toDouble() ?? 0.0,
                    unit: meta['unit']!,
                    activeIncidentsCount: (dSummary['active_incidents_count'] as num?)?.toInt() ?? 0,
                    onTap: () => widget.onNavigate(3),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCriticalIncidentsCard() {
    final criticalIncidents = _incidents.where((i) => i['severity'] == 'CRITICAL').toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.warning_amber_rounded, color: AppColors.errorRed, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Active Critical Incidents',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${criticalIncidents.length} Critical',
                  style: const TextStyle(color: AppColors.errorRed, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (criticalIncidents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('No active critical incidents. Plant operating normally.', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: criticalIncidents.length.clamp(0, 4),
              separatorBuilder: (context, index) => const Divider(color: Color(0xFF1E293B), height: 12),
              itemBuilder: (context, idx) {
                final inc = criticalIncidents[idx];
                final code = inc['incident_code'] ?? 'INC-001';
                final machine = inc['machine_code'] ?? inc['machine']?.toString() ?? 'WEV-AJ-02';
                final summary = inc['summary'] ?? 'Sensor threshold excursion';
                final detectedAt = inc['detected_at']?.toString().split('T').first ?? 'Recent';

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        machine,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$code: $summary',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Detected: $detectedAt | Escalated to Machine Health Specialist',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEnergyAndProductionCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Factory Power & Operations Footprint',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Text('SIMULATED DATABASE METRICS', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Builder(
            builder: (context) {
              final machines = _snapshot?.machineStates ?? [];
              double livePowerKw = 0.0;
              for (final m in machines) {
                final kw = (m.latestTelemetry?['power_consumption_kw'] as num?)?.toDouble();
                if (kw != null && kw > 0) {
                  livePowerKw += kw;
                }
              }
              final powerDisplay = livePowerKw > 0
                  ? '${livePowerKw.toStringAsFixed(1)} kW'
                  : '485.2 kW';

              final assignedCount = machines.where((m) => m.productionAssignment != null).length;
              final activeJobsDisplay = assignedCount > 0
                  ? '$assignedCount Active Batches'
                  : '${_recoveryCases.isNotEmpty ? _recoveryCases.length : 5} Active Batches';

              return Row(
                children: [
                  Expanded(
                    child: _buildFootprintMetric('Simulated Power Load', powerDisplay, Icons.electric_meter_rounded, const Color(0xFFF59E0B)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFootprintMetric('Active Work Orders', activeJobsDisplay, Icons.inventory_2_rounded, const Color(0xFF38BDF8)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFootprintMetric('Warehousing SKUs', '11 Stocked SKUs', Icons.warehouse_rounded, const Color(0xFF10B981)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFootprintMetric(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _DepartmentNodeData {
  final String code;
  final String name;
  final int machineCount;
  final int runningPct;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _DepartmentNodeData({
    required this.code,
    required this.name,
    required this.machineCount,
    required this.runningPct,
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}
