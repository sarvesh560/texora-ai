import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/ai_agent_model.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/services/api_service.dart';
import '../widgets/design_system/design_system.dart';
import 'digital_twin_screen.dart';

class MachineHealthAgentScreen extends StatefulWidget {
  final ApiService? apiService;

  const MachineHealthAgentScreen({super.key, this.apiService});

  @override
  State<MachineHealthAgentScreen> createState() => _MachineHealthAgentScreenState();
}

class _MachineHealthAgentScreenState extends State<MachineHealthAgentScreen> {
  late final ApiService _apiService;
  Timer? _pollingTimer;
  int _subViewMode = 0; // 0: Telemetry & Monitoring, 1: Factory Digital Twin & Topology

  bool _isLoading = true;
  String? _errorMessage;

  // Fleet & Snapshot data
  DigitalTwinSnapshotModel? _snapshot;
  List<MachineTwinModel> _machines = [];
  MachineTwinModel? _selectedMachine;
  List<Map<String, dynamic>> _selectedMachineTelemetry = [];
  bool _isLoadingTelemetry = false;
  String _activeTrendMetric = 'vibration';
  final Map<int, List<Map<String, dynamic>>> _machineTelemetryCache = {};

  // AI Agent Data
  AgentSummaryModel? _summary;
  List<ApprovalRequestModel> _approvals = [];
  int? _investigatingIncidentId;
  bool _isCycleRunning = false;

