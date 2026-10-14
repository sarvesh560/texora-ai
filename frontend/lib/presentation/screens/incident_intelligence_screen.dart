import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/incident_model.dart';
import '../../data/services/api_service.dart';
import '../widgets/autonomous_workflow_monitor.dart';
import '../widgets/business_impact_card.dart';
import 'audit_trail_screen.dart';

class IncidentIntelligenceScreen extends StatefulWidget {
  final ApiService? apiService;
  final VoidCallback? onRefresh;
  final Function(int)? onOpenApproval;
  final Function(int)? onNavigateToRecovery;
  final VoidCallback? onNavigateToApprovals;

  const IncidentIntelligenceScreen({
    super.key,
    this.apiService,
    this.onRefresh,
    this.onOpenApproval,
    this.onNavigateToRecovery,
    this.onNavigateToApprovals,
  });

  @override
  State<IncidentIntelligenceScreen> createState() => _IncidentIntelligenceScreenState();
}

class _IncidentIntelligenceScreenState extends State<IncidentIntelligenceScreen> {
  late final ApiService _apiService;
  bool _isLoading = true;
  String? _errorMessage;

  List<FactoryIncidentModel> _incidents = [];
  IncidentsSummaryModel? _summary;

  // Filters & Search
  String _searchQuery = '';
  String _selectedSeverity = 'ALL';
  String _selectedDepartment = 'ALL';
  String _selectedStatus = 'ALL';

  // Selected Incident for Detail Workspace
  FactoryIncidentModel? _selectedIncident;
  Map<String, dynamic>? _incidentIntelligenceData;
  bool _isLoadingDetail = false;

  Timer? _refreshTimer;

  final List<String> _severities = ['ALL', 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];
  final List<String> _departments = ['ALL', 'Spinning', 'Weaving', 'Knitting', 'Dyeing', 'Finishing'];
  final List<String> _statuses = ['ALL', 'OPEN', 'INVESTIGATING', 'MITIGATING', 'RESOLVED', 'CLOSED'];

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final incsFuture = _apiService.getFactoryIncidents();
      final summaryFuture = _apiService.fetchIncidentsSummary();

      final results = await Future.wait([incsFuture, summaryFuture]);
      final fetchedIncidents = results[0] as List<FactoryIncidentModel>;
      final fetchedSummary = results[1] as IncidentsSummaryModel?;

