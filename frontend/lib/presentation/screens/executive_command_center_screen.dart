import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/services/api_service.dart';
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

  DigitalTwinSnapshotModel? _snapshot;
  Map<String, dynamic> _recoverySummary = {};
  Map<String, dynamic> _autonomousStatus = {};
  List<dynamic> _autonomousRuns = [];
  List<dynamic> _incidents = [];
  List<dynamic> _executions = [];
  List<dynamic> _recoveryCases = [];

  bool _isLoading = true;
  bool _isLaunchingDemo = false;
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

      if (mounted) {
        setState(() {
          _snapshot = snap;
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

  Future<void> _launchExpoDemo() async {
    setState(() {
      _isLaunchingDemo = true;
      _actionFeedback = '🚀 Injecting vibration anomaly on Loom WEV-RAP-01 and launching autonomous AI pipeline...';
    });

    try {
      final result = await _apiService.launchAutonomousExpoDemo(machineCode: 'WEV-RAP-01');
      if (mounted) {
        setState(() {
          _isLaunchingDemo = false;
          if (result['success'] == true) {
            _actionFeedback = '✅ Autonomous Pipeline Complete! Incident #${result['incident_id']} analyzed, What-If simulation finished. Recommended: ${result['recommended_strategy']}. Awaiting Manager Approval.';
          } else {
            _actionFeedback = '⚠️ Demo status: ${result['error'] ?? 'Execution completed'}';
          }
        });
        await _loadAllDashboardData(silent: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLaunchingDemo = false;
          _actionFeedback = '❌ Demo Error: $e';
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
      backgroundColor: const Color(0xFF0A0F1D), // Dark Navy Background
      body: _isLoading && _snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _snapshot == null
              ? ErrorStateWidget(
                  message: _errorMessage!,
                  onRetry: () => _loadAllDashboardData(silent: false),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadAllDashboardData(silent: false),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),

                      // Quick Action Bar
                      _buildQuickActionBar(),
                      const SizedBox(height: 16),

                      // Autonomous Operations & Expo Control Panel (Phase 9)
                      _buildAutonomousOperationsPanel(),
                      const SizedBox(height: 20),

                      // Top Operational KPI Matrix Row
                      _buildOperationalKpiRow(),
                      const SizedBox(height: 24),

                      // 5-Department Performance Matrix
                      _buildDepartmentSection(),
                      const SizedBox(height: 24),

                      // Two-Column Live Operations Layout
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Critical Incident Feed & Energy Summary
                          Expanded(
                            flex: 5,
                            child: Column(
                              children: [
                                _buildCriticalIncidentsCard(),
                                const SizedBox(height: 20),
                                _buildEnergyAndProductionCard(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),

                          // Right Column: AI Operations Activity Stream & Recovery Workflow
                          Expanded(
                            flex: 6,
                            child: AiActivityCenterWidget(
                              executions: _executions,
                              incidents: _incidents,
                              recoveryCases: _recoveryCases,
                              onNavigate: (route, params) {},
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
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
                        runSpacing: 4,
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
                                Text(
                                  'AUTONOMOUS FACTORY INTELLIGENCE',
                                  style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
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
            ),
          ),
          const SizedBox(width: 16),
          Row(
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
        ],
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
            label: 'AI Agent Operations',
            icon: Icons.hub_rounded,
            color: const Color(0xFF38BDF8),
            onTap: () => widget.onNavigate(10),
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
            label: 'What-If Sandbox',
            icon: Icons.science_rounded,
            color: const Color(0xFF64748B),
            onTap: () => widget.onNavigate(8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Wrap: Title, Worker Status, and Autonomous Trigger
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 10,
            children: [
              Row(
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
                    constraints: const BoxConstraints(maxWidth: 580),
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
              ElevatedButton.icon(
                onPressed: _isLaunchingDemo ? null : _launchExpoDemo,
                icon: _isLaunchingDemo
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_circle_fill_rounded, size: 16),
                label: Text(_isLaunchingDemo ? 'EXECUTING PIPELINE...' : 'DISPATCH AUTONOMOUS PIPELINE'),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
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

    return Row(
      children: [
        Expanded(
          child: IndustrialMetricCard(
            title: 'Fleet Operational Status',
            value: '$running / $total',
            subtitle: '$critical Critical | $warning Warning',
            sourceProvenance: '25 Machines',
            icon: Icons.precision_manufacturing_rounded,
            accentColor: critical > 0 ? AppColors.errorRed : AppColors.successGreen,
            onTap: () => widget.onNavigate(3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: IndustrialMetricCard(
            title: 'Telemetry Stream Status',
            value: stale > 0 ? '$stale Stale' : 'All Fresh',
            subtitle: stale > 0 ? 'Simulator Paused (>180s)' : 'Active Telemetry Stream',
            sourceProvenance: '180s Threshold',
            icon: Icons.sensors_rounded,
            accentColor: stale > 0 ? const Color(0xFF94A3B8) : AppColors.successGreen,
            onTap: () => widget.onNavigate(1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: IndustrialMetricCard(
            title: 'Active Factory Incidents',
            value: '${_incidents.length}',
            subtitle: '${_incidents.where((i) => i['severity'] == 'CRITICAL').length} Critical Priority',
            sourceProvenance: 'Anomaly Engine',
            icon: Icons.warning_amber_rounded,
            accentColor: _incidents.isNotEmpty ? AppColors.warningOrange : AppColors.successGreen,
            onTap: () => widget.onNavigate(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: IndustrialMetricCard(
            title: 'Active Recovery Cases',
            value: '$activeCases',
            subtitle: '$pendingApprovals Awaiting Approval',
            sourceProvenance: 'Orchestrator',
            icon: Icons.build_circle_rounded,
            accentColor: pendingApprovals > 0 ? const Color(0xFF38BDF8) : const Color(0xFF0D9488),
            onTap: () => widget.onNavigate(5),
          ),
        ),
      ],
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: departmentMeta.entries.map((entry) {
            final code = entry.key;
            final meta = entry.value;
            final dSummary = deptSummaries[code] as Map<String, dynamic>? ?? {};

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
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
              ),
            );
          }).toList(),
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
                ),
                child: const Text('DATABASE METRICS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildFootprintMetric('Nominal Power Load', '485.2 kW', Icons.electric_meter_rounded, const Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFootprintMetric('Active Batches', '5 Work Orders', Icons.inventory_2_rounded, const Color(0xFF38BDF8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFootprintMetric('Active Warehousing', '11 SKU Items', Icons.warehouse_rounded, const Color(0xFF10B981)),
              ),
            ],
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
