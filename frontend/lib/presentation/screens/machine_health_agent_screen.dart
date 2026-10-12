import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/ai_agent_model.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/services/api_service.dart';

class MachineHealthAgentScreen extends StatefulWidget {
  final ApiService? apiService;

  const MachineHealthAgentScreen({super.key, this.apiService});

  @override
  State<MachineHealthAgentScreen> createState() => _MachineHealthAgentScreenState();
}

class _MachineHealthAgentScreenState extends State<MachineHealthAgentScreen> {
  late final ApiService _apiService;
  Timer? _pollingTimer;

  bool _isLoading = true;
  String? _errorMessage;

  // Fleet & Snapshot data
  DigitalTwinSnapshotModel? _snapshot;
  List<MachineTwinModel> _machines = [];
  MachineTwinModel? _selectedMachine;
  List<Map<String, dynamic>> _selectedMachineTelemetry = [];
  bool _isLoadingTelemetry = false;

  // AI Agent Data
  AgentSummaryModel? _summary;
  List<ApprovalRequestModel> _approvals = [];
  int? _investigatingIncidentId;
  bool _isCycleRunning = false;

  // Filters & Search
  String _selectedStatusFilter = 'ALL';
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
    setState(() {
      _selectedMachine = machine;
      _isLoadingTelemetry = true;
      _selectedMachineTelemetry = [];
    });

    try {
      final telemetry = await _apiService.fetchMachineTelemetry(machine.id);
      if (mounted) {
        setState(() {
          _selectedMachineTelemetry = telemetry;
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
    setState(() {
      _investigatingIncidentId = incidentId;
    });

    final res = await _apiService.triggerInvestigation(incidentId);

    if (mounted) {
      setState(() {
        _investigatingIncidentId = null;
      });

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Investigation Completed for Incident #$incidentId'),
            backgroundColor: AppColors.successGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Investigation notice: ${res['error'] ?? res['message'] ?? 'Check AI provider configuration'}'),
            backgroundColor: const Color(0xFFF59E0B),
          ),
        );
      }
      _fetchAllData(isBackground: true);
    }
  }