      if (mounted) {
        setState(() {
          _incidents = fetchedIncidents;
          _summary = fetchedSummary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openIncidentWorkspace(FactoryIncidentModel incident) async {
    setState(() {
      _selectedIncident = incident;
      _isLoadingDetail = true;
      _incidentIntelligenceData = null;
    });

    final data = await _apiService.fetchIncidentIntelligence(incident.id);
    if (mounted) {
      setState(() {
        _incidentIntelligenceData = data;
        _isLoadingDetail = false;
      });
    }
  }

  void _closeWorkspace() {
    setState(() {
      _selectedIncident = null;
      _incidentIntelligenceData = null;
    });
  }

  void _openAuditTrailDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 1000,
            height: 750,
            child: AuditTrailScreen(
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
  }

  List<FactoryIncidentModel> get _filteredIncidents {
    return _incidents.where((inc) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final code = inc.incidentCode.toLowerCase();
        final summary = inc.summary.toLowerCase();
        final machine = (inc.machineCode ?? '').toLowerCase();
        if (!code.contains(query) && !summary.contains(query) && !machine.contains(query)) {
          return false;
        }
      }
      if (_selectedSeverity != 'ALL' && inc.severity.toUpperCase() != _selectedSeverity) {
        return false;
      }
      if (_selectedDepartment != 'ALL') {
        final dept = inc.departmentName.isNotEmpty ? inc.departmentName : inc.departmentCode;
        if (!dept.toLowerCase().contains(_selectedDepartment.toLowerCase())) {
          return false;
        }
      }
      if (_selectedStatus != 'ALL' && inc.status.toUpperCase() != _selectedStatus) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: Row(
        children: [
          // Main Incidents List & Controls
          Expanded(
            flex: _selectedIncident != null ? 5 : 10,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildMetricCards(),
                  const SizedBox(height: 16),
                  _buildFilterBar(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildIncidentTable()),
                ],
              ),
            ),
          ),

          // Incident Intelligence Detail Workspace Drawer
          if (_selectedIncident != null)
            Expanded(
              flex: 6,
              child: Container(
                decoration: const BoxDecoration(
                  color: TexoraColors.cardBg,
                  border: Border(left: BorderSide(color: TexoraColors.cardBorder, width: 1.5)),
                ),
                child: _buildDetailWorkspace(),
              ),
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
      runSpacing: 10,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: TexoraColors.criticalBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TexoraColors.criticalBorder),
              ),
              child: const Icon(Icons.radar_rounded, color: TexoraColors.criticalText, size: 22),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incident Intelligence & Abnormality Management',
                    style: TextStyle(color: TexoraColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Real-time automated anomaly triage, AI diagnostics, and strategy workflows',
                    style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _openAuditTrailDialog,
              icon: const Icon(Icons.shield_outlined, size: 15, color: TexoraColors.primaryBlue),
              label: const Text('Audit Trail', style: TextStyle(color: TexoraColors.primaryBlue, fontSize: 12, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: TexoraColors.primaryLightBorder),
                backgroundColor: TexoraColors.primaryLight,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: TexoraColors.primaryBlue),
              onPressed: () => _loadData(),
              tooltip: 'Refresh Incidents',
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TexoraColors.cardBorder),
              ),
              child: Row(
                children: const [
                  Icon(Icons.circle, size: 8, color: TexoraColors.successText),
                  SizedBox(width: 6),
                  Text('AI MONITOR ACTIVE', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCards() {
    final active = _incidents.where((i) => i.status != 'RESOLVED' && i.status != 'CLOSED').length;
    final critical = _incidents.where((i) => i.severity == 'CRITICAL' && i.status != 'RESOLVED').length;
    final investigating = _incidents.where((i) => i.status == 'INVESTIGATING' || i.status == 'OPEN').length;
    final resolved = _incidents.where((i) => i.status == 'RESOLVED' || i.status == 'CLOSED').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 700
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildMetricTile('Active Incidents', '$active', const Color(0xFF38BDF8), Icons.warning_amber_rounded, cardWidth),
            _buildMetricTile('Critical Outages', '$critical', const Color(0xFFEF4444), Icons.error_outline_rounded, cardWidth),
            _buildMetricTile('AI Investigating', '$investigating', const Color(0xFFA855F7), Icons.psychology_rounded, cardWidth),
            _buildMetricTile('Resolved Total', '$resolved', const Color(0xFF10B981), Icons.check_circle_outline_rounded, cardWidth),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, IconData icon, double width) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TexoraColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  Text(label, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search input
          SizedBox(
            width: 220,
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search ID, machine, summary...',
                hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded, color: TexoraColors.textMuted, size: 16),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.primaryBlue)),
              ),
            ),
          ),

          // Severity Dropdown
          _buildDropdownFilter('Severity', _selectedSeverity, _severities, (val) => setState(() => _selectedSeverity = val)),

          // Department Dropdown
          _buildDropdownFilter('Dept', _selectedDepartment, _departments, (val) => setState(() => _selectedDepartment = val)),

