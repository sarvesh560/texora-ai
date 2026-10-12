import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/digital_twin_models.dart';
import '../../data/services/api_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/factory_flow_view.dart';

enum DigitalTwinViewMode { flowView, gridView }

class DigitalTwinScreen extends StatefulWidget {
  final Function(String machineCode)? onNavigateToWhatIfWithMachine;

  const DigitalTwinScreen({
    super.key,
    this.onNavigateToWhatIfWithMachine,
  });

  @override
  State<DigitalTwinScreen> createState() => _DigitalTwinScreenState();
}

class _DigitalTwinScreenState extends State<DigitalTwinScreen> {
  final ApiService _apiService = ApiService();
  DigitalTwinSnapshotModel? _snapshot;
  MachineTwinModel? _selectedMachine;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedDepartmentFilter = 'ALL';
  DigitalTwinViewMode _viewMode = DigitalTwinViewMode.flowView;
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
    _loadSnapshot();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadSnapshot(silent: true));
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
            // Keep selected machine fresh
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
        return AppColors.successGreen;
      case 'WARNING':
        return AppColors.warningOrange;
      case 'CRITICAL':
        return AppColors.errorRed;
      case 'UNDER_MAINTENANCE':
        return AppColors.primaryBlueLight;
      case 'IDLE':
        return const Color(0xFF94A3B8);
      case 'OFFLINE':
        return const Color(0xFF64748B);
      case 'UNKNOWN':
      default:
        return const Color(0xFF475569);
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
      backgroundColor: const Color(0xFF0A0F1D), // Dark Navy Command Center Background
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
                      ? const Center(child: CircularProgressIndicator())
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
                color: Color(0xFF0F172A),
                border: Border(
                  left: BorderSide(color: Color(0xFF1E293B), width: 1.5),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withAlpha(38),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primaryBlueLight.withAlpha(100)),
            ),
            child: const Icon(
              Icons.precision_manufacturing_rounded,
              color: AppColors.primaryBlueLight,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Factory Digital Twin Command Center',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
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
                            'SIMULATED FACTORY DIGITAL TWIN',
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
                  'Live operational topology across 25 textile machines in 5 departments — PSG Coimbatore Expo Platform',
                  style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
                ),
              ],
            ),
          ),
          // View Switcher Buttons
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewToggleButton(
                  mode: DigitalTwinViewMode.flowView,
                  icon: Icons.account_tree_rounded,
                  label: 'Factory Flow View',
                ),
                _buildViewToggleButton(
                  mode: DigitalTwinViewMode.gridView,
                  icon: Icons.grid_view_rounded,
                  label: 'Machine Grid View',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _loadSnapshot(refresh: true),
            icon: const Icon(Icons.sync_rounded, size: 16),
            label: const Text('Refresh Snapshot'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              elevation: 0,
              side: const BorderSide(color: Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton({
    required DigitalTwinViewMode mode,
    required IconData icon,
    required String label,
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
          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCards(Map<String, dynamic> stateDistribution) {
    int running = stateDistribution['RUNNING'] ?? 0;
    int warning = stateDistribution['WARNING'] ?? 0;
    int critical = stateDistribution['CRITICAL'] ?? 0;
    int maintenance = stateDistribution['UNDER_MAINTENANCE'] ?? 0;
    int unknown = stateDistribution['UNKNOWN'] ?? 0;
    int total = _snapshot?.totalMachines ?? 25;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          Expanded(
            child: MetricCard(
              title: 'Total Active Machines',
              value: '$total Assets',
              icon: Icons.factory_rounded,
              accentColor: AppColors.primaryBlueLight,
              backgroundColor: const Color(0xFF0F172A),
              borderColor: const Color(0xFF1E293B),
              titleColor: const Color(0xFF94A3B8),
              valueColor: Colors.white,
              subtitleColor: const Color(0xFF64748B),
              subtitle: '5 Departments Monitored',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Nominal Running',
              value: '$running',
              icon: Icons.check_circle_rounded,
              accentColor: AppColors.successGreen,
              backgroundColor: const Color(0xFF0F172A),
              borderColor: const Color(0xFF1E293B),
              titleColor: const Color(0xFF94A3B8),
              valueColor: Colors.white,
              subtitleColor: const Color(0xFF64748B),
              subtitle: 'Within Operating Envelopes',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Warning Excursions',
              value: '$warning',
              icon: Icons.warning_rounded,
              accentColor: AppColors.warningOrange,
              backgroundColor: const Color(0xFF0F172A),
              borderColor: const Color(0xFF1E293B),
              titleColor: const Color(0xFF94A3B8),
              valueColor: Colors.white,
              subtitleColor: const Color(0xFF64748B),
              subtitle: 'Minor Telemetry Deviation',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Critical & Maintenance',
              value: '${critical + maintenance}',
              icon: Icons.build_circle_rounded,
              accentColor: (critical + maintenance) > 0 ? AppColors.errorRed : AppColors.successGreen,
              backgroundColor: const Color(0xFF0F172A),
              borderColor: const Color(0xFF1E293B),
              titleColor: const Color(0xFF94A3B8),
              valueColor: Colors.white,
              subtitleColor: const Color(0xFF64748B),
              subtitle: '$critical Critical / $maintenance Work Orders',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetricCard(
              title: 'Missing / Stale Readings',
              value: '$unknown',
              icon: Icons.sensors_off_rounded,
              accentColor: unknown > 0 ? const Color(0xFF94A3B8) : AppColors.successGreen,
              backgroundColor: const Color(0xFF0F172A),
              borderColor: const Color(0xFF1E293B),
              titleColor: const Color(0xFF94A3B8),
              valueColor: Colors.white,
              subtitleColor: const Color(0xFF64748B),
              subtitle: unknown > 0 ? 'Telemetry Stale (>180s - Simulator Paused)' : 'All Telemetry Fresh',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                backgroundColor: const Color(0xFF0F172A),
                selectedColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected ? AppColors.primaryBlueLight : const Color(0xFF1E293B),
                  ),
                ),
                onSelected: (_) {
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
    final filteredMachines = _selectedDepartmentFilter == 'ALL'
        ? machines
        : machines.where((m) => m.departmentCode == _selectedDepartmentFilter).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                Row(
                  children: [
                    const Icon(Icons.grid_view_rounded, color: AppColors.primaryBlueLight, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Interactive Factory Floor Layout (${filteredMachines.length} Machines)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildLegendItem('Running', AppColors.successGreen),
                    const SizedBox(width: 12),
                    _buildLegendItem('Warning', AppColors.warningOrange),
                    const SizedBox(width: 12),
                    _buildLegendItem('Critical', AppColors.errorRed),
                    const SizedBox(width: 12),
                    _buildLegendItem('Maintenance', AppColors.primaryBlueLight),
                    const SizedBox(width: 12),
                    _buildLegendItem('Stale/Unknown', const Color(0xFF475569)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisExtent: 180,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                ),
                itemCount: filteredMachines.length,
                itemBuilder: (context, index) {
                  final machine = filteredMachines[index];
                  final isSelected = _selectedMachine?.code == machine.code;
                  return _buildMachineTile(machine, isSelected);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildMachineTile(MachineTwinModel machine, bool isSelected) {
    final stateColor = _getStateColor(machine.twinPresentationState);
    final stateIcon = _getStateIcon(machine.twinPresentationState);
    final tel = machine.latestTelemetry;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedMachine = machine;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0B132B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlueLight
                : stateColor.withAlpha(machine.twinPresentationState == 'RUNNING' ? 50 : 180),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withAlpha(40),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row: Code + Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(stateIcon, color: stateColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      machine.code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: stateColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    machine.twinPresentationState,
                    style: TextStyle(
                      color: stateColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
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
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${machine.departmentName} (${machine.floorLocation})',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                ),
              ],
            ),

            // Telemetry Chips
            if (tel != null)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMicroGauge(
                      'RPM',
                      '${(tel['speed_rpm'] ?? machine.ratedSpeedRpm).toInt()}',
                      const Color(0xFF38BDF8),
                    ),
                    _buildMicroGauge(
                      'TEMP',
                      '${(tel['temperature_c'] ?? 0.0).toStringAsFixed(1)}°C',
                      (tel['temperature_c'] ?? 0.0) > 75.0 ? AppColors.errorRed : const Color(0xFF10B981),
                    ),
                    _buildMicroGauge(
                      'VIB',
                      '${(tel['vibration_mms'] ?? 0.0).toStringAsFixed(1)}',
                      (tel['vibration_mms'] ?? 0.0) > 4.0 ? AppColors.warningOrange : const Color(0xFF10B981),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withAlpha(100),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text(
                    'No Telemetry Readings',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                  ),
                ),
              ),

            // Health Bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (machine.healthScore / 100.0).clamp(0.0, 1.0),
                      backgroundColor: const Color(0xFF1E293B),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        machine.healthScore > 80
                            ? AppColors.successGreen
                            : machine.healthScore > 50
                                ? AppColors.warningOrange
                                : AppColors.errorRed,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${machine.healthScore.toInt()}%',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicroGauge(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
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
            color: Color(0xFF1E293B),
            border: Border(bottom: BorderSide(color: Color(0xFF334155))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: stateColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_getStateIcon(machine.twinPresentationState), color: stateColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        machine.code,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        machine.name,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedMachine = null;
                  });
                },
                icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
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
                  color: stateColor.withAlpha(20),
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
                        Text(
                          'TWIN PRESENTATION STATE: ${machine.twinPresentationState}',
                          style: TextStyle(color: stateColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      machine.stateReason,
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
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
                  child: Text('No telemetry available for this machine.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
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
                  child: Text('No active production order attached.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        alt,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                )
              else
                const Text('No compatible alternate machines in tier.', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              const SizedBox(height: 24),

              // What-If Quick Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (widget.onNavigateToWhatIfWithMachine != null) {
                      widget.onNavigateToWhatIfWithMachine!(machine.code);
                    }
                  },
                  icon: const Icon(Icons.science_rounded, size: 18),
                  label: Text('Simulate What-If Outage on ${machine.code}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
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
          Icon(icon, color: const Color(0xFF64748B), size: 14),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
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
          Row(
            children: [
              Icon(icon, color: const Color(0xFF475569), size: 14),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            ],
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
          const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 48),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Unknown error occurred',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadSnapshot(refresh: true),
            child: const Text('Retry Connection'),
          ),
        ],
      ),
    );
  }
}