  // Filters & Search
  String _selectedStatusFilter = 'ALL';
  String _selectedDepartmentFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _fetchAllData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _fetchAllData(isBackground: true));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllData({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final snapFuture = _apiService.fetchDigitalTwinSnapshot(refresh: false);
      final summaryFuture = _apiService.fetchAgentSummary();
      final approvalsFuture = _apiService.fetchApprovals();

      final results = await Future.wait([snapFuture, summaryFuture, approvalsFuture]);
      final snap = results[0] as DigitalTwinSnapshotModel?;
      final summary = results[1] as AgentSummaryModel?;
      final approvals = results[2] as List<ApprovalRequestModel>? ?? [];

      if (mounted) {
        setState(() {
          _snapshot = snap;
          if (snap != null) {
            _machines = snap.machineStates;
          }
          _summary = summary;
          _approvals = approvals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !isBackground) {
        setState(() {
          _errorMessage = 'Failed to load machine health data: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectMachine(MachineTwinModel machine) async {
    final cached = _machineTelemetryCache[machine.id];
    setState(() {
      _selectedMachine = machine;
      _isLoadingTelemetry = cached == null;
      _selectedMachineTelemetry = cached ?? [];
    });

    try {
      final telemetry = await _apiService.fetchMachineTelemetry(machine.id);
      if (mounted) {
        setState(() {
          _selectedMachineTelemetry = telemetry;
          _machineTelemetryCache[machine.id] = telemetry;
          _isLoadingTelemetry = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingTelemetry = false;
        });
      }
    }
  }

  void _closeMachineDetail() {
    setState(() {
      _selectedMachine = null;
      _selectedMachineTelemetry = [];
    });
  }

  Future<void> _triggerInvestigation(int incidentId) async {
    setState(() => _investigatingIncidentId = incidentId);
    try {
      await _apiService.triggerInvestigation(incidentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Specialist investigation completed for incident #$incidentId.'),
            backgroundColor: TexoraColors.successText,
          ),
        );
        _fetchAllData(isBackground: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Investigation failed: $e'),
            backgroundColor: TexoraColors.criticalText,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _investigatingIncidentId = null);
      }
    }
  }

  Future<void> _runAgentCycle() async {
    setState(() => _isCycleRunning = true);
    try {
      final res = await _apiService.triggerAgentCycle();
      if (mounted) {
        final count = res['investigated_count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Autonomous AI cycle completed. Investigated $count incidents.'),
            backgroundColor: TexoraColors.successText,
          ),
        );
        _fetchAllData(isBackground: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cycle execution failed: $e'),
            backgroundColor: TexoraColors.criticalText,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCycleRunning = false);
      }
    }
  }

  Future<void> _handleApprove(int approvalId) async {
    final ok = await _apiService.approveRequest(
      approvalId,
      notes: 'Approved via Machine Health Specialist Console',
    );
    if (mounted && ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action approved. AI dispatching automated execution.'),
          backgroundColor: TexoraColors.successText,
        ),
      );
      _fetchAllData(isBackground: true);
    }
  }

  Future<void> _handleReject(int approvalId) async {
    final ok = await _apiService.rejectRequest(
      approvalId,
      notes: 'Rejected by operator in console',
    );
    if (mounted && ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action rejected. Incident status updated.'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      _fetchAllData(isBackground: true);
    }
  }

  List<MachineTwinModel> get _filteredMachines {
    return _machines.where((m) {
      final q = _searchQuery.toLowerCase();
      final code = m.code.toLowerCase();
      final name = m.name.toLowerCase();
      final dept = m.departmentName.toLowerCase();

      final matchesSearch = q.isEmpty || code.contains(q) || name.contains(q) || dept.contains(q);

      final state = m.twinPresentationState.toUpperCase();
      final rawStatus = m.rawStatus.toUpperCase();

      bool matchesStatus = true;
      if (_selectedStatusFilter != 'ALL') {
        if (_selectedStatusFilter == 'CRITICAL') {
          matchesStatus = state == 'CRITICAL' || rawStatus == 'CRITICAL';
        } else if (_selectedStatusFilter == 'WARNING') {
          matchesStatus = state == 'WARNING' || rawStatus == 'WARNING';
        } else if (_selectedStatusFilter == 'RUNNING' || _selectedStatusFilter == 'OPERATIONAL') {
          matchesStatus = state == 'RUNNING' || rawStatus == 'OPERATIONAL';
        } else if (_selectedStatusFilter == 'MAINTENANCE') {
          matchesStatus = state == 'UNDER_MAINTENANCE' || rawStatus == 'MAINTENANCE';
        } else if (_selectedStatusFilter == 'STALE') {
          matchesStatus = m.isStale;
        }
      }

      bool matchesDept = true;
      if (_selectedDepartmentFilter != 'ALL') {
        if (_selectedDepartmentFilter == 'SPINNING') {
          matchesDept = dept.contains('spin') || m.departmentCode == 'SPN';
        } else if (_selectedDepartmentFilter == 'WEAVING') {
          matchesDept = dept.contains('weav') || m.departmentCode == 'WEV';
        } else if (_selectedDepartmentFilter == 'KNITTING') {
          matchesDept = dept.contains('knit') || m.departmentCode == 'KNT';
        } else if (_selectedDepartmentFilter == 'DYEING') {
          matchesDept = dept.contains('dye') || m.departmentCode == 'DYE';
        } else if (_selectedDepartmentFilter == 'FINISHING') {
          matchesDept = dept.contains('finish') || m.departmentCode == 'FNS';
        }
      }

      return matchesSearch && matchesStatus && matchesDept;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _machines.isEmpty) {
      return const Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: Center(
          child: CircularProgressIndicator(color: TexoraColors.primaryBlue),
        ),
      );
    }

    if (_errorMessage != null && _machines.isEmpty) {
      return Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: TexoraColors.criticalText, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _fetchAllData(),
                style: ElevatedButton.styleFrom(backgroundColor: TexoraColors.primaryBlue),
                child: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    if (_subViewMode == 1) {
      return Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: const BoxDecoration(
                color: TexoraColors.cardBg,
                border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
              ),
              child: Row(
                children: [
                  _buildViewSelector(),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _subViewMode = 0),
                    icon: const Icon(Icons.arrow_back_rounded, size: 16, color: TexoraColors.primaryBlue),
                    label: const Text(
                      'Back to Fleet Telemetry',
                      style: TextStyle(color: TexoraColors.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: DigitalTwinScreen()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Monitoring Fleet Area
          Expanded(
            flex: _selectedMachine != null ? 6 : 10,
            child: RefreshIndicator(
              onRefresh: () => _fetchAllData(),
              color: TexoraColors.primaryBlue,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                children: [
                  // 1. Heading matching reference screen 3
                  _buildHeader(),
                  const SizedBox(height: 14),

                  // 2. Inference Engine Status Banner
                  if (_summary != null) ...[
                    _buildProviderBanner(_summary!.providerStatus),
                    const SizedBox(height: 16),
                  ],

                  // 3. Department Filter Tabs
                  _buildDepartmentFilterTabs(),
                  const SizedBox(height: 16),

                  // 4. Fleet KPI Summary Overview
                  _buildFleetKpiOverview(),
                  const SizedBox(height: 16),

                  // 5. Search & Status Filter Toolbar
                  _buildMachineToolbar(),
                  const SizedBox(height: 12),

                  // 6. Compact Machine Monitoring Table with Sparklines
                  _buildMachineTable(),
                  const SizedBox(height: 24),

                  // 7. AI Agent Investigation & Reasoning Log
                  _buildAiAgentActivitySection(),
                ],
              ),
            ),
          ),

          // Diagnostic Workspace Drawer (when machine is selected)
          if (_selectedMachine != null)
            Expanded(
              flex: 4,
              child: _buildMachineDetailWorkspace(_selectedMachine!),
            ),
        ],
      ),
    );
  }

  Widget _buildViewSelector() {
    return Container(
      decoration: BoxDecoration(
        color: TexoraColors.inputBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _subViewMode = 0),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _subViewMode == 0 ? TexoraColors.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: _subViewMode == 0
                    ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.precision_manufacturing_rounded,
                    size: 14,
                    color: _subViewMode == 0 ? TexoraColors.primaryBlue : TexoraColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Fleet Telemetry',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _subViewMode == 0 ? FontWeight.w700 : FontWeight.w500,
                      color: _subViewMode == 0 ? TexoraColors.textPrimary : TexoraColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _subViewMode = 1),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _subViewMode == 1 ? TexoraColors.cardBg : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: _subViewMode == 1
                    ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.view_in_ar_rounded,
                    size: 14,
                    color: _subViewMode == 1 ? TexoraColors.primaryBlue : TexoraColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Digital Twin & Topology',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: _subViewMode == 1 ? FontWeight.w700 : FontWeight.w500,
                      color: _subViewMode == 1 ? TexoraColors.textPrimary : TexoraColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 750;

        final titleSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Machine Monitoring & Fleet Telemetry',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: TexoraColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'AI Sensor Streams, Vibration Signatures & Dynamic Factory Twin',
              style: TextStyle(
                fontSize: 12,
                color: TexoraColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        );

        final actionSection = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildViewSelector(),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: TexoraColors.successBg,
                borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                border: Border.all(color: TexoraColors.successBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 7, color: TexoraColors.successText),
                  SizedBox(width: 6),
                  Text(
                    'Telemetry Live',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: TexoraColors.successText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isCycleRunning ? null : _runAgentCycle,
              icon: _isCycleRunning
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_circle_outline_rounded, size: 16),
              label: Text(_isCycleRunning ? 'Evaluating...' : 'Run Cycle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TexoraColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleSection,
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: actionSection,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleSection),
            actionSection,
          ],
        );
      },
    );
  }

  Widget _buildProviderBanner(ProviderStatusModel provider) {
    final isConf = provider.isConfigured;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
        border: Border.all(
          color: isConf ? TexoraColors.successBorder : TexoraColors.warningBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConf ? Icons.psychology_rounded : Icons.warning_amber_rounded,
            color: isConf ? TexoraColors.primaryBlue : TexoraColors.warningText,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  'Inference Engine: ${provider.provider.toUpperCase()} (${provider.model})',
                  style: const TextStyle(
                    color: TexoraColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                TexoraStatusBadge(
                  label: isConf ? 'ACTIVE' : 'FALLBACK (RULE/HEURISTIC)',
                  variant: isConf ? TexoraBadgeVariant.running : TexoraBadgeVariant.attention,
                  showDot: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentFilterTabs() {
    final totalCount = _machines.length;
    final spinningCount = _machines.where((m) => m.departmentName.toLowerCase().contains('spin') || m.departmentCode == 'SPN').length;
    final weavingCount = _machines.where((m) => m.departmentName.toLowerCase().contains('weav') || m.departmentCode == 'WEV').length;
    final knittingCount = _machines.where((m) => m.departmentName.toLowerCase().contains('knit') || m.departmentCode == 'KNT').length;
    final dyeingCount = _machines.where((m) => m.departmentName.toLowerCase().contains('dye') || m.departmentCode == 'DYE').length;
    final finishingCount = _machines.where((m) => m.departmentName.toLowerCase().contains('finish') || m.departmentCode == 'FNS').length;

    final depts = [
      {'id': 'ALL', 'name': 'All', 'count': totalCount},
      {'id': 'SPINNING', 'name': 'Spinning', 'count': spinningCount},
      {'id': 'WEAVING', 'name': 'Weaving', 'count': weavingCount},
      {'id': 'KNITTING', 'name': 'Knitting', 'count': knittingCount},
      {'id': 'DYEING', 'name': 'Dyeing', 'count': dyeingCount},
      {'id': 'FINISHING', 'name': 'Finishing', 'count': finishingCount},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: depts.map((d) {
          final isSelected = _selectedDepartmentFilter == d['id'];
          final count = d['count'] as int;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedDepartmentFilter = d['id'] as String),
              borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? TexoraColors.primaryBlue : TexoraColors.cardBg,
                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                  border: Border.all(
                    color: isSelected ? TexoraColors.primaryBlue : TexoraColors.borderDefault,
                  ),
                ),
                child: Text(
                  '${d['name']} ($count)',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : TexoraColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFleetKpiOverview() {
    final total = _machines.length;
    final healthy = _machines.where((m) => m.twinPresentationState == 'RUNNING' || m.rawStatus == 'OPERATIONAL').length;
    final warning = _machines.where((m) => m.twinPresentationState == 'WARNING' || m.rawStatus == 'WARNING').length;
    final critical = _machines.where((m) => m.twinPresentationState == 'CRITICAL' || m.rawStatus == 'CRITICAL').length;
    final stale = _machines.where((m) => m.isStale).length;

    final cards = [
      TexoraKpiCard(
        label: 'TOTAL MONITORED',
        value: '$total Machines',
        subtitle: '100% telemetry synced',
        isPositive: true,
        icon: Icons.precision_manufacturing_rounded,
        iconColor: TexoraColors.primaryBlue,
      ),
      TexoraKpiCard(
        label: 'HEALTHY & RUNNING',
        value: '$healthy Machines',
        subtitle: total > 0 ? '${((healthy / total) * 100).round()}% nominal' : '100%',
        isPositive: true,
        icon: Icons.check_circle_rounded,
        iconColor: TexoraColors.successText,
      ),
      TexoraKpiCard(
        label: 'SUB-OPTIMAL WARNING',
        value: '$warning Machines',
        subtitle: warning > 0 ? 'Action advised' : 'Zero warnings',
        isPositive: warning == 0,
        icon: Icons.warning_amber_rounded,
        iconColor: const Color(0xFFF59E0B),
      ),
      TexoraKpiCard(
        label: 'CRITICAL OUTAGES',
        value: '$critical Machines',
        subtitle: critical > 0 ? 'Urgent attention' : 'Zero outages',
        isPositive: critical == 0,
        icon: Icons.error_outline_rounded,
        iconColor: TexoraColors.criticalText,
      ),
      TexoraKpiCard(
        label: 'STALE TELEMETRY',
        value: '$stale Machines',
        subtitle: stale > 0 ? 'Heartbeat delayed' : 'Real-time',
        isPositive: stale == 0,
        icon: Icons.sensors_off_rounded,
        iconColor: TexoraColors.textMuted,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        int count = 5;
        if (w < 600) {
          count = 1;
        } else if (w < 900) {
          count = 2;
        } else if (w < 1200) {
          count = 3;
        }

        if (count == 1) {
          return Column(
            children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: c)).toList(),
          );
        }

        final itemWidth = (w - (count - 1) * 12) / count;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildMachineToolbar() {
    final filters = [
      {'id': 'ALL', 'label': 'All Fleet'},
      {'id': 'RUNNING', 'label': 'Healthy'},
      {'id': 'WARNING', 'label': 'Warning'},
      {'id': 'CRITICAL', 'label': 'Critical'},
      {'id': 'MAINTENANCE', 'label': 'Maintenance'},
      {'id': 'STALE', 'label': 'Stale Telemetry'},
    ];

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((f) {
              final isSelected = _selectedStatusFilter == f['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f['label']!),
                  selected: isSelected,
                  selectedColor: TexoraColors.primaryBlue.withAlpha(25),
                  backgroundColor: TexoraColors.cardBg,
                  labelStyle: TextStyle(
                    color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: isSelected ? TexoraColors.primaryBlue : TexoraColors.borderDefault,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedStatusFilter = f['id']!);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Search Box
        SizedBox(
          width: 240,
          height: 36,
          child: TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Search machine code, name...',
              hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
              prefixIcon: const Icon(Icons.search_rounded, color: TexoraColors.textMuted, size: 16),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: TexoraColors.borderDefault),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: TexoraColors.borderDefault),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 14, color: TexoraColors.textSecondary),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMachineTable() {
    final list = _filteredMachines;

    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
          border: Border.all(color: TexoraColors.borderDefault),
        ),
        child: const Center(
          child: Text(
            'No machines match the selected filter or search criteria.',
            style: TextStyle(color: TexoraColors.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
        border: Border.all(color: TexoraColors.borderDefault),
        boxShadow: TexoraSpacing.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1060),
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(120), // Machine Code
                1: FixedColumnWidth(210), // Asset & Dept
                2: FixedColumnWidth(125), // Status
                3: FixedColumnWidth(110), // Vibration
                4: FixedColumnWidth(100), // Temperature
                5: FixedColumnWidth(110), // Speed
                6: FixedColumnWidth(100), // Efficiency / Health
                7: FixedColumnWidth(100), // Trend Sparkline
                8: FixedColumnWidth(105), // Action
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // Table Header
                TableRow(
                  decoration: const BoxDecoration(
                    color: TexoraColors.workspaceBg,
                    border: Border(bottom: BorderSide(color: TexoraColors.borderDefault, width: 1.2)),
                  ),
                  children: [
                    _buildHeaderCell('MACHINE CODE'),
                    _buildHeaderCell('ASSET & DEPT'),
                    _buildHeaderCell('STATUS'),
                    _buildHeaderCell('VIBRATION'),
                    _buildHeaderCell('TEMP (°C)'),
                    _buildHeaderCell('SPEED'),
                    _buildHeaderCell('EFFICIENCY'),
                    _buildHeaderCell('TREND'),
                    _buildHeaderCell('ACTION'),
                  ],
                ),

                // Table Rows
                ...list.map((m) {
                  final telem = m.latestTelemetry ?? {};
                  final vib = (telem['vibration_mms'] as num?)?.toDouble();
                  final temp = (telem['temperature_c'] as num?)?.toDouble();
                  final rpm = (telem['speed_rpm'] as num?)?.toDouble();
                  final isSelected = _selectedMachine?.id == m.id;

                  // Vibration threshold styling
                  final vibColor = (vib != null && vib > 4.5)
                      ? TexoraColors.criticalText
                      : ((vib != null && vib > 2.8) ? const Color(0xFFD97706) : TexoraColors.successText);

                  // Temperature threshold styling
                  final tempColor = (temp != null && temp > 80)
                      ? TexoraColors.criticalText
                      : ((temp != null && temp > 65) ? const Color(0xFFD97706) : TexoraColors.textPrimary);

                  // Historical telemetry trend data (zero fabricated measurements)
                  final cachedHistory = _machineTelemetryCache[m.id];
                  List<double> trendData;
                  if (cachedHistory != null && cachedHistory.isNotEmpty) {
                    trendData = cachedHistory
                        .take(8)
                        .toList()
                        .reversed
                        .map((p) => (p['vibration_mms'] as num?)?.toDouble() ?? 0.0)
                        .toList();
                  } else if (m.id == _selectedMachine?.id && _selectedMachineTelemetry.isNotEmpty) {
                    trendData = _selectedMachineTelemetry
                        .take(8)
                        .toList()
                        .reversed
                        .map((p) => (p['vibration_mms'] as num?)?.toDouble() ?? 0.0)
                        .toList();
                  } else if (vib != null) {
                    trendData = [vib, vib];
                  } else {
                    trendData = const [];
                  }

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? TexoraColors.primaryBlue.withAlpha(15)
                          : Colors.white,
                      border: const Border(bottom: BorderSide(color: TexoraColors.borderDefault, width: 0.8)),
                    ),
                    children: [
                      // Machine Code
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(
                          m.code,
                          style: const TextStyle(
                            color: TexoraColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),

                      // Asset & Dept
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m.name,
                              style: const TextStyle(
                                color: TexoraColors.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${m.departmentName} (${m.departmentCode})',
                              style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      // Status Badge
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildStatusBadge(m.twinPresentationState, m.rawStatus),
                        ),
                      ),

                      // Vibration
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(
                          vib != null ? '${vib.toStringAsFixed(2)} mm/s' : '—',
                          style: TextStyle(color: vibColor, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),

                      // Temperature
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(
                          temp != null ? '${temp.toStringAsFixed(1)} °C' : '—',
                          style: TextStyle(color: tempColor, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),

                      // Speed / RPM
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(
                          rpm != null ? '${rpm.toInt()} RPM' : '—',
                          style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                        ),
                      ),

                      // Efficiency / Health Score
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              '${m.healthScore.toInt()}%',
                              style: TextStyle(
                                color: m.healthScore < 70
                                    ? TexoraColors.criticalText
                                    : (m.healthScore < 90 ? const Color(0xFFD97706) : TexoraColors.successText),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Trend Sparkline
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: TexoraSparkline(
                          data: trendData,
                          width: 68,
                          height: 22,
                          color: (vib != null && vib > 4.5) ? TexoraColors.criticalText : TexoraColors.successText,
                        ),
                      ),

                      // Action (Inspect button)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: ElevatedButton(
                          onPressed: () => _selectMachine(m),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected ? TexoraColors.primaryBlue : Colors.white,
                            foregroundColor: isSelected ? Colors.white : TexoraColors.textPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            side: BorderSide(
                              color: isSelected ? TexoraColors.primaryBlue : TexoraColors.borderDefault,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            elevation: 0,
                          ),
                          child: const Text('Inspect', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String twinState, String rawStatus) {
    if (twinState == 'CRITICAL' || rawStatus == 'CRITICAL') {
      return const TexoraStatusBadge(label: 'CRITICAL', variant: TexoraBadgeVariant.critical, showDot: true);
    } else if (twinState == 'WARNING' || rawStatus == 'WARNING') {
      return const TexoraStatusBadge(label: 'WARNING', variant: TexoraBadgeVariant.attention, showDot: true);
    } else if (twinState == 'UNDER_MAINTENANCE' || rawStatus == 'MAINTENANCE') {
      return const TexoraStatusBadge(label: 'SERVICE', variant: TexoraBadgeVariant.neutral, showDot: false);
    } else if (twinState == 'RUNNING' || rawStatus == 'OPERATIONAL') {
      return const TexoraStatusBadge(label: 'NORMAL', variant: TexoraBadgeVariant.running, showDot: true);
    } else {
      return const TexoraStatusBadge(label: 'IDLE', variant: TexoraBadgeVariant.neutral, showDot: false);
    }
  }

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        label,
        style: const TextStyle(
          color: TexoraColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildMachineDetailWorkspace(MachineTwinModel m) {
    final telem = m.latestTelemetry ?? {};
    final limits = m.operatingLimits ?? {};

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: TexoraColors.borderDefault, width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: TexoraColors.workspaceBg,
              border: Border(bottom: BorderSide(color: TexoraColors.borderDefault)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: TexoraColors.primaryBlue.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.analytics_rounded, color: TexoraColors.primaryBlue, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m.code} Diagnostic Workspace',
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          m.name,
                          style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: TexoraColors.textSecondary),
                  onPressed: _closeMachineDetail,
                  tooltip: 'Close Workspace',
                ),
              ],
            ),
          ),

          // Drawer Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                // Live Sensor Metrics Grid
                const Text(
                  'CURRENT SENSOR READINGS',
                  style: TextStyle(color: TexoraColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSensorMetricTile('Vibration', '${(telem['vibration_mms'] as num?)?.toStringAsFixed(2) ?? "—"} mm/s', TexoraColors.primaryBlue),
                    const SizedBox(width: 8),
                    _buildSensorMetricTile('Temperature', '${(telem['temperature_c'] as num?)?.toStringAsFixed(1) ?? "—"} °C', TexoraColors.textPrimary),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSensorMetricTile('Speed', '${(telem['speed_rpm'] as num?)?.toInt() ?? "—"} RPM', TexoraColors.textSecondary),
                    const SizedBox(width: 8),
                    _buildSensorMetricTile('Utilization', '${(telem['utilization_pct'] as num?)?.toStringAsFixed(1) ?? "—"}%', TexoraColors.successText),
                  ],
                ),
                const SizedBox(height: 18),

                // Operating Thresholds
                const Text(
                  'ENGINEERING OPERATING LIMITS',
                  style: TextStyle(color: TexoraColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TexoraColors.workspaceBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: TexoraColors.borderDefault),
                  ),
                  child: Column(
                    children: [
                      _buildThresholdRow('Warning Vibration:', '${limits['warning_vibration_mms'] ?? "4.0"} mm/s'),
                      _buildThresholdRow('Max Critical Vibration:', '${limits['max_vibration_mms'] ?? "5.5"} mm/s'),
                      _buildThresholdRow('Warning Temperature:', '${limits['warning_temp_c'] ?? "75.0"} °C'),
                      _buildThresholdRow('Max Critical Temperature:', '${limits['max_temp_c'] ?? "85.0"} °C'),
                      _buildThresholdRow('Rated Speed:', '${m.ratedSpeedRpm} RPM'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Interactive Historical Telemetry Trend Chart
                _buildTelemetryTrendWorkspace(m, limits),
                const SizedBox(height: 18),

                // Telemetry History Log
                const Text(
                  'RECENT TELEMETRY READINGS (LAST 10)',
                  style: TextStyle(color: TexoraColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                if (_isLoadingTelemetry && _selectedMachineTelemetry.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_selectedMachineTelemetry.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: TexoraColors.workspaceBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: TexoraColors.borderDefault),
                    ),
                    child: const Text('No recent telemetry samples returned from time-series storage.', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: TexoraColors.borderDefault),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _selectedMachineTelemetry.take(10).length,
                      separatorBuilder: (context, index) => const Divider(color: TexoraColors.borderDefault, height: 1),
                      itemBuilder: (ctx, idx) {
                        final item = _selectedMachineTelemetry[idx];
                        final ts = item['timestamp']?.toString() ?? '';
                        final vib = (item['vibration_mms'] as num?)?.toDouble();
                        final temp = (item['temperature_c'] as num?)?.toDouble();

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                ts.length > 19 ? ts.substring(11, 19) : ts,
                                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontFamily: 'monospace'),
                              ),
                              Text(
                                vib != null ? '${vib.toStringAsFixed(2)} mm/s' : '—',
                                style: const TextStyle(color: TexoraColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                temp != null ? '${temp.toStringAsFixed(1)} °C' : '—',
                                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorMetricTile(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: TexoraColors.workspaceBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: TexoraColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
          Text(value, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildTelemetryTrendWorkspace(MachineTwinModel m, Map<String, dynamic> limits) {
    final warningVib = (limits['warning_vibration_mms'] as num?)?.toDouble() ?? 4.0;
    final criticalVib = (limits['max_vibration_mms'] as num?)?.toDouble() ?? 5.5;
    final warningTemp = (limits['warning_temp_c'] as num?)?.toDouble() ?? 75.0;
    final criticalTemp = (limits['max_temp_c'] as num?)?.toDouble() ?? 85.0;

    List<TelemetryDataPoint> chartPoints = [];
    String unit = 'mm/s';
    Color lineColor = TexoraColors.primaryBlue;
    double? warnThreshold;
    double? critThreshold;

    if (_activeTrendMetric == 'vibration') {
      unit = 'mm/s';
      lineColor = TexoraColors.primaryBlue;
      warnThreshold = warningVib;
      critThreshold = criticalVib;
      chartPoints = _selectedMachineTelemetry.map((item) {
        final ts = DateTime.tryParse(item['timestamp']?.toString() ?? '') ?? DateTime.now();
        final val = (item['vibration_mms'] as num?)?.toDouble() ?? 0.0;
        return TelemetryDataPoint(timestamp: ts, value: val);
      }).toList();
    } else if (_activeTrendMetric == 'temperature') {
      unit = '°C';
      lineColor = const Color(0xFFD97706);
      warnThreshold = warningTemp;
      critThreshold = criticalTemp;
      chartPoints = _selectedMachineTelemetry.map((item) {
        final ts = DateTime.tryParse(item['timestamp']?.toString() ?? '') ?? DateTime.now();
        final val = (item['temperature_c'] as num?)?.toDouble() ?? 0.0;
        return TelemetryDataPoint(timestamp: ts, value: val);
      }).toList();
    } else {
      unit = 'RPM';
      lineColor = TexoraColors.purple;
      chartPoints = _selectedMachineTelemetry.map((item) {
        final ts = DateTime.tryParse(item['timestamp']?.toString() ?? '') ?? DateTime.now();
        final val = (item['speed_rpm'] as num?)?.toDouble() ?? 0.0;
        return TelemetryDataPoint(timestamp: ts, value: val);
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            const Text(
              'HISTORICAL TELEMETRY TREND',
              style: TextStyle(
                color: TexoraColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            // Metric Selector Tabs
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTrendTab('Vibration', 'vibration', TexoraColors.primaryBlue),
                const SizedBox(width: 4),
                _buildTrendTab('Temp', 'temperature', const Color(0xFFD97706)),
                const SizedBox(width: 4),
                _buildTrendTab('RPM', 'speed', TexoraColors.purple),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        TexoraTrendChart(
          points: chartPoints,
          metricName: _activeTrendMetric == 'vibration'
              ? 'Vibration (RMS)'
              : (_activeTrendMetric == 'temperature' ? 'Bearing Temperature' : 'Spindle Speed'),
          unit: unit,
          lineColor: lineColor,
          warningThreshold: warnThreshold,
          criticalThreshold: critThreshold,
          height: 180,
        ),
      ],
    );
  }

  Widget _buildTrendTab(String label, String metricKey, Color activeColor) {
    final isSelected = _activeTrendMetric == metricKey;
    return InkWell(
      onTap: () => setState(() => _activeTrendMetric = metricKey),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? activeColor : TexoraColors.borderDefault,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? activeColor : TexoraColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildAiAgentActivitySection() {
    final pending = _summary?.pendingIncidents ?? [];
    final execs = _summary?.recentExecutions ?? [];
    final pendingApprovals = _approvals.where((a) => a.status == 'PENDING').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(
              child: Text(
                'AI INVESTIGATION & AUTONOMOUS REASONING LOG',
                style: TextStyle(color: TexoraColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_snapshot != null)
              Text(
                'Plant Snapshot: ${_snapshot!.factoryCode} • Synchronized',
                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10.5, fontFamily: 'monospace'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 850;

            final leftColumn = Column(
              children: [
                // Sub-panel: Pending Incidents
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
                    border: Border.all(color: TexoraColors.borderDefault),
                    boxShadow: TexoraSpacing.cardShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              'Awaiting AI Investigation',
                              style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFF59E0B)),
                            ),
                            child: Text(
                              '${pending.length} Pending',
                              style: const TextStyle(color: Color(0xFFD97706), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (pending.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text('All detected incidents have completed AI investigation.', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12)),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: pending.take(4).length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final inc = pending[idx];
                            final isInv = _investigatingIncidentId == inc.id;

                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: TexoraColors.workspaceBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: TexoraColors.borderDefault),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${inc.machineCode} • ${inc.severity}',
                                          style: TextStyle(
                                            color: inc.severity == 'CRITICAL' ? TexoraColors.criticalText : const Color(0xFFD97706),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          inc.summary,
                                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: isInv ? null : () => _triggerInvestigation(inc.id),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TexoraColors.primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                      elevation: 0,
                                    ),
                                    child: isInv
                                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Text('Investigate', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // Sub-panel: Pending Human Approvals (if any)
                if (pendingApprovals.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
                      border: Border.all(color: const Color(0xFFF59E0B).withAlpha(120)),
                      boxShadow: TexoraSpacing.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: Text(
                                'Pending Approvals',
                                style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${pendingApprovals.length} Req',
                              style: const TextStyle(color: Color(0xFFD97706), fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: pendingApprovals.take(3).length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final appr = pendingApprovals[idx];
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: TexoraColors.workspaceBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: TexoraColors.borderDefault),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          appr.title.isNotEmpty ? appr.title : appr.requestedAction,
                                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Risk: ${appr.riskLevel} • Code: ${appr.approvalCode}',
                                          style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton(
                                    onPressed: () => _handleReject(appr.id),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFD97706),
                                      side: const BorderSide(color: Color(0xFFD97706)),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Reject', style: TextStyle(fontSize: 10)),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed: () => _handleApprove(appr.id),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TexoraColors.successText,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      elevation: 0,
                                    ),
                                    child: const Text('Approve', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );

            final rightColumn = Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
                border: Border.all(color: TexoraColors.borderDefault),
                boxShadow: TexoraSpacing.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Text(
                          'Recent AI Diagnoses & Findings',
                          style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${execs.length} Recorded',
                        style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (execs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text('No AI investigations executed yet.', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12)),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: execs.take(4).length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final ex = execs[idx];
                        final hasDec = ex.decisions.isNotEmpty;
                        final dec = hasDec ? ex.decisions.first : null;

                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: TexoraColors.workspaceBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: TexoraColors.borderDefault),
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
                                        const Icon(Icons.smart_toy_rounded, color: TexoraColors.primaryBlue, size: 14),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            ex.triggerEvent.isNotEmpty ? ex.triggerEvent : 'Diagnostic Run',
                                            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${ex.latencyMs}ms | ${ex.tokenCount} tokens',
                                    style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ex.executionSummary,
                                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (dec != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: TexoraColors.borderDefault),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text('Verdict: ', style: TextStyle(color: TexoraColors.textMuted, fontSize: 10.5)),
                                      Expanded(
                                        child: Text(
                                          dec.rationale.isNotEmpty ? dec.rationale : dec.decisionTypeDisplay,
                                          style: const TextStyle(color: TexoraColors.primaryBlue, fontSize: 10.5, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${dec.confidenceScore.toInt()}%',
                                        style: const TextStyle(color: TexoraColors.successText, fontSize: 10.5, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            );

            if (isNarrow) {
              return Column(
                children: [
                  leftColumn,
                  const SizedBox(height: 16),
                  rightColumn,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: leftColumn),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: rightColumn),
              ],
            );
          },
        ),
      ],
    );
  }
}
