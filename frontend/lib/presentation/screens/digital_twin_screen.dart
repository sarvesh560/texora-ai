import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/services/api_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/factory_flow_view.dart';

enum DigitalTwinViewMode { flowView, gridView }

class DigitalTwinScreen extends StatefulWidget {
  final Function(String machineCode)? onNavigateToWhatIfWithMachine;
  final DigitalTwinSnapshotModel? initialSnapshot;
  final ApiService? apiService;
  final DigitalTwinViewMode? initialViewMode;

  const DigitalTwinScreen({
    super.key,
    this.onNavigateToWhatIfWithMachine,
    this.initialSnapshot,
    this.apiService,
    this.initialViewMode,
  });

  @override
  State<DigitalTwinScreen> createState() => _DigitalTwinScreenState();
}

class _DigitalTwinScreenState extends State<DigitalTwinScreen> {
  late final ApiService _apiService;
  DigitalTwinSnapshotModel? _snapshot;
  MachineTwinModel? _selectedMachine;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedDepartmentFilter = 'ALL';
  late DigitalTwinViewMode _viewMode;
  Timer? _refreshTimer;

  final Map<String, String> _departmentNames = {
    'ALL': 'All Factory Floor',
    'SPN': 'Spinning Department (7)',
    'WEV': 'Weaving Shed (6)',
    'KNT': 'Knitting Division (4)',
    'DYE': 'Dyeing & Processing (4)',
    'FIN': 'Finishing & Inspection (4)',
  };

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _viewMode = widget.initialViewMode ?? DigitalTwinViewMode.flowView;
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot;
      _isLoading = false;
    } else {
      _loadSnapshot();
      _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadSnapshot(silent: true));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSnapshot({bool silent = false, bool refresh = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final snap = await _apiService.fetchDigitalTwinSnapshot(refresh: refresh);
      if (mounted) {
        setState(() {
          _snapshot = snap;
          _isLoading = false;
          if (snap == null) {
            _errorMessage = 'Failed to load factory digital twin snapshot from backend.';
          } else if (_selectedMachine != null) {
            _selectedMachine = snap.machineStates.firstWhere(
              (m) => m.code == _selectedMachine!.code,
              orElse: () => _selectedMachine!,
            );
          }
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

  Color _getStateColor(String state) {
    switch (state.toUpperCase()) {
      case 'RUNNING':
        return TexoraColors.success;
      case 'WARNING':
        return TexoraColors.warning;
      case 'CRITICAL':
        return TexoraColors.critical;
      case 'UNDER_MAINTENANCE':
        return TexoraColors.info;
      case 'IDLE':
        return TexoraColors.textMuted;
      case 'OFFLINE':
        return TexoraColors.textSecondary;
      case 'UNKNOWN':
      default:
        return TexoraColors.textMuted;
    }
  }

  IconData _getStateIcon(String state) {
    switch (state.toUpperCase()) {
      case 'RUNNING':
        return Icons.check_circle_outline_rounded;
      case 'WARNING':
        return Icons.warning_amber_rounded;
      case 'CRITICAL':
        return Icons.error_outline_rounded;
      case 'UNDER_MAINTENANCE':
        return Icons.build_circle_outlined;
      case 'IDLE':
        return Icons.pause_circle_outline_rounded;
      case 'OFFLINE':
        return Icons.power_settings_new_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateDistribution = _snapshot?.operationalSummary['state_distribution'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: Row(
        children: [
          // Main Factory Floor & Department View
          Expanded(
            flex: 7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildMetricCards(stateDistribution),
                Expanded(
                  child: _isLoading && _snapshot == null
                      ? const Center(child: CircularProgressIndicator(color: TexoraColors.primaryBlue))
                      : _errorMessage != null && _snapshot == null
                          ? _buildErrorView()
                          : _viewMode == DigitalTwinViewMode.flowView
                              ? FactoryFlowView(
                                  snapshot: _snapshot,
                                  selectedDepartment: _selectedDepartmentFilter,
                                  selectedMachine: _selectedMachine,
                                  onSelectDepartment: (dept) {
                                    setState(() {
                                      _selectedDepartmentFilter = dept;
                                    });
                                  },
                                  onSelectMachine: (machine) {
                                    setState(() {
                                      _selectedMachine = machine;
                                    });
                                  },
                                  onNavigateToWhatIfWithMachine: widget.onNavigateToWhatIfWithMachine,
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDepartmentFilterBar(),
                                    Expanded(child: _buildFactoryFloorLayout()),
                                  ],
                                ),
                ),
              ],
            ),
          ),

          // Machine Inspector / Detail Side Panel
          if (_selectedMachine != null)
            Container(
              width: 380,
              decoration: const BoxDecoration(
                color: TexoraColors.cardBg,
                border: Border(
                  left: BorderSide(color: TexoraColors.cardBorder, width: 1.5),
                ),
              ),
              child: _buildMachineDetailPanel(_selectedMachine!),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1100;
          final titleWidget = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TexoraColors.primaryBlue.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: TexoraColors.primaryBlue.withAlpha(80)),
                ),
                child: const Icon(
                  Icons.precision_manufacturing_rounded,
                  color: TexoraColors.primaryBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        const Text(
                          'Factory Digital Twin Command Center',
                          style: TextStyle(
                            color: TexoraColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: TexoraColors.successBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: TexoraColors.successBorder),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hub_rounded, color: TexoraColors.successText, size: 12),
                              SizedBox(width: 4),
                              Text(
                                'SIMULATED FACTORY DIGITAL TWIN',
                                style: TextStyle(
                                  color: TexoraColors.successText,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _snapshot != null
                          ? '${_snapshot!.factoryCode} — ${_snapshot!.factoryName} • Real-time Topology'
                          : 'Loading real-time plant telemetry...',
                      style: const TextStyle(
                        color: TexoraColors.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );

          final controlsWidget = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // View Mode Selector
                Container(
                  decoration: BoxDecoration(
                    color: TexoraColors.inputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: TexoraColors.cardBorder),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildViewModeButton(
                        mode: DigitalTwinViewMode.flowView,
                        label: 'Process Flow',
                        icon: Icons.account_tree_rounded,
                      ),
                      _buildViewModeButton(
                        mode: DigitalTwinViewMode.gridView,
                        label: 'Shop Floor Grid',
                        icon: Icons.grid_view_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Refresh Button
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _loadSnapshot(refresh: true),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh Snapshot'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TexoraColors.textPrimary,
                    backgroundColor: TexoraColors.cardBg,
                    side: const BorderSide(color: TexoraColors.cardBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleWidget,
                const SizedBox(height: 12),
                controlsWidget,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: titleWidget),
              const SizedBox(width: 16),
              controlsWidget,
            ],
          );
        },
      ),
    );
  }

  Widget _buildViewModeButton({
    required DigitalTwinViewMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? TexoraColors.cardBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? TexoraColors.textPrimary : TexoraColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCards(Map<String, dynamic> stateDist) {
    final running = stateDist['RUNNING'] ?? 0;
    final warning = stateDist['WARNING'] ?? 0;
    final critical = stateDist['CRITICAL'] ?? 0;
    final maintenance = stateDist['UNDER_MAINTENANCE'] ?? 0;
    final unknown = stateDist['UNKNOWN'] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          int count = constraints.maxWidth < 650 ? 2 : (constraints.maxWidth < 1100 ? 3 : 5);
          return GridView.count(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: count == 2 ? 1.7 : (count == 3 ? 1.55 : 1.45),
            children: [
              MetricCard(
                title: 'OPERATIONAL',
                value: '$running',
                subtitle: 'Active Production',
                icon: Icons.check_circle_outline_rounded,
                accentColor: TexoraColors.success,
                backgroundColor: TexoraColors.cardBg,
                borderColor: TexoraColors.cardBorder,
                titleColor: TexoraColors.textMuted,
                subtitleColor: TexoraColors.textSecondary,
              ),
              MetricCard(
                title: 'WARNING',
                value: '$warning',
                subtitle: 'Potential Risk',
                icon: Icons.warning_amber_rounded,
                accentColor: TexoraColors.warning,
                backgroundColor: TexoraColors.cardBg,
                borderColor: TexoraColors.cardBorder,
                titleColor: TexoraColors.textMuted,
                subtitleColor: TexoraColors.textSecondary,
              ),
              MetricCard(
                title: 'CRITICAL ALERTS',
                value: '$critical',
                subtitle: 'Action Required',
                icon: Icons.error_outline_rounded,
                accentColor: TexoraColors.critical,
                backgroundColor: TexoraColors.cardBg,
                borderColor: TexoraColors.cardBorder,
                titleColor: TexoraColors.textMuted,
                subtitleColor: TexoraColors.textSecondary,
              ),
              MetricCard(
                title: 'MAINTENANCE',
                value: '$maintenance',
                subtitle: 'Under Service',
                icon: Icons.build_circle_outlined,
                accentColor: TexoraColors.info,
                backgroundColor: TexoraColors.cardBg,
                borderColor: TexoraColors.cardBorder,
                titleColor: TexoraColors.textMuted,
                subtitleColor: TexoraColors.textSecondary,
              ),
              MetricCard(
                title: 'STANDBY / IDLE',
                value: '$unknown',
                subtitle: 'Headroom Reserve',
                icon: Icons.pause_circle_outline_rounded,
                accentColor: TexoraColors.textMuted,
                backgroundColor: TexoraColors.cardBg,
                borderColor: TexoraColors.cardBorder,
                titleColor: TexoraColors.textMuted,
                subtitleColor: TexoraColors.textSecondary,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDepartmentFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _departmentNames.entries.map((entry) {
            final isSelected = _selectedDepartmentFilter == entry.key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: isSelected,
                label: Text(entry.value),
                labelStyle: TextStyle(
                  color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
                backgroundColor: TexoraColors.workspaceBg,
                selectedColor: TexoraColors.sidebarActivePill,
                side: BorderSide(
                  color: isSelected ? TexoraColors.primaryBlue : TexoraColors.cardBorder,
                ),
                onSelected: (selected) {
                  setState(() {
                    _selectedDepartmentFilter = entry.key;
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFactoryFloorLayout() {
    final machines = _snapshot?.machineStates ?? [];
    final filtered = _selectedDepartmentFilter == 'ALL'
        ? machines
        : machines.where((m) => m.departmentCode == _selectedDepartmentFilter).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox_rounded, color: TexoraColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(
              'No machines found in ${_departmentNames[_selectedDepartmentFilter] ?? _selectedDepartmentFilter}',
              style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth < 600 ? 1 : (constraints.maxWidth < 1000 ? 2 : 3);
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.45,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            return _buildMachineGridCard(filtered[index]);
          },
        );
      },
    );
  }

  Widget _buildMachineGridCard(MachineTwinModel machine) {
    final isSelected = _selectedMachine?.code == machine.code;
    final stateColor = _getStateColor(machine.twinPresentationState);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMachine = machine;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? TexoraColors.primaryBlue : TexoraColors.cardBorder,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? TexoraColors.primaryBlue.withAlpha(25) : const Color(0x05000000),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: stateColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(_getStateIcon(machine.twinPresentationState), color: stateColor, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          machine.code,
                          style: const TextStyle(
                            color: TexoraColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: stateColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: stateColor.withAlpha(80)),
                    ),
                    child: Text(
                      machine.twinPresentationState,
                      style: TextStyle(
                        color: stateColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),

            // Machine Name & Department
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  machine.name,
                  style: const TextStyle(
                    color: TexoraColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  machine.departmentName,
                  style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),

            // Health Progress
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (machine.healthScore / 100.0).clamp(0.0, 1.0),
                      backgroundColor: TexoraColors.inputBg,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        machine.healthScore > 80
                            ? TexoraColors.success
                            : (machine.healthScore > 50 ? TexoraColors.warning : TexoraColors.critical),
                      ),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${machine.healthScore.toInt()}%',
                  style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineDetailPanel(MachineTwinModel machine) {
    final stateColor = _getStateColor(machine.twinPresentationState);
    final tel = machine.latestTelemetry;
    final limits = machine.operatingLimits;
    final prod = machine.productionAssignment;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: TexoraColors.cardBg,
            border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: stateColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_getStateIcon(machine.twinPresentationState), color: stateColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            machine.code,
                            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            machine.name,
                            style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedMachine = null;
                  });
                },
                icon: const Icon(Icons.close_rounded, color: TexoraColors.textMuted),
                tooltip: 'Close Inspector',
              ),
            ],
          ),
        ),

        // Scrollable Inspector Details
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Presentation State & Reason Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: stateColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: stateColor.withAlpha(80)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: stateColor, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'TWIN PRESENTATION STATE: ${machine.twinPresentationState}',
                            style: TextStyle(color: stateColor, fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      machine.stateReason,
                      style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Operational Telemetry Section
              _buildSectionTitle('LATEST TELEMETRY SENSORS', Icons.speed_rounded),
              if (tel != null) ...[
                _buildDetailRow('Temperature', '${(tel['temperature_c'] ?? 0.0).toStringAsFixed(1)} °C', Icons.thermostat_rounded),
                _buildDetailRow('Vibration Amplitude', '${(tel['vibration_mms'] ?? 0.0).toStringAsFixed(2)} mm/s RMS', Icons.vibration_rounded),
                _buildDetailRow('Operating Speed', '${(tel['speed_rpm'] ?? 0).toInt()} RPM', Icons.rotate_right_rounded),
                _buildDetailRow('Active Electrical Power', '${(tel['power_kw'] ?? 0.0).toStringAsFixed(1)} kW', Icons.bolt_rounded),
                _buildDetailRow('Motor Utilization', '${(tel['utilization_pct'] ?? 0.0).toStringAsFixed(1)} %', Icons.pie_chart_outline_rounded),
                _buildDetailRow('Timestamp', tel['timestamp']?.toString() ?? 'N/A', Icons.access_time_rounded),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No telemetry available for this machine.', style: TextStyle(color: TexoraColors.textMuted, fontSize: 12)),
                ),
              const SizedBox(height: 16),

              // Operating Limits
              if (limits != null) ...[
                _buildSectionTitle('OPERATING THRESHOLD LIMITS', Icons.tune_rounded),
                _buildDetailRow('Max Temperature', '${limits['max_temp_c']} °C', Icons.thermostat_rounded),
                _buildDetailRow('Warning Temp', '${limits['warning_temp_c']} °C', Icons.warning_amber_rounded),
                _buildDetailRow('Max Vibration', '${limits['max_vibration_mms']} mm/s', Icons.vibration_rounded),
                _buildDetailRow('Warning Vibration', '${limits['warning_vibration_mms']} mm/s', Icons.warning_amber_rounded),
                const SizedBox(height: 16),
              ],

              // Production Assignment
              _buildSectionTitle('ACTIVE PRODUCTION ASSIGNMENT', Icons.inventory_2_rounded),
              if (prod != null) ...[
                _buildDetailRow('Production Order', prod['order_number']?.toString() ?? 'N/A', Icons.tag_rounded),
                _buildDetailRow('Client', prod['client_name']?.toString() ?? 'N/A', Icons.business_rounded),
                _buildDetailRow('Fabric / Spec', prod['fabric_spec']?.toString() ?? 'N/A', Icons.texture_rounded),
                _buildDetailRow('Target Quantity', '${prod['planned_quantity']} ${prod['unit']}', Icons.numbers_rounded),
                _buildDetailRow('Batch Status', prod['status']?.toString() ?? 'N/A', Icons.flag_rounded),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No active production order attached.', style: TextStyle(color: TexoraColors.textMuted, fontSize: 12)),
                ),
              const SizedBox(height: 16),

              // Compatible Alternate Machines
              _buildSectionTitle('COMPATIBLE ALTERNATE MACHINES', Icons.swap_horiz_rounded),
              if (machine.compatibleAlternates.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: machine.compatibleAlternates.map((alt) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: TexoraColors.sidebarActivePill,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: TexoraColors.cardBorder),
                      ),
                      child: Text(
                        alt,
                        style: const TextStyle(color: TexoraColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                )
              else
                const Text('No compatible alternate machines in tier.', style: TextStyle(color: TexoraColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: TexoraColors.textMuted, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: TexoraColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(icon, color: TexoraColors.textMuted, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: TexoraColors.critical, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadSnapshot(refresh: true),
            style: ElevatedButton.styleFrom(backgroundColor: TexoraColors.primaryBlue),
            child: const Text('Retry Connection'),
          ),
        ],
      ),
    );
  }
}
