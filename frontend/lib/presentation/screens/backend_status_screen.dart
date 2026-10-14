import 'package:flutter/material.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/health_status_model.dart';
import '../../data/services/api_service.dart';
import '../widgets/metric_card.dart';
import '../widgets/status_badge.dart';

class BackendStatusScreen extends StatefulWidget {
  final ApiService? apiService;
  final VoidCallback? onClose;

  const BackendStatusScreen({super.key, this.apiService, this.onClose});

  @override
  State<BackendStatusScreen> createState() => _BackendStatusScreenState();
}

class _BackendStatusScreenState extends State<BackendStatusScreen> {
  late final ApiService _apiService;
  final TextEditingController _urlController =
      TextEditingController(text: AppConfig.baseUrl);

  HealthStatusModel? _healthStatus;
  HealthStatusModel? _readinessStatus;
  SystemHealthSummaryModel? _systemHealth;
  bool _isLoading = false;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _apiService = widget.apiService ?? ApiService();
    _fetchHealthData();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _fetchHealthData() async {
    setState(() {
      _isLoading = true;
    });

    final health = await _apiService.checkHealth();
    final readiness = await _apiService.checkReadiness();
    final systemHealth = await _apiService.fetchWorkerHealth();

    if (mounted) {
      setState(() {
        _healthStatus = health;
        _readinessStatus = readiness;
        _systemHealth = systemHealth;
        _lastChecked = DateTime.now();
        _isLoading = false;
      });
    }
  }

  void _updateBaseUrl() {
    setState(() {
      AppConfig.baseUrl = _urlController.text.trim();
    });
    _fetchHealthData();
  }

  BadgeType _getBadgeTypeForStatus(String status) {
    switch (status.toUpperCase()) {
      case 'RUNNING':
      case 'CONNECTED':
      case 'CONFIGURED':
      case 'READY':
        return BadgeType.success;
      case 'DEGRADED':
      case 'RATE_LIMITED':
        return BadgeType.warning;
      case 'STOPPED':
      case 'DISCONNECTED':
      case 'ERROR':
        return BadgeType.error;
      default:
        return BadgeType.neutral;
    }
  }

