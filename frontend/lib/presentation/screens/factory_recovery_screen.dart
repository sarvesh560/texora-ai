import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_service.dart';
import '../../data/models/recovery_models.dart';
import '../widgets/status_badge.dart';
import '../widgets/metric_card.dart';

class FactoryRecoveryScreen extends StatefulWidget {
  const FactoryRecoveryScreen({super.key});

  @override
  State<FactoryRecoveryScreen> createState() => _FactoryRecoveryScreenState();
}

class _FactoryRecoveryScreenState extends State<FactoryRecoveryScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  bool _isLoading = true;
  String _errorMessage = '';
  RecoverySummaryModel? _summary;
  List<RecoveryCaseModel> _cases = [];
  RecoveryCaseModel? _selectedCase;
  String _filterStatus = 'ALL';

  // Manager Approval Inputs
  String _selectedRole = 'MAINTENANCE_MANAGER';
  final TextEditingController _managerNameController =
      TextEditingController(text: 'K. Sundaram (Maintenance Lead)');
  final TextEditingController _notesController =
      TextEditingController(text: 'Approved for immediate technical intervention');

  final List<String> _managerRoles = [
    'MAINTENANCE_MANAGER',
    'PRODUCTION_MANAGER',
    'WAREHOUSE_MANAGER',
    'PLANT_DIRECTOR',
    'OPERATOR',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadRecoveryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _managerNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecoveryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final summary = await _apiService.getRecoverySummary();
      final cases = await _apiService.getRecoveryCases();

      setState(() {
        _summary = summary;
        _cases = cases;
        if (_cases.isNotEmpty) {
          _selectedCase = _cases.first;
        } else {
          _selectedCase = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load recovery telemetry: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectCase(int id) async {
    try {
      final fullCase = await _apiService.getRecoveryCaseDetail(id);
      if (!mounted) return;
      setState(() {
        _selectedCase = fullCase;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load case #$id details: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  Future<void> _handleApprove(int approvalId) async {
    try {
      final res = await _apiService.approveAction(
        approvalId,
        _selectedRole,
        _managerNameController.text.trim(),
        _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action Authorized: ${res['message'] ?? 'Successfully executed'}'),
          backgroundColor: AppColors.successGreen,
        ),
      );

      // Refresh recovery case
      if (_selectedCase != null) {
        await _selectCase(_selectedCase!.id);
      }
      final summary = await _apiService.getRecoverySummary();
      final cases = await _apiService.getRecoveryCases();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _cases = cases;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approval Execution Failed: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  Future<void> _handleReject(int approvalId) async {
    try {
      final res = await _apiService.rejectAction(
        approvalId,
        _selectedRole,
        _managerNameController.text.trim(),
        'Rejected by manager review',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action Rejected: ${res['message'] ?? 'Status updated to REJECTED'}'),
          backgroundColor: AppColors.warningOrange,
        ),
      );

      if (_selectedCase != null) {
        await _selectCase(_selectedCase!.id);
      }
      final summary = await _apiService.getRecoverySummary();
      final cases = await _apiService.getRecoveryCases();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _cases = cases;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rejection Failed: $e'), backgroundColor: AppColors.errorRed),
      );
    }
  }

  List<RecoveryCaseModel> get _filteredCases {
    if (_filterStatus == 'ALL') return _cases;
    return _cases.where((c) => c.status == _filterStatus).toList();
  }

  Widget _buildStatusBadge(String status) {
    BadgeType type = BadgeType.neutral;
    switch (status) {
      case 'COMPLETED':
      case 'RECOVERED':
      case 'APPROVED':
        type = BadgeType.success;
        break;
      case 'IN_RECOVERY':
      case 'IN_PROGRESS':
      case 'PENDING':
        type = BadgeType.info;
        break;
      case 'AWAITING_APPROVALS':
      case 'AWAITING_APPROVAL':
        type = BadgeType.warning;
        break;
      case 'FAILED':
      case 'REJECTED':
      case 'CRITICAL':
        type = BadgeType.error;
        break;
      default:
        type = BadgeType.neutral;
    }
    return StatusBadge(label: status.replaceAll('_', ' '), type: type);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primaryBlue),
              SizedBox(height: 16),
              Text(
                'Correlating Multi-Agent Recovery Plans...',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage, style: const TextStyle(color: Colors.white, fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                onPressed: _loadRecoveryData,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Retry Connection', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          // Top Bar
          _buildTopBar(),

          // KPI Metric Bar
          if (_summary != null) _buildKpiRow(),

          // Main Multi-Pane Content
          Expanded(
            child: Row(
              children: [
                // Left: Recovery Cases List Pane (360px)
                Container(
                  width: 360,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    border: Border(right: BorderSide(color: Color(0xFF1E293B))),
                  ),
                  child: _buildCasesListPane(),
                ),

                // Right: Case Detail & Multi-Agent Tabs
                Expanded(
                  child: _selectedCase == null
                      ? const Center(
                          child: Text(
                            'Select a recovery case to view coordinated action plans and RBAC gates',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                          ),
                        )
                      : _buildCaseDetailPane(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.cardBackgroundDark,
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentPurple.withAlpha(51),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.build_circle_rounded, color: AppColors.accentPurple, size: 24),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Factory Recovery Command Center',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Multi-Agent Maintenance, Inventory & Production Recovery Coordination',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
                tooltip: 'Refresh Recovery Cases',
                onPressed: _loadRecoveryData,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Live Coordination Drill', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Triggering Multi-Agent Recovery Drill for active incidents...'),
                      backgroundColor: AppColors.primaryBlue,
                    ),
                  );
                  await _apiService.orchestrateRecovery(1, forceReanalyze: true);
                  _loadRecoveryData();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow() {
    final m = _summary!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: MetricCard(
              title: 'Active Recovery Cases',
              value: '${m.activeCases}',
              icon: Icons.sync_problem_rounded,
              accentColor: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Critical Priority',
              value: '${m.criticalCases}',
              icon: Icons.warning_amber_rounded,
              accentColor: AppColors.errorRed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Awaiting Approvals',
              value: '${m.pendingApprovalsTotal}',
              icon: Icons.gavel_rounded,
              accentColor: Colors.amber,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Reserved Spares',
              value: '${m.reservedSparesCount}',
              icon: Icons.inventory_2_rounded,
              accentColor: AppColors.accentPurple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Recovered Cases',
              value: '${m.recoveredCases}',
              icon: Icons.check_circle_rounded,
              accentColor: AppColors.successGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCasesListPane() {
    return Column(
      children: [
        // Filter Chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All Cases'),
                const SizedBox(width: 6),
                _buildFilterChip('AWAITING_APPROVALS', 'Pending Approval'),
                const SizedBox(width: 6),
                _buildFilterChip('IN_RECOVERY', 'In Recovery'),
                const SizedBox(width: 6),
                _buildFilterChip('RECOVERED', 'Recovered'),
              ],
            ),
          ),
        ),

        const Divider(height: 1, color: Color(0xFF1E293B)),

        // Case Cards List
        Expanded(
          child: _filteredCases.isEmpty
              ? const Center(
                  child: Text(
                    'No recovery cases found',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _filteredCases.length,
                  itemBuilder: (context, index) {
                    final item = _filteredCases[index];
                    final isSelected = _selectedCase?.id == item.id;

                    return GestureDetector(
                      onTap: () => _selectCase(item.id),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1E293B) : AppColors.cardBackgroundDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? AppColors.primaryBlue : const Color(0xFF334155),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item.caseCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                _buildStatusBadge(item.status),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.precision_manufacturing_rounded, size: 14, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 6),
                                Text(
                                  '${item.machineCode} — ${item.departmentName}',
                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: item.priority == 'CRITICAL'
                                        ? AppColors.errorRed.withAlpha(51)
                                        : AppColors.primaryBlue.withAlpha(51),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${item.priorityScore.toStringAsFixed(0)}% Priority',
                                    style: TextStyle(
                                      color: item.priority == 'CRITICAL' ? AppColors.errorRed : AppColors.primaryBlue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (item.pendingApprovalsCount > 0)
                                  Row(
                                    children: [
                                      const Icon(Icons.gavel_rounded, size: 12, color: Colors.amber),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${item.pendingApprovalsCount} Approval Gate(s)',
                                        style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String statusKey, String label) {
    final isSelected = _filterStatus == statusKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : const Color(0xFF94A3B8))),
      selected: isSelected,
      selectedColor: AppColors.primaryBlue,
      backgroundColor: const Color(0xFF1E293B),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _filterStatus = statusKey;
          });
        }
      },
    );
  }

  Widget _buildCaseDetailPane() {
    final c = _selectedCase!;

    return Column(
      children: [
        // Case Header Banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withAlpha(51),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primaryBlue.withAlpha(102)),
                        ),
                        child: Text(
                          c.caseCode,
                          style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${c.machineCode} (${c.machineName})',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  _buildStatusBadge(c.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                c.incidentSummary.isNotEmpty ? c.incidentSummary : c.summary,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildHeaderBadge(Icons.timer_outlined, 'Est. Repair: ${c.estimatedDowntimeHours}h'),
                  const SizedBox(width: 10),
                  _buildHeaderBadge(Icons.flag_outlined, 'Target SLA: ${c.targetResolutionHours}h'),
                  const SizedBox(width: 10),
                  _buildHeaderBadge(Icons.speed_rounded, 'Priority: ${c.priority} (${c.priorityScore.toStringAsFixed(0)}%)'),
                ],
              ),
            ],
          ),
        ),

        // Tabs Header
        Container(
          color: AppColors.cardBackgroundDark,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primaryBlue,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF94A3B8),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.timeline_rounded, size: 16), text: 'Recovery Plan Timeline'),
              Tab(icon: Icon(Icons.hub_rounded, size: 16), text: 'Multi-Agent Evidence'),
              Tab(icon: Icon(Icons.gavel_rounded, size: 16), text: 'Manager Approvals (RBAC)'),
            ],
          ),
        ),

        // Tab Content Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTimelineTab(c),
              _buildEvidenceTab(c),
              _buildApprovalsTab(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTimelineTab(RecoveryCaseModel c) {
    if (c.steps.isEmpty) {
      return const Center(
        child: Text('No recovery steps registered in plan.', style: TextStyle(color: Color(0xFF64748B))),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: c.steps.length,
      itemBuilder: (context, index) {
        final step = c.steps[index];
        final isCompleted = step.status == 'COMPLETED';
        final isAwaiting = step.status == 'AWAITING_APPROVAL';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step Number & Line
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.successGreen
                        : (isAwaiting ? Colors.amber : const Color(0xFF334155)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : Text(
                            '${step.stepOrder}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                if (index < c.steps.length - 1)
                  Container(
                    width: 2,
                    height: 90,
                    color: const Color(0xFF334155),
                  ),
              ],
            ),

            const SizedBox(width: 16),

            // Step Content Card
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackgroundDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isAwaiting ? Colors.amber.withAlpha(128) : const Color(0xFF334155),
                  ),
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getAgentColor(step.agentType).withAlpha(51),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                step.agentType,
                                style: TextStyle(
                                  color: _getAgentColor(step.agentType),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              step.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        _buildStatusBadge(step.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      step.description,
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (step.dependencies.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Prerequisites: Step ${step.dependencies.join(', ')}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                            ),
                          ),
                        const Spacer(),
                        if (step.approvalCode != null)
                          Text(
                            'Gate: ${step.approvalCode} (${step.approvalStatus})',
                            style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEvidenceTab(RecoveryCaseModel c) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 1. Machine Health Specialist Evidence
        _buildEvidenceCard(
          title: 'Machine Health AI Diagnosis',
          agent: 'MACHINE_HEALTH',
          icon: Icons.psychology_rounded,
          content: [
            _buildEvidenceRow('Root Cause Hypothesis', c.healthDiagnosis['possible_root_causes'] != null && (c.healthDiagnosis['possible_root_causes'] as List).isNotEmpty ? (c.healthDiagnosis['possible_root_causes'][0]['hypothesis'] ?? 'Under investigation') : 'Bearing mechanical flaking'),
            _buildEvidenceRow('Confidence', '${c.healthDiagnosis['confidence_score'] ?? 85.0}%'),
            _buildEvidenceRow('Assessed Severity', c.healthDiagnosis['severity_assessment'] ?? c.incidentSeverity),
          ],
        ),

        const SizedBox(height: 16),

        // 2. Maintenance Coordinator Evidence
        _buildEvidenceCard(
          title: 'Maintenance Work Order Plan',
          agent: 'MAINTENANCE',
          icon: Icons.build_rounded,
          content: [
            _buildEvidenceRow('Proposed Work Order', c.maintenanceRecommendation['proposed_ticket']?['title'] ?? 'Loom Drive Bearing Inspection'),
            _buildEvidenceRow('Assigned Unit', c.maintenanceRecommendation['assigned_technician'] ?? 'Fast Response Mechanical Team'),
            _buildEvidenceRow('Estimated Labor', '${c.maintenanceRecommendation['estimated_hours'] ?? 1.5} Hours'),
            _buildEvidenceRow('Inspection Protocols', '${(c.maintenanceRecommendation['inspection_steps'] as List?)?.length ?? 4} Systematic Steps'),
          ],
        ),

        const SizedBox(height: 16),

        // 3. Inventory Stock Verification
        _buildEvidenceCard(
          title: 'Warehouse Spare Part Assessment',
          agent: 'INVENTORY',
          icon: Icons.inventory_2_rounded,
          content: [
            _buildEvidenceRow('Parts Evaluated', '${(c.inventoryAssessment['evaluated_parts'] as List?)?.length ?? 1} Registered Items'),
            _buildEvidenceRow('Shortages Detected', '${c.inventoryAssessment['shortages_count'] ?? 0} Shortages'),
            _buildEvidenceRow('Safety Stock Bar', 'Enforced - Zero negative stock permitted'),
            if ((c.inventoryAssessment['proposed_actions'] as List?)?.isNotEmpty == true)
              _buildEvidenceRow('Warehouse Action', '${c.inventoryAssessment['proposed_actions'][0]['action_type']} (${c.inventoryAssessment['proposed_actions'][0]['status']})'),
          ],
        ),

        const SizedBox(height: 16),

        // 4. Production Impact & Rescheduling
        _buildEvidenceCard(
          title: 'Production Schedule & Batch Risk',
          agent: 'PRODUCTION_IMPACT',
          icon: Icons.precision_manufacturing_rounded,
          content: [
            _buildEvidenceRow('Active Batches', '${(c.productionImpactAssessment['active_batches'] as List?)?.length ?? 0} Batches Staged'),
            _buildEvidenceRow('Orders At Risk', '${(c.productionImpactAssessment['orders_at_risk'] as List?)?.length ?? 0} Customer Orders'),
            _buildEvidenceRow('Alternate Machines', '${(c.productionImpactAssessment['alternate_machines'] as List?)?.length ?? 1} Compatible Machines Available'),
          ],
        ),
      ],
    );
  }

  Widget _buildEvidenceCard({
    required String title,
    required String agent,
    required IconData icon,
    required List<Widget> content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackgroundDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _getAgentColor(agent), size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getAgentColor(agent).withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  agent,
                  style: TextStyle(color: _getAgentColor(agent), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFF1E293B)),
          const SizedBox(height: 12),
          ...content,
        ],
      ),
    );
  }

  Widget _buildEvidenceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalsTab(RecoveryCaseModel c) {
    final pendingSteps = c.steps.where((s) => s.approvalId != null && s.approvalStatus == 'PENDING').toList();
    final authorizedSteps = c.steps.where((s) => s.approvalId != null && s.approvalStatus != 'PENDING').toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Role & Manager Authorization Setup
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.security_rounded, color: AppColors.primaryBlue, size: 18),
                  SizedBox(width: 8),
                  Text('Manager Authorization & Role Context', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sign-Off Role (RBAC)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedRole,
                          dropdownColor: const Color(0xFF1E293B),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: AppColors.cardBackgroundDark,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          items: _managerRoles.map((role) {
                            return DropdownMenuItem(value: role, child: Text(role));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedRole = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Manager Identity / Name', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _managerNameController,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: AppColors.cardBackgroundDark,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'Pending Approval Gates (Action Required)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 10),

        if (pendingSteps.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBackgroundDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: AppColors.successGreen, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No pending manager approvals for this case. All required action gates are signed off.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          ...pendingSteps.map((step) {
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackgroundDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withAlpha(128)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Approval Gate: ${step.approvalCode ?? "APR-REQ"}',
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.errorRed.withAlpha(51),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('HIGH RISK GATE', style: TextStyle(color: AppColors.errorRed, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.description,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.errorRed,
                          side: const BorderSide(color: AppColors.errorRed),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Reject Action', style: TextStyle(fontSize: 12)),
                        onPressed: () => _handleReject(step.approvalId!),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: Text(
                          step.agentType == 'INVENTORY'
                              ? 'Authorize & Reserve Spare Parts'
                              : (step.agentType == 'MAINTENANCE'
                                  ? 'Authorize & Dispatch Work Order'
                                  : 'Authorize Action Execution'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _handleApprove(step.approvalId!),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

        if (authorizedSteps.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Authorized Action Gates & Audit Sign-Off History',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 10),
          ...authorizedSteps.map((step) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: AppColors.successGreen, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            step.approvalCode ?? 'APR-RECORD',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      _buildStatusBadge(step.approvalStatus ?? 'APPROVED'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.title,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (step.outputPayload.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Execution Output: ${step.outputPayload.toString()}',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Color _getAgentColor(String agentType) {
    switch (agentType) {
      case 'MACHINE_HEALTH':
        return AppColors.accentPurple;
      case 'MAINTENANCE':
        return AppColors.primaryBlue;
      case 'INVENTORY':
        return Colors.tealAccent;
      case 'PRODUCTION_IMPACT':
        return Colors.amber;
      default:
        return AppColors.primaryBlue;
    }
  }
}