  Future<void> _triggerCycle() async {
    setState(() {
      _isCycleRunning = true;
    });

    final res = await _apiService.triggerAgentCycle();

    if (mounted) {
      setState(() {
        _isCycleRunning = false;
      });

      final count = res['investigated_count'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Autonomous AI cycle completed: $count investigations executed across fleet.'),
          backgroundColor: AppColors.primaryBlueLight,
        ),
      );
      _fetchAllData(isBackground: true);
    }
  }

  Future<void> _handleApprove(int approvalId) async {
    final success = await _apiService.approveRequest(approvalId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Action approved & executed. Work order generated.' : 'Failed to execute approval.'),
          backgroundColor: success ? AppColors.successGreen : AppColors.errorRed,
        ),
      );
      _fetchAllData(isBackground: true);
    }
  }

  Future<void> _handleReject(int approvalId) async {
    final success = await _apiService.rejectRequest(approvalId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Approval rejected & action cancelled.' : 'Failed to reject approval.'),
          backgroundColor: const Color(0xFFF59E0B),
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

      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: _isLoading && _machines.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryBlueLight))
          : _errorMessage != null && _machines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 40),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _fetchAllData(),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                        child: const Text('Retry Connection'),
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    // Main Fleet & AI Overview Panel
                    Expanded(
                      flex: _selectedMachine != null ? 6 : 10,
                      child: RefreshIndicator(
                        onRefresh: () => _fetchAllData(),
                        color: AppColors.primaryBlueLight,
                        child: ListView(
                          padding: const EdgeInsets.all(24.0),
                          children: [
                            // 1. Header Bar with Manual Trigger
                            _buildHeader(),
                            const SizedBox(height: 18),

                            // 2. Inference Provider Status Banner
                            if (_summary != null) ...[
                              _buildProviderBanner(_summary!.providerStatus),
                              const SizedBox(height: 18),
                            ],

                            // 3. Machine Health Fleet KPI Metrics
                            _buildFleetKpiOverview(),
                            const SizedBox(height: 20),

                            // 4. Machine Monitoring Table Toolbar & Filters
                            _buildMachineToolbar(),
                            const SizedBox(height: 12),

                            // 5. Machine Monitoring Table
                            _buildMachineTable(),
                            const SizedBox(height: 28),

                            // 6. AI Agent Activity & Execution Stream
                            _buildAiAgentActivitySection(),
                          ],
                        ),
                      ),
                    ),

                    // Machine Detail Workspace Drawer (when selected)
                    if (_selectedMachine != null)
                      Expanded(
                        flex: 4,
                        child: _buildMachineDetailWorkspace(_selectedMachine!),
                      ),
                  ],
                ),
    );
  }

  Widget _buildHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA855F7).withAlpha(35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA855F7).withAlpha(100)),
                  ),
                  child: const Text(
                    'AUTONOMOUS AGENT SPECIALIST',
                    style: TextStyle(
                      color: Color(0xFFA855F7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const Text(
                  'Machine Health AI & Fleet Telemetry',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Live multi-domain telemetry surveillance, operating limits verification, anomaly diagnostics, and human-in-the-loop action dispatches.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: () => _fetchAllData(),
              icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF94A3B8)),
              label: const Text('Refresh', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF334155)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isCycleRunning ? null : _triggerCycle,
              icon: _isCycleRunning
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt_rounded, size: 16),
              label: Text(_isCycleRunning ? 'Evaluating Fleet...' : 'Run Agent Cycle (Manual)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProviderBanner(ProviderStatusModel provider) {
    final isConf = provider.isConfigured;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isConf ? const Color(0xFF38BDF8).withAlpha(80) : const Color(0xFFF59E0B).withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(
            isConf ? Icons.psychology_rounded : Icons.warning_amber_rounded,
            color: isConf ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
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
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isConf ? AppColors.successGreen : const Color(0xFFF59E0B)).withAlpha(35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isConf ? 'ACTIVE' : 'FALLBACK (RULE/HEURISTIC)',
                    style: TextStyle(
                      color: isConf ? AppColors.successGreen : const Color(0xFFF59E0B),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetKpiOverview() {
    final total = _machines.length;
    final healthy = _machines.where((m) => m.twinPresentationState == 'RUNNING' || m.rawStatus == 'OPERATIONAL').length;
    final warning = _machines.where((m) => m.twinPresentationState == 'WARNING' || m.rawStatus == 'WARNING').length;
    final critical = _machines.where((m) => m.twinPresentationState == 'CRITICAL' || m.rawStatus == 'CRITICAL').length;
    final stale = _machines.where((m) => m.isStale).length;

    return Row(
      children: [
        _buildKpiCard('TOTAL MONITORED', '$total Machines', Icons.precision_manufacturing_rounded, const Color(0xFF38BDF8)),
        const SizedBox(width: 12),
        _buildKpiCard('HEALTHY & RUNNING', '$healthy Machines', Icons.check_circle_rounded, AppColors.successGreen),
        const SizedBox(width: 12),
        _buildKpiCard('SUB-OPTIMAL WARNING', '$warning Machines', Icons.warning_amber_rounded, const Color(0xFFF59E0B), isAlert: warning > 0),
        const SizedBox(width: 12),
        _buildKpiCard('CRITICAL OUTAGES', '$critical Machines', Icons.error_outline_rounded, AppColors.errorRed, isAlert: critical > 0),
        const SizedBox(width: 12),
        _buildKpiCard('STALE TELEMETRY', '$stale Machines', Icons.sensors_off_rounded, const Color(0xFF94A3B8), isAlert: stale > 0),
      ],
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color, {bool isAlert = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withAlpha(120),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAlert ? color.withAlpha(150) : const Color(0xFF334155),
            width: isAlert ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.4), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
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
                  selectedColor: const Color(0xFF2563EB).withAlpha(60),
                  backgroundColor: const Color(0xFF1E293B),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
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
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Search machine code, name...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
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
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: const Center(
          child: Text('No machines match the selected filter or search criteria.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(130), // Machine Code
          1: FlexColumnWidth(1.2),  // Machine Name & Dept
          2: FixedColumnWidth(110), // Status
          3: FixedColumnWidth(100), // Vibration
          4: FixedColumnWidth(95),  // Temperature
          5: FixedColumnWidth(100), // Speed
          6: FixedColumnWidth(130), // Freshness
          7: FixedColumnWidth(90),  // Health Score
          8: FixedColumnWidth(95),  // Action
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // Table Header
          TableRow(
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1.2)),
            ),
            children: [
              _buildHeaderCell('MACHINE CODE'),
              _buildHeaderCell('ASSET & DEPT'),
              _buildHeaderCell('STATUS'),
              _buildHeaderCell('VIBRATION'),
              _buildHeaderCell('TEMP (°C)'),
              _buildHeaderCell('SPEED'),
              _buildHeaderCell('LAST READING'),
              _buildHeaderCell('HEALTH'),
              _buildHeaderCell('ACTION'),
            ],
          ),

          // Machine Rows
          ...list.map((m) {
            final isSelected = _selectedMachine?.id == m.id;
            final telem = m.latestTelemetry ?? {};
            final limits = m.operatingLimits ?? {};

            final vib = (telem['vibration_mms'] as num?)?.toDouble();
            final temp = (telem['temperature_c'] as num?)?.toDouble();
            final rpm = (telem['speed_rpm'] as num?)?.toDouble();
            final ts = telem['timestamp']?.toString() ?? '';

            final warnVib = (limits['warning_vibration_mms'] as num?)?.toDouble() ?? 4.0;
            final maxVib = (limits['max_vibration_mms'] as num?)?.toDouble() ?? 5.5;
            final warnTemp = (limits['warning_temp_c'] as num?)?.toDouble() ?? 75.0;

            Color vibColor = const Color(0xFF38BDF8);
            if (vib != null) {
              if (vib >= maxVib) {
                vibColor = AppColors.errorRed;
              } else if (vib >= warnVib) {
                vibColor = const Color(0xFFF59E0B);
              }
            }

            Color tempColor = Colors.white;
            if (temp != null && temp >= warnTemp) {
              tempColor = const Color(0xFFF59E0B);
            }

            return TableRow(
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF2563EB).withAlpha(40) : Colors.transparent,
                border: const Border(bottom: BorderSide(color: Color(0xFF334155), width: 0.8)),
              ),
              children: [
                // Machine Code
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF475569)),
                        ),
                        child: Text(
                          m.code,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Name & Department
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${m.departmentName} (${m.departmentCode})',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                      ),
                    ],
                  ),
                ),

                // Operational Status
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: _buildStatusBadge(m.twinPresentationState, m.rawStatus),
                ),

                // Vibration
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    vib != null ? '${vib.toStringAsFixed(2)} mm/s' : '—',
                    style: TextStyle(color: vibColor, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),

                // Temperature
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    temp != null ? '${temp.toStringAsFixed(1)} °C' : '—',
                    style: TextStyle(color: tempColor, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),

                // Speed / RPM
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    rpm != null ? '${rpm.toInt()} RPM' : '—',
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
                  ),
                ),

                // Last Reading
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    ts.length > 19 ? ts.substring(11, 19) : (ts.isNotEmpty ? ts : 'Offline'),
                    style: TextStyle(color: m.isStale ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8), fontSize: 10.5, fontFamily: 'monospace'),
                  ),
                ),

                // Health Score
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    '${m.healthScore.toInt()}%',
                    style: TextStyle(
                      color: m.healthScore < 70
                          ? AppColors.errorRed
                          : (m.healthScore < 90 ? const Color(0xFFF59E0B) : AppColors.successGreen),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Action
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: ElevatedButton(
                    onPressed: () => _selectMachine(m),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      side: const BorderSide(color: Color(0xFF334155)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text('Inspect', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String twinState, String rawStatus) {
    Color color;
    String label;

    if (twinState == 'CRITICAL' || rawStatus == 'CRITICAL') {
      color = AppColors.errorRed;
      label = 'CRITICAL';
    } else if (twinState == 'WARNING' || rawStatus == 'WARNING') {
      color = const Color(0xFFF59E0B);
      label = 'WARNING';
    } else if (twinState == 'UNDER_MAINTENANCE' || rawStatus == 'MAINTENANCE') {
      color = const Color(0xFFA855F7);
      label = 'SERVICE';
    } else if (twinState == 'RUNNING' || rawStatus == 'OPERATIONAL') {
      color = AppColors.successGreen;
      label = 'NORMAL';
    } else {
      color = const Color(0xFF94A3B8);
      label = 'IDLE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
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
        color: Color(0xFF0F172A),
        border: Border(left: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drawer Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withAlpha(35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.analytics_rounded, color: Color(0xFF38BDF8), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m.code} Diagnostic Workspace',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          m.name,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
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
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSensorMetricTile('Vibration', '${(telem['vibration_mms'] as num?)?.toStringAsFixed(2) ?? "—"} mm/s', const Color(0xFF38BDF8)),
                    const SizedBox(width: 8),
                    _buildSensorMetricTile('Temperature', '${(telem['temperature_c'] as num?)?.toStringAsFixed(1) ?? "—"} °C', Colors.white),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildSensorMetricTile('Speed', '${(telem['speed_rpm'] as num?)?.toInt() ?? "—"} RPM', const Color(0xFFCBD5E1)),
                    const SizedBox(width: 8),
                    _buildSensorMetricTile('Utilization', '${(telem['utilization_pct'] as num?)?.toStringAsFixed(1) ?? "—"}%', AppColors.successGreen),
                  ],
                ),
                const SizedBox(height: 18),

                // Operating Thresholds
                const Text(
                  'ENGINEERING OPERATING LIMITS',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
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

                // Telemetry History Log
                const Text(
                  'RECENT TELEMETRY READINGS (LAST 10)',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                ),
                const SizedBox(height: 8),
                if (_isLoadingTelemetry)
                  const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                else if (_selectedMachineTelemetry.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('No recent telemetry samples returned from time-series storage.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _selectedMachineTelemetry.take(10).length,
                      separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
                      itemBuilder: (ctx, idx) {
                        final item = _selectedMachineTelemetry[idx];
                        final ts = item['timestamp']?.toString() ?? '';
                        final vib = (item['vibration_mms'] as num?)?.toDouble();
                        final temp = (item['temperature_c'] as num?)?.toDouble();

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                ts.length > 19 ? ts.substring(11, 19) : ts,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontFamily: 'monospace'),
                              ),
                              Text(
                                vib != null ? '${vib.toStringAsFixed(2)} mm/s' : '—',
                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                temp != null ? '${temp.toStringAsFixed(1)} °C' : '—',
                                style: const TextStyle(color: Colors.white, fontSize: 11),
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
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
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
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ],
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
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_snapshot != null)
              Text(
                'Plant Snapshot: ${_snapshot!.factoryCode} • Synchronized',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontFamily: 'monospace'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Pending Incidents Awaiting AI & Approvals
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  // Sub-panel: Pending Incidents
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF334155)),
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
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withAlpha(35),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${pending.length} Pending',
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (pending.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text('All detected incidents have completed AI investigation.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
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
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF334155)),
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
                                              color: inc.severity == 'CRITICAL' ? AppColors.errorRed : const Color(0xFFF59E0B),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            inc.summary,
                                            style: const TextStyle(color: Colors.white, fontSize: 11.5),
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
                                        backgroundColor: const Color(0xFF0284C7),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF59E0B).withAlpha(100)),
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
                                  style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${pendingApprovals.length} Req',
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5, fontWeight: FontWeight.bold),
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
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            appr.title.isNotEmpty ? appr.title : appr.requestedAction,
                                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Risk: ${appr.riskLevel} • Code: ${appr.approvalCode}',
                                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () => _handleReject(appr.id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFF59E0B),
                                        side: const BorderSide(color: Color(0xFFF59E0B)),
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
                                        backgroundColor: AppColors.successGreen,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              ),
            ),
            const SizedBox(width: 16),

            // Right Column: Recent AI Inferences & Verdicts
            Expanded(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
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
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${execs.length} Recorded',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (execs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text('No AI investigations executed yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
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
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
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
                                          const Icon(Icons.smart_toy_rounded, color: Color(0xFF38BDF8), size: 14),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              ex.triggerEvent.isNotEmpty ? ex.triggerEvent : 'Diagnostic Run',
                                              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${ex.latencyMs}ms | ${ex.tokenCount} tokens',
                                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ex.executionSummary,
                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (dec != null) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        const Text('Verdict: ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5)),
                                        Expanded(
                                          child: Text(
                                            dec.rationale.isNotEmpty ? dec.rationale : dec.decisionTypeDisplay,
                                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${dec.confidenceScore.toInt()}%',
                                          style: const TextStyle(color: AppColors.successGreen, fontSize: 10.5, fontWeight: FontWeight.bold),
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
              ),
            ),
          ],
        ),
      ],
    );
  }
}
