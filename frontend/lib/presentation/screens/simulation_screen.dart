import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/simulation_model.dart';
import '../../data/services/api_service.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final ApiService _apiService = ApiService();
  SimulationSummaryModel? _summary;
  bool _isLoading = false;
  bool _isActionInProgress = false;
  String? _statusMessage;
  Timer? _pollingTimer;
  bool _autoRefresh = true;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_autoRefresh && mounted) {
        _fetchSummary(silent: true);
      }
    });
  }

  Future<void> _fetchSummary({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }

    final summary = await _apiService.fetchSimulationSummary();

    if (mounted) {
      setState(() {
        _summary = summary;
        if (!silent) _isLoading = false;
      });
    }
  }

  Future<void> _startSimulation() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.startSimulation(speedMultiplier: 1.0, intervalSeconds: 3.0);
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Simulation started successfully' : 'Failed to start simulation';
      });
      _fetchSummary();
    }
  }

  Future<void> _pauseSimulation() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.pauseSimulation();
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Simulation paused' : 'Failed to pause simulation';
      });
      _fetchSummary();
    }
  }

  Future<void> _resumeSimulation() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.resumeSimulation();
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Simulation resumed' : 'Failed to resume simulation';
      });
      _fetchSummary();
    }
  }

  Future<void> _stopSimulation() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.stopSimulation();
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Simulation stopped' : 'Failed to stop simulation';
      });
      _fetchSummary();
    }
  }

  Future<void> _triggerTick() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.triggerManualTick();
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Single simulation tick executed' : 'Failed to execute tick';
      });
      _fetchSummary();
    }
  }

  Future<void> _injectScenario(String type, String machineCode, String label) async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.injectScenario(
      scenarioType: type,
      machineCode: machineCode,
      description: 'Demo injected: $label',
    );
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Injected $label' : 'Failed to inject scenario';
      });
      _fetchSummary();
    }
  }

  Future<void> _clearScenarios() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.clearScenarios();
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'All anomaly scenarios cleared' : 'Failed to clear scenarios';
      });
      _fetchSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          if (_statusMessage != null) _buildStatusBar(),
          Expanded(
            child: _isLoading && _summary == null
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final state = _summary?.state;
    final isRunning = state?.isRunning ?? false;
    final isPaused = state?.isPaused ?? false;

    Color badgeBg;
    Color badgeText;
    String statusText;

    if (isRunning && !isPaused) {
      badgeBg = AppColors.successGreen.withAlpha(35);
      badgeText = AppColors.successGreen;
      statusText = 'SIMULATION RUNNING';
    } else if (isPaused) {
      badgeBg = AppColors.warningOrange.withAlpha(35);
      badgeText = AppColors.warningOrange;
      statusText = 'SIMULATION PAUSED';
    } else {
      badgeBg = const Color(0xFF64748B).withAlpha(35);
      badgeText = const Color(0xFF64748B);
      statusText = 'SIMULATION STOPPED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Factory Simulation Engine',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: badgeText.withAlpha(100)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: badgeText,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: badgeText,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
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
                'Continuous backend simulation generating realistic textile telemetry and production physics',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
          // Action Controls
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!isRunning || isPaused)
                ElevatedButton.icon(
                  onPressed: _isActionInProgress ? null : (isPaused ? _resumeSimulation : _startSimulation),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(isPaused ? 'Resume' : 'Start Engine'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              if (isRunning && !isPaused)
                OutlinedButton.icon(
                  onPressed: _isActionInProgress ? null : _pauseSimulation,
                  icon: const Icon(Icons.pause_rounded, size: 18),
                  label: const Text('Pause'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.warningOrange),
                ),
              if (isRunning || isPaused)
                OutlinedButton.icon(
                  onPressed: _isActionInProgress ? null : _stopSimulation,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.errorRed),
                ),
              OutlinedButton.icon(
                onPressed: _isActionInProgress ? null : _triggerTick,
                icon: const Icon(Icons.skip_next_rounded, size: 18),
                label: const Text('Step Tick'),
              ),
              IconButton(
                onPressed: _fetchSummary,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Data',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      width: double.infinity,
      color: AppColors.primaryBlue.withAlpha(20),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.primaryBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage ?? '',
              style: const TextStyle(fontSize: 12, color: AppColors.primaryBlue, fontWeight: FontWeight.w500),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _statusMessage = null),
            child: const Icon(Icons.close, size: 14, color: AppColors.primaryBlue),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final summary = _summary;
    if (summary == null) {
      return const Center(child: Text('No simulation data available. Ensure backend is running.'));
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildMetricCards(summary),
        const SizedBox(height: 20),
        _buildScenarioControlPanel(summary),
        const SizedBox(height: 24),
        _buildDepartmentSection(summary),
        const SizedBox(height: 24),
        _buildMachineTelemetryGrid(summary),
      ],
    );
  }

  Widget _buildMetricCards(SimulationSummaryModel summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 48) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'LIVE MACHINES',
              value: '${summary.totalMachines} Assets',
              subtitle: '${summary.statusBreakdown['OPERATIONAL'] ?? 0} Normal | ${summary.statusBreakdown['WARNING'] ?? 0} Warning',
              icon: Icons.precision_manufacturing_rounded,
              iconColor: AppColors.primaryBlue,
              width: cardWidth.clamp(200.0, 320.0),
            ),
            _buildStatCard(
              title: 'TOTAL POWER DRAW',
              value: '${summary.totalPowerKw.toStringAsFixed(1)} kW',
              subtitle: 'Active Instantaneous Load',
              icon: Icons.electric_bolt_rounded,
              iconColor: AppColors.warningOrange,
              width: cardWidth.clamp(200.0, 320.0),
            ),
            _buildStatCard(
              title: 'SIMULATION TICKS',
              value: '${summary.state.totalTicksGenerated}',
              subtitle: 'Last: ${summary.state.lastTickAt?.substring(11, 19) ?? 'Never'}',
              icon: Icons.timeline_rounded,
              iconColor: AppColors.successGreen,
              width: cardWidth.clamp(200.0, 320.0),
            ),
            _buildStatCard(
              title: 'ACTIVE ANOMALIES',
              value: '${summary.activeScenariosCount}',
              subtitle: summary.activeScenariosCount > 0 ? 'Scenarios active' : 'All parameters nominal',
              icon: Icons.warning_amber_rounded,
              iconColor: summary.activeScenariosCount > 0 ? AppColors.errorRed : const Color(0xFF64748B),
              width: cardWidth.clamp(200.0, 320.0),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioControlPanel(SimulationSummaryModel summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              const Text(
                'Operational Scenario Injections',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyDark,
                ),
              ),
              const Spacer(),
              if (summary.activeScenariosCount > 0)
                ElevatedButton.icon(
                  onPressed: _isActionInProgress ? null : _clearScenarios,
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Clear All Injected Scenarios'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildScenarioButton(
                label: 'Weaving Loom High Vibration (WEV-AJ-02)',
                onPressed: () => _injectScenario('WEAVING_VIBRATION', 'WEV-AJ-02', 'Loom Vibration Spike'),
                color: AppColors.errorRed,
              ),
              _buildScenarioButton(
                label: 'Ring Frame Bearing Overheat (SPN-RS-03)',
                onPressed: () => _injectScenario('SPN-RS-03', 'SPN-RS-03', 'Ring Frame Thermal Overheat'),
                color: AppColors.warningOrange,
              ),
              _buildScenarioButton(
                label: 'Draft Bottleneck Slowdown (KNT-CS-01)',
                onPressed: () => _injectScenario('PRODUCTION_SLOWDOWN', 'KNT-CS-01', 'Draft Bottleneck Slowdown'),
                color: const Color(0xFF8B5CF6),
              ),
              _buildScenarioButton(
                label: 'Fabric Barre Defect Spike (QC)',
                onPressed: () => _injectScenario('QUALITY_DEFECT_SPIKE', 'KNT-CS-02', 'Quality Defect Spike'),
                color: const Color(0xFFEC4899),
              ),
              _buildScenarioButton(
                label: 'Peak Power Demand Surge (DYE)',
                onPressed: () => _injectScenario('ENERGY_SURGE', 'DYE-SF-01', 'Energy Surge'),
                color: AppColors.warningOrange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return OutlinedButton(
      onPressed: _isActionInProgress ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(120)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildDepartmentSection(SimulationSummaryModel summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Active Factory Departments (5)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 48) / 5;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: summary.departments.map((dept) {
                return Container(
                  width: cardWidth.clamp(160.0, 240.0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dept.code,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          Text(
                            '${dept.averageHealthScore.toStringAsFixed(0)}% Health',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: dept.averageHealthScore > 85 ? AppColors.successGreen : AppColors.warningOrange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dept.name,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.navyDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${dept.operationalMachines}/${dept.totalMachines} Machines Active',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMachineTelemetryGrid(SimulationSummaryModel summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Live Machine Telemetry Stream (${summary.machines.length} Equipment Assets)',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.navyDark,
              ),
            ),
            Row(
              children: [
                Checkbox(
                  value: _autoRefresh,
                  onChanged: (v) => setState(() => _autoRefresh = v ?? true),
                ),
                const Text('Live Stream (3s)', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: summary.machines.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, index) {
              final machine = summary.machines[index];
              final telem = machine.latestTelemetry;

              Color statusColor;
              if (machine.status == 'CRITICAL' || telem?.statusFlag == 'CRITICAL') {
                statusColor = AppColors.errorRed;
              } else if (machine.status == 'WARNING' || telem?.statusFlag == 'WARNING') {
                statusColor = AppColors.warningOrange;
              } else {
                statusColor = AppColors.successGreen;
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            machine.code,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navyDark),
                          ),
                          Text(
                            machine.departmentCode,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        machine.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildTelemetryValue('SPEED', telem != null ? '${telem.speedRpm} RPM' : '--'),
                    _buildTelemetryValue('TEMP', telem != null ? '${telem.temperatureC}°C' : '--'),
                    _buildTelemetryValue('VIB', telem != null ? '${telem.vibrationMms} mm/s' : '--'),
                    _buildTelemetryValue('POWER', telem != null ? '${telem.powerKw} kW' : '--'),
                    _buildTelemetryValue('UTIL', telem != null ? '${telem.utilizationPct}%' : '--'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        telem?.statusFlag ?? machine.status,
                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryValue(String label, String val) {
    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8))),
          Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navyDark)),
        ],
      ),
    );
  }
}