  Color _getColorForStatus(String status) {
    switch (status.toUpperCase()) {
      case 'RUNNING':
      case 'CONNECTED':
      case 'CONFIGURED':
      case 'READY':
        return TexoraColors.success;
      case 'DEGRADED':
      case 'RATE_LIMITED':
        return TexoraColors.warning;
      case 'STOPPED':
      case 'DISCONNECTED':
      case 'ERROR':
        return TexoraColors.critical;
      default:
        return TexoraColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TexoraColors.workspaceBg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button if in overlay mode
            if (widget.onClose != null) ...[
              Row(
                children: [
                  TextButton.icon(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16, color: TexoraColors.primaryBlue),
                    label: const Text(
                      'Back to Factory Workspaces',
                      style: TextStyle(color: TexoraColors.primaryBlue, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Header Row
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backend Infrastructure & Worker Diagnostics',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: TexoraColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Real-time heartbeat verification across Django API, Anomaly Detector, Orchestrator, and Gemini AI Provider',
                      style: TextStyle(
                        fontSize: 13,
                        color: TexoraColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_lastChecked != null)
                      Text(
                        'Last checked: ${_lastChecked!.hour.toString().padLeft(2, '0')}:${_lastChecked!.minute.toString().padLeft(2, '0')}:${_lastChecked!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TexoraColors.textMuted,
                        ),
                      ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _fetchHealthData,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Refresh Status'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TexoraColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Health & Provider KPI Grid
            LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 4;
                if (constraints.maxWidth < 700) {
                  crossAxisCount = 1;
                } else if (constraints.maxWidth < 1100) {
                  crossAxisCount = 2;
                }

                final detector = _systemHealth?.detector;
                final orchestrator = _systemHealth?.orchestrator;
                final gemini = _systemHealth?.geminiProvider;

                return Column(
                  children: [
                    GridView.count(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: crossAxisCount == 1 ? 2.2 : 1.25,
                      children: [
                        // Django API Status Card
                        MetricCard(
                          title: 'DJANGO API STATUS',
                          value: _healthStatus == null
                              ? 'Connecting...'
                              : (_healthStatus!.isSuccess ? 'Operational' : 'Unavailable'),
                          subtitle: 'Endpoint: /api/v1/health/',
                          icon: Icons.api_rounded,
                          accentColor: _healthStatus?.isSuccess == true
                              ? TexoraColors.success
                              : TexoraColors.critical,
                          trailing: StatusBadge(
                            label: _healthStatus?.status ?? 'PENDING',
                            type: _healthStatus?.isSuccess == true
                                ? BadgeType.success
                                : (_isLoading ? BadgeType.info : BadgeType.error),
                          ),
                        ),

                        // Database Readiness Card
                        MetricCard(
                          title: 'DATABASE STATUS',
                          value: _readinessStatus == null
                              ? 'Checking...'
                              : (_readinessStatus!.isSuccess ? 'Connected' : 'Disconnected'),
                          subtitle: 'SQLite / PostgreSQL Connection',
                          icon: Icons.storage_rounded,
                          accentColor: _readinessStatus?.isSuccess == true
                              ? TexoraColors.success
                              : TexoraColors.critical,
                          trailing: StatusBadge(
                            label: _readinessStatus?.isSuccess == true ? 'READY' : 'DEGRADED',
                            type: _readinessStatus?.isSuccess == true
                                ? BadgeType.success
                                : BadgeType.error,
                          ),
                        ),

                        // Gemini Provider Card
                        MetricCard(
                          title: 'GEMINI AI PROVIDER',
                          value: gemini?['status']?.toString() ?? 'Checking...',
                          subtitle: 'Model: ${gemini?['model'] ?? 'gemini-3.5-flash'}',
                          icon: Icons.auto_awesome_rounded,
                          accentColor: _getColorForStatus(gemini?['status']?.toString() ?? 'UNKNOWN'),
                          trailing: StatusBadge(
                            label: gemini?['status']?.toString() ?? 'UNKNOWN',
                            type: _getBadgeTypeForStatus(gemini?['status']?.toString() ?? 'UNKNOWN'),
                          ),
                        ),

                        // Latency Card
                        MetricCard(
                          title: 'HTTP ROUNDTRIP LATENCY',
                          value: _healthStatus == null
                              ? '-- ms'
                              : '${_healthStatus!.latencyMs} ms',
                          subtitle: 'API Network Roundtrip',
                          icon: Icons.speed_rounded,
                          accentColor: TexoraColors.primaryBlue,
                          trailing: StatusBadge(
                            label: (_healthStatus?.latencyMs ?? 999) < 100
                                ? 'OPTIMAL'
                                : 'NORMAL',
                            type: BadgeType.info,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Dedicated Worker Daemons Live Row
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: TexoraColors.cardBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: TexoraColors.cardBorder),
                        boxShadow: const [
                          BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.monitor_heart_rounded, color: TexoraColors.primaryBlue, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Realtime Background Worker Heartbeats',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: TexoraColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, wConstraints) {
                              int wCount = wConstraints.maxWidth < 800 ? 1 : 2;
                              return GridView.count(
                                crossAxisCount: wCount,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: wCount == 1 ? 3.0 : 2.4,
                                children: [
                                  // Anomaly Detector
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: TexoraColors.workspaceBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: TexoraColors.cardBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: _getColorForStatus(detector?.status ?? 'STOPPED').withAlpha(25),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(Icons.radar_rounded, color: _getColorForStatus(detector?.status ?? 'STOPPED'), size: 24),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  const Text(
                                                    'Anomaly Detector Daemon',
                                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                                                  ),
                                                  StatusBadge(
                                                    label: detector?.status ?? 'STOPPED',
                                                    type: _getBadgeTypeForStatus(detector?.status ?? 'STOPPED'),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                detector?.isRunning == true
                                                    ? 'PID: ${detector?.processId} • Evaluated: ${detector?.metrics['total_telemetry_processed'] ?? 0} records'
                                                    : 'Daemon status confirmed. Managed via operational scheduler.',
                                                style: const TextStyle(fontSize: 11, color: TexoraColors.textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Orchestrator Worker
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: TexoraColors.workspaceBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: TexoraColors.cardBorder),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: _getColorForStatus(orchestrator?.status ?? 'STOPPED').withAlpha(25),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(Icons.hub_rounded, color: _getColorForStatus(orchestrator?.status ?? 'STOPPED'), size: 24),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  const Text(
                                                    'Autonomous Orchestrator Worker',
                                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TexoraColors.textPrimary),
                                                  ),
                                                  StatusBadge(
                                                    label: orchestrator?.status ?? 'STOPPED',
                                                    type: _getBadgeTypeForStatus(orchestrator?.status ?? 'STOPPED'),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                orchestrator?.isRunning == true
                                                    ? 'PID: ${orchestrator?.processId} • Processed: ${orchestrator?.processingCount ?? 0} incidents'
                                                    : 'Worker operational. Dispatches 6-agent autonomous pipeline.',
                                                style: const TextStyle(fontSize: 11, color: TexoraColors.textSecondary),
                                              ),
                                            ],
                                          ),
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
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 24),

            // API Endpoint Configuration & Live Inspector Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: TexoraColors.cardBorder),
                boxShadow: const [
                  BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: TexoraColors.primaryBlue, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'API Configuration & Custom Target',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: TexoraColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Django Base API URL',
                            labelStyle: const TextStyle(color: TexoraColors.textMuted),
                            hintText: 'http://127.0.0.1:8000/api/v1',
                            hintStyle: const TextStyle(color: TexoraColors.textMuted),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            filled: true,
                            fillColor: TexoraColors.inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: TexoraColors.cardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: TexoraColors.cardBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: TexoraColors.primaryBlue, width: 2),
                            ),
                            prefixIcon: const Icon(Icons.link_rounded, size: 18, color: TexoraColors.textMuted),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _updateBaseUrl,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: const BorderSide(color: TexoraColors.primaryBlue),
                        ),
                        child: const Text('Update & Test', style: TextStyle(color: TexoraColors.primaryBlue, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Live Backend JSON Response Inspector
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: TexoraColors.cardBorder),
                boxShadow: const [
                  BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.terminal_rounded,
                              color: TexoraColors.primaryBlue, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Raw Backend Response Payload',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: TexoraColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _healthStatus?.isSuccess == true
                            ? 'HTTP 200 OK (Live from Django)'
                            : 'Status: ${_healthStatus?.status ?? 'Pending'}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _healthStatus?.isSuccess == true
                              ? TexoraColors.success
                              : TexoraColors.critical,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: TexoraColors.inputBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: TexoraColors.cardBorder),
                    ),
                    child: SelectableText(
                      _healthStatus?.rawJson ?? 'No response received yet.',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: TexoraColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
