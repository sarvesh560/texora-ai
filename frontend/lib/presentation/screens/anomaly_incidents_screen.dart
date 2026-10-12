import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/incident_model.dart';
import '../../data/services/api_service.dart';


class AnomalyIncidentsScreen extends StatefulWidget {
  const AnomalyIncidentsScreen({super.key});

  @override
  State<AnomalyIncidentsScreen> createState() => _AnomalyIncidentsScreenState();
}

class _AnomalyIncidentsScreenState extends State<AnomalyIncidentsScreen> {
  final ApiService _apiService = ApiService();
  IncidentsSummaryModel? _summary;
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
      setState(() => _isLoading = true);
    }

    final summary = await _apiService.fetchIncidentsSummary();

    if (mounted) {
      setState(() {
        _summary = summary;
        if (!silent) _isLoading = false;
      });
    }
  }

  Future<void> _triggerEval() async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.triggerDetectionEval(batchSize: 100);
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Anomaly evaluation cycle executed.' : 'Failed to run detection cycle.';
      });
      _fetchSummary();
    }
  }

  Future<void> _resolveIncident(int id) async {
    setState(() => _isActionInProgress = true);
    final ok = await _apiService.resolveIncident(id, notes: 'Resolved by Operations Operator');
    if (mounted) {
      setState(() {
        _isActionInProgress = false;
        _statusMessage = ok ? 'Incident #$id marked as resolved.' : 'Failed to resolve incident.';
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
                    'Autonomous Anomaly & Incident Center',
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
                      color: AppColors.successGreen.withAlpha(35),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.successGreen.withAlpha(100)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.radar_rounded, size: 14, color: AppColors.successGreen),
                        SizedBox(width: 6),
                        Text(
                          'MONITORING ACTIVE',
                          style: TextStyle(
                            color: AppColors.successGreen,
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
                'Incremental rolling temporal analysis across machine limits, temperature, vibration, speed and power',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _isActionInProgress ? null : _triggerEval,
                icon: const Icon(Icons.flash_on_rounded, size: 18),
                label: const Text('Run Detection Cycle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
              ),
              IconButton(
                onPressed: _fetchSummary,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Incidents',
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
      return const Center(child: Text('No incident monitoring data available. Ensure backend is running.'));
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildMetricCards(summary),
        const SizedBox(height: 24),
        _buildActiveIncidentsSection(summary),
        const SizedBox(height: 24),
        _buildRecentAnomaliesTimeline(summary),
      ],
    );
  }

  Widget _buildMetricCards(IncidentsSummaryModel summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 48) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'ACTIVE INCIDENTS',
              value: '${summary.totalActiveIncidents}',
              subtitle: '${summary.statusBreakdown['RESOLVED'] ?? 0} Recovered / Resolved',
              icon: Icons.error_outline_rounded,
              iconColor: summary.totalActiveIncidents > 0 ? AppColors.errorRed : AppColors.successGreen,
              width: cardWidth.clamp(200.0, 320.0),
            ),
            _buildStatCard(
              title: 'CRITICAL ANOMALIES',
              value: '${summary.severityBreakdown['CRITICAL'] ?? 0}',
              subtitle: 'Immediate Failure Risk',
              icon: Icons.dangerous_rounded,
              iconColor: AppColors.errorRed,
              width: cardWidth.clamp(200.0, 320.0),
            ),
            _buildStatCard(
              title: 'WARNING ELEVATIONS',
              value: '${(summary.severityBreakdown['HIGH'] ?? 0) + (summary.severityBreakdown['MEDIUM'] ?? 0)}',
              subtitle: 'Operating Drift / Throttle',
              icon: Icons.warning_amber_rounded,
              iconColor: AppColors.warningOrange,
              width: cardWidth.clamp(200.0, 320.0),
            ),
            _buildStatCard(
              title: 'TELEMETRY EVALUATED',
              value: '${summary.checkpoint.totalTelemetryProcessed}',
              subtitle: 'Checkpoint #${summary.checkpoint.lastProcessedTelemetryId}',
              icon: Icons.speed_rounded,
              iconColor: AppColors.primaryBlue,
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

  Widget _buildActiveIncidentsSection(IncidentsSummaryModel summary) {
    final incidents = summary.activeIncidents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Active Operational Incidents (${incidents.length})',
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
        if (incidents.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 40, color: AppColors.successGreen),
                  SizedBox(height: 12),
                  Text(
                    'No Active Factory Incidents',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'All 25 machines operating within normal thermal, vibration, RPM and power limits.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: incidents.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final inc = incidents[index];

              Color sevColor;
              if (inc.severity == 'CRITICAL') {
                sevColor = AppColors.errorRed;
              } else if (inc.severity == 'HIGH') {
                sevColor = AppColors.warningOrange;
              } else {
                sevColor = AppColors.primaryBlue;
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sevColor.withAlpha(100), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: sevColor.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            inc.severity,
                            style: TextStyle(color: sevColor, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            inc.category,
                            style: const TextStyle(color: AppColors.navyDark, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          inc.incidentCode,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                        ),
                        const Spacer(),
                        Text(
                          'Detected: ${inc.detectedAt.length > 19 ? inc.detectedAt.substring(11, 19) : inc.detectedAt}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      inc.summary,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navyDark),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Root Cause Hypothesis: ${inc.rootCauseHypothesis}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.precision_manufacturing_rounded, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(
                          '${inc.machineCode ?? "Factory"} — ${inc.machineName ?? ""} (${inc.departmentName})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _isActionInProgress ? null : () => _resolveIncident(inc.id),
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: const Text('Mark Resolved'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.successGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }


  Widget _buildRecentAnomaliesTimeline(IncidentsSummaryModel summary) {
    final anomalies = summary.recentAnomalies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Telemetry Anomaly Detections Stream',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.navyDark,
          ),
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
            itemCount: anomalies.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, index) {
              final anom = anomalies[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.errorRed.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.errorRed),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: Text(
                        anom.machineCode,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.navyDark),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Metric: ${anom.metricName} | Observed: ${anom.observedValue} (Threshold: ${anom.thresholdValue})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Score: ${anom.anomalyScore}x (${anom.confidencePct}%)',
                        style: const TextStyle(color: AppColors.primaryBlue, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      anom.detectedAt.length > 19 ? anom.detectedAt.substring(11, 19) : anom.detectedAt,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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

}