          // Status Dropdown
          _buildDropdownFilter('Status', _selectedStatus, _statuses, (val) => setState(() => _selectedStatus = val)),
        ],
      ),
    );
  }

  Widget _buildDropdownFilter(String label, String value, List<String> options, Function(String) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: TexoraColors.cardBg,
          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: TexoraColors.textSecondary, size: 16),
          items: options.map((opt) => DropdownMenuItem(value: opt, child: Text('$label: $opt'))).toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }

  Widget _buildIncidentTable() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: TexoraColors.primaryBlue));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: TexoraColors.criticalText, size: 36),
            const SizedBox(height: 8),
            Text('Failed to load incidents: $_errorMessage', style: const TextStyle(color: TexoraColors.textPrimary)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: TexoraColors.primaryBlue, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredIncidents;
    if (filtered.isEmpty) {
      if (_incidents.isEmpty) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TexoraColors.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, color: TexoraColors.primaryBlue, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'No Operational Incidents Recorded',
                  style: TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Continuous telemetry surveillance and anomaly detection are active.\nNo machine abnormalities or safety limit breaches are currently detected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12, height: 1.4),
                ),
                if (_summary?.checkpoint != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: TexoraColors.workspaceBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: TexoraColors.cardBorder),
                    ),
                    child: Text(
                      'Detector Daemon: ${_summary!.checkpoint.isThreadAlive ? "ACTIVE (Scanning telemetry)" : "DAEMON (Periodic batch evaluation)"} • Total Telemetry Evaluated: ${_summary!.checkpoint.totalTelemetryProcessed}',
                      style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      // Filter mismatch state
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: TexoraColors.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: TexoraColors.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.filter_alt_off_rounded, color: Color(0xFFF59E0B), size: 36),
              const SizedBox(height: 10),
              const Text(
                'No Incidents Match Selected Filters',
                style: TextStyle(color: TexoraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '0 matching of ${_incidents.length} total database incidents.\nTry clearing the search query or resetting filters.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _selectedSeverity = 'ALL';
                    _selectedDepartment = 'ALL';
                    _selectedStatus = 'ALL';
                  });
                },
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Clear All Filters', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TexoraColors.primaryLight,
                  foregroundColor: TexoraColors.primaryBlue,
                  elevation: 0,
                  side: const BorderSide(color: TexoraColors.primaryLightBorder),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const Divider(color: TexoraColors.cardBorder, height: 1),
        itemBuilder: (context, index) {
          final inc = filtered[index];
          final isSelected = _selectedIncident?.id == inc.id;

          return Material(
            color: isSelected ? TexoraColors.primaryLight : Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              onTap: () => _openIncidentWorkspace(inc),
              leading: _buildSeverityBadge(inc.severity),
              title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(inc.incidentCode, style: const TextStyle(color: TexoraColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: TexoraColors.primaryLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: TexoraColors.primaryLightBorder),
                    ),
                    child: Text(
                      inc.machineCode ?? 'UNKNOWN',
                      style: const TextStyle(color: TexoraColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '• ${inc.departmentName.isNotEmpty ? inc.departmentName : inc.departmentCode}',
                    style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  inc.summary,
                  style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusChip(inc.status),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => _openIncidentWorkspace(inc),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? TexoraColors.primaryBlue : TexoraColors.workspaceBg,
                      foregroundColor: isSelected ? Colors.white : TexoraColors.primaryBlue,
                      elevation: 0,
                      side: BorderSide(color: isSelected ? TexoraColors.primaryBlue : TexoraColors.cardBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Workspace ➔', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeverityBadge(String severity) {
    Color color;
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        color = const Color(0xFFEF4444);
        break;
      case 'HIGH':
        color = const Color(0xFFF97316);
        break;
      case 'MEDIUM':
        color = const Color(0xFFF59E0B);
        break;
      default:
        color = TexoraColors.primaryBlue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withAlpha(80))),
      child: Text(severity.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status.toUpperCase()) {
      case 'OPEN':
      case 'INVESTIGATING':
        color = const Color(0xFFA855F7);
        break;
      case 'MITIGATING':
        color = const Color(0xFFF97316);
        break;
      case 'RESOLVED':
      case 'CLOSED':
        color = const Color(0xFF10B981);
        break;
      default:
        color = TexoraColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(20), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  // =========================================================================
  // INCIDENT DETAIL WORKSPACE (MULTI-PANEL)
  // =========================================================================

  Widget _buildDetailWorkspace() {
    final inc = _selectedIncident!;
    final data = _incidentIntelligenceData;

    return Column(
      children: [
        // Drawer Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: const BoxDecoration(
            color: TexoraColors.cardBg,
            border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  _buildSeverityBadge(inc.severity),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inc.incidentCode, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('${inc.machineCode ?? "Machine"} • ${inc.departmentName.isNotEmpty ? inc.departmentName : inc.departmentCode}', style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: TexoraColors.textSecondary),
                onPressed: _closeWorkspace,
                tooltip: 'Close Workspace',
              ),
            ],
          ),
        ),

        // Drawer Content
        Expanded(
          child: _isLoadingDetail
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    // 1. Autonomous Workflow Lifecycle Stepper
                    _buildWorkflowStepper(data),
                    const SizedBox(height: 16),

                    // 2. Live 12-Stage Autonomous Workflow Pipeline
                    AutonomousWorkflowMonitor(
                      key: ValueKey('detail_wf_${inc.id}'),
                      incidentId: inc.id,
                      isCompact: false,
                      onNavigateToApprovals: widget.onNavigateToApprovals,
                      onNavigateToRecovery: widget.onNavigateToRecovery != null
                          ? () => widget.onNavigateToRecovery!(data?['recovery_case']?['id'] ?? 1)
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // 2. Business Impact & Strategy Comparison
                    BusinessImpactCard(
                      key: ValueKey('detail_bi_${inc.id}'),
                      incidentId: inc.id,
                    ),
                    const SizedBox(height: 16),

                    // 3. Machine Telemetry & Health Panel
                    _buildMachineHealthCard(data),
                    const SizedBox(height: 16),

                    // 3. AI Diagnostic Investigation Panel
                    _buildAiInvestigationCard(data),
                    const SizedBox(height: 16),

                    // 4. Production & Inventory Constraints
                    _buildProductionInventoryCard(data),
                    const SizedBox(height: 16),

                    // 5. Recovery Strategy Comparison (What-If)
                    _buildStrategyComparisonCard(data),
                    const SizedBox(height: 16),

                    // 6. Linked Work Orders & Governance Actions
                    _buildGovernanceCard(data),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildWorkflowStepper(Map<String, dynamic>? data) {
    final workflow = data?['workflow_run'] as Map<String, dynamic>?;
    final currentStage = workflow?['current_stage'] ?? 'NEW_INCIDENT';

    final stages = [
      {'key': 'NEW_INCIDENT', 'label': 'Detected'},
      {'key': 'AI_INVESTIGATING', 'label': 'Investigation'},
      {'key': 'COORDINATING_AGENTS', 'label': 'Coordination'},
      {'key': 'SIMULATING_STRATEGIES', 'label': 'Simulation'},
      {'key': 'AWAITING_MANAGER_APPROVAL', 'label': 'Approval'},
      {'key': 'RECOVERY_COORDINATION', 'label': 'Execution'},
      {'key': 'VERIFIED_RECOVERED', 'label': 'Verification'},
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Autonomous Workflow Lifecycle', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stages.map((s) {
              final isCurrent = currentStage == s['key'];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isCurrent ? TexoraColors.primaryLight : TexoraColors.cardBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isCurrent ? TexoraColors.primaryLightBorder : TexoraColors.cardBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCurrent ? Icons.play_circle_fill_rounded : Icons.check_circle_outline_rounded,
                      color: isCurrent ? TexoraColors.primaryBlue : TexoraColors.textMuted,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      s['label']!,
                      style: TextStyle(
                        color: isCurrent ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                        fontSize: 11,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineHealthCard(Map<String, dynamic>? data) {
    final machine = data?['machine'] as Map<String, dynamic>?;
    final tel = machine?['latest_telemetry'] as Map<String, dynamic>?;
    final limits = machine?['operating_limits'] as Map<String, dynamic>?;

    final vib = tel?['vibration_mms']?.toString() ?? 'N/A';
    final temp = tel?['temperature_c']?.toString() ?? 'N/A';
    final speed = tel?['speed_rpm']?.toString() ?? 'N/A';
    final maxVib = limits?['max_vibration_mms']?.toString() ?? '4.5';
    final maxTemp = limits?['max_temp_c']?.toString() ?? '85.0';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Machine Operating State & Sensors', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: TexoraColors.successBg, borderRadius: BorderRadius.circular(4), border: Border.all(color: TexoraColors.successBorder)),
                child: const Text('TELEMETRY FRESH', style: TextStyle(color: TexoraColors.successText, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSensorTile('Vibration', '$vib mm/s', 'Max: $maxVib mm/s', const Color(0xFFEF4444)),
              const SizedBox(width: 10),
              _buildSensorTile('Temperature', '$temp °C', 'Max: $maxTemp °C', const Color(0xFFF97316)),
              const SizedBox(width: 10),
              _buildSensorTile('Speed RPM', '$speed rpm', 'Rated: 650 rpm', TexoraColors.primaryBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorTile(String label, String value, String limit, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: TexoraColors.cardBg, borderRadius: BorderRadius.circular(6), border: Border.all(color: TexoraColors.cardBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(limit, style: const TextStyle(color: TexoraColors.textMuted, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildAiInvestigationCard(Map<String, dynamic>? data) {
    final rec = data?['recommendation_payload'] as Map<String, dynamic>?;
    final hypotheses = rec?['ai_hypotheses'] as Map<String, dynamic>?;
    final provider = hypotheses?['provider'] ?? rec?['ai_provider'] ?? 'gemini-3.5-flash';
    final rootCause = hypotheses?['root_cause_analysis'] ?? _selectedIncident?.rootCauseHypothesis ?? 'Analyzing sensor signatures...';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA855F7).withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.psychology_rounded, color: Color(0xFFA855F7), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI Diagnostic Findings',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFA855F7).withAlpha(20), borderRadius: BorderRadius.circular(4)),
                child: Text(provider.toString().toUpperCase(), style: const TextStyle(color: Color(0xFF9333EA), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            rootCause.toString().isNotEmpty ? rootCause.toString() : 'Diagnostic investigation in progress by AI specialist fleet.',
            style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildProductionInventoryCard(Map<String, dynamic>? data) {
    final rec = data?['recommendation_payload'] as Map<String, dynamic>?;
    final multiAgent = rec?['multi_agent_assessments'] as Map<String, dynamic>?;
    final prod = multiAgent?['production'] as Map<String, dynamic>?;
    final inv = multiAgent?['inventory'] as Map<String, dynamic>?;

    final inStockList = inv?['in_stock_parts'] as List?;
    final parts = (inStockList != null && inStockList.isNotEmpty)
        ? inStockList.join(', ')
        : 'No specific replacement parts allocated yet';
    final altList = prod?['eligible_alternates'] as List?;
    final alternates = (altList != null && altList.isNotEmpty)
        ? altList.join(', ')
        : 'No alternate machines designated';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Operational Constraints & Multi-Agent Findings', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildInfoRow('Spare Parts Stock:', parts, Icons.inventory_2_outlined),
          const SizedBox(height: 6),
          _buildInfoRow('Eligible Alternate Machines:', alternates, Icons.alt_route_rounded),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: TexoraColors.primaryBlue, size: 14),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(value, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11)),
        ),
      ],
    );
  }

  Widget _buildStrategyComparisonCard(Map<String, dynamic>? data) {
    final rec = data?['recommendation_payload'] as Map<String, dynamic>?;
    final sim = rec?['deterministic_simulation'] as Map<String, dynamic>?;
    final strategies = sim?['strategies_evaluated'] as List? ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Digital Twin Recovery Strategy Evaluation', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (strategies.isEmpty)
            const Text('No strategy simulations recorded yet.', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11))
          else
            Column(
              children: strategies.map((s) {
                final sMap = s as Map<String, dynamic>;
                final code = sMap['code'] ?? '';
                final name = sMap['name'] ?? '';
                final rank = sMap['rank'] ?? 1;
                final hours = sMap['estimated_downtime_hours'] ?? 1.5;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: TexoraColors.cardBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: rank == 1 ? TexoraColors.successText : TexoraColors.cardBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(code, style: const TextStyle(color: TexoraColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                              if (rank == 1) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: TexoraColors.successBg, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('RECOMMENDED', style: TextStyle(color: TexoraColors.successText, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(name, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10)),
                        ],
                      ),
                      Text('Est: $hours hrs', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildGovernanceCard(Map<String, dynamic>? data) {
    final approvals = data?['approval_requests'] as List? ?? [];
    final pending = approvals.where((a) => a['status'] == 'PENDING').toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TexoraColors.primaryLightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Manager Governance & Approvals', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
              if (pending.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: TexoraColors.criticalBg, borderRadius: BorderRadius.circular(4)),
                  child: Text('${pending.length} ACTION REQUIRED', style: const TextStyle(color: TexoraColors.criticalText, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (pending.isEmpty)
            const Text('No pending authorization requests for this incident.', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11))
          else
            ElevatedButton.icon(
              onPressed: () {
                if (widget.onOpenApproval != null) {
                  widget.onOpenApproval!(5); // Navigate to dedicated Approval Center
                }
              },
              icon: const Icon(Icons.gavel_rounded, size: 14),
              label: const Text('Review & Authorize in Approval Center ➔', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: TexoraColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
        ],
      ),
    );
  }
}
