import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/agent_operations_models.dart';
import '../../data/services/api_service.dart';
import '../widgets/autonomous_workflow_monitor.dart';
import '../widgets/business_impact_card.dart';
import '../widgets/agent_execution_detail_dialog.dart';

class AiAgentOperationsScreen extends StatefulWidget {
  final Function(int, {String? targetMachine})? onNavigate;

  const AiAgentOperationsScreen({
    super.key,
    this.onNavigate,
  });

  @override
  State<AiAgentOperationsScreen> createState() => _AiAgentOperationsScreenState();
}

class _AiAgentOperationsScreenState extends State<AiAgentOperationsScreen> {
  final ApiService _apiService = ApiService();
  Timer? _refreshTimer;

  bool _isLoading = true;
  String? _errorMessage;
  AgentOperationsOverviewModel? _overview;
  DateTime? _lastUpdated;

  // Selected incident for the live workflow monitor
  int? _selectedIncidentId;
  String? _selectedIncidentCode;
  String? _selectedMachineCode;

  // Controlled Demo Execution State
  bool _isTriggeringDemo = false;
  String? _demoFeedback;

  @override
  void initState() {
    super.initState();
    _fetchOverview(showLoading: true);
    // Poll every 3 seconds for live agent execution updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchOverview(showLoading: false);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOverview({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await _apiService.getAgentOperationsOverview();
      if (!mounted) return;

      if (res != null) {
        final parsed = AgentOperationsOverviewModel.fromJson(res);
        setState(() {
          _overview = parsed;
          _isLoading = false;
          _errorMessage = null;
          _lastUpdated = DateTime.now();

          // Auto-select latest incident from specialist agents if not already selected
          if (_selectedIncidentId == null) {
            for (final agent in parsed.specialistAgents) {
              if (agent.latestExecution?.incidentId != null) {
                _selectedIncidentId = agent.latestExecution!.incidentId;
                _selectedIncidentCode = agent.latestExecution!.incidentCode;
                _selectedMachineCode = agent.latestExecution!.machineCode;
                break;
              }
            }
          }
        });
      } else {
        if (showLoading) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Unable to connect to AI Agent Operations service.';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (showLoading) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Network error: $e';
        });
      }
    }
  }

  Future<void> _triggerDemoScenario() async {
    if (_isTriggeringDemo) return;

    setState(() {
      _isTriggeringDemo = true;
      _demoFeedback = null;
    });

    try {
      final res = await _apiService.triggerExpoDemo(machineCode: 'WEV-AJ-02');
      if (!mounted) return;

      if (res['success'] == true) {
        final incId = res['incident_id'] as int?;
        setState(() {
          _isTriggeringDemo = false;
          _demoFeedback = res['message'] ??
              'Controlled Demo initiated on WEV-AJ-02! Anomaly detected, multi-agent evaluation completed, paused at Manager Approval.';
          if (incId != null) {
            _selectedIncidentId = incId;
            _selectedIncidentCode = res['incident_code'];
            _selectedMachineCode = res['machine_code'] ?? 'WEV-AJ-02';
          }
        });
        await _fetchOverview(showLoading: false);
      } else {
        setState(() {
          _isTriggeringDemo = false;
          _demoFeedback = 'Demo Error: ${res['error'] ?? 'Execution failed.'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTriggeringDemo = false;
        _demoFeedback = 'Failed to execute demo: $e';
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'RUNNING':
        return const Color(0xFF38BDF8); // Cyan
      case 'COMPLETED':
        return const Color(0xFF10B981); // Emerald
      case 'WAITING_FOR_APPROVAL':
        return const Color(0xFFF59E0B); // Amber
      case 'FAILED':
        return const Color(0xFFEF4444); // Red
      case 'WAITING_FOR_DEPENDENCY':
        return const Color(0xFF818CF8); // Indigo
      case 'QUEUED':
        return const Color(0xFFA855F7); // Purple
      default:
        return const Color(0xFF64748B); // Slate (IDLE)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading && _overview == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF38BDF8)),
                  SizedBox(height: 16),
                  Text(
                    'Loading AI Specialist Agent Fleet Operations...',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            )
          : _errorMessage != null && _overview == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: Color(0xFFEF4444), size: 48),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _fetchOverview(showLoading: true),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry Connection'),
                      ),
                    ],
                  ),
                )
              : _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    final overview = _overview!;
    final orchHeartbeat = overview.workerHeartbeats['AUTONOMOUS_ORCHESTRATOR'];
    final detectorHeartbeat = overview.workerHeartbeats['ANOMALY_DETECTOR'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          _buildTopHeader(orchHeartbeat, detectorHeartbeat),

          const SizedBox(height: 20),

          // Demo Scenario Feedback Alert
          if (_demoFeedback != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _demoFeedback!.contains('Error') ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _demoFeedback!.contains('Error') ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                    color: _demoFeedback!.contains('Error') ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _demoFeedback!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 16),
                    onPressed: () => setState(() => _demoFeedback = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // 4 Specialist Agent Cards Grid
          const Text(
            'AUTONOMOUS SPECIALIST AGENTS',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 1100;
              final isTablet = constraints.maxWidth > 700;

              if (isDesktop) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: overview.specialistAgents.map((agent) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _buildSpecialistAgentCard(agent),
                      ),
                    );
                  }).toList(),
                );
              } else if (isTablet) {
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSpecialistAgentCard(overview.specialistAgents[0])),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSpecialistAgentCard(overview.specialistAgents[1])),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildSpecialistAgentCard(overview.specialistAgents[2])),
                        const SizedBox(width: 12),
                        Expanded(child: _buildSpecialistAgentCard(overview.specialistAgents[3])),
                      ],
                    ),
                  ],
                );
              } else {
                return Column(
                  children: overview.specialistAgents
                      .map((agent) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSpecialistAgentCard(agent),
                          ))
                      .toList(),
                );
              }
            },
          ),

          const SizedBox(height: 28),

          // Live Autonomous Workflow Monitor (For Active Incident)
          if (_selectedIncidentId != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF38BDF8),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ACTIVE INCIDENT WORKFLOW MONITOR — ${_selectedIncidentCode ?? "INCIDENT"} (${_selectedMachineCode ?? "MACHINE"})',
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () {
                    if (widget.onNavigate != null) {
                      widget.onNavigate!(2); // Navigate to Incident Intelligence
                    }
                  },
                  icon: const Icon(Icons.arrow_outward_rounded, size: 14),
                  label: const Text('Open in Incident Intelligence'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AutonomousWorkflowMonitor(
              key: ValueKey('workflow_mon_$_selectedIncidentId'),
              incidentId: _selectedIncidentId!,
              isCompact: false,
              onNavigateToApprovals: () {
                if (widget.onNavigate != null) {
                  widget.onNavigate!(5); // Navigate to Approval Center
                }
              },
              onNavigateToRecovery: () {
                if (widget.onNavigate != null) {
                  widget.onNavigate!(4); // Navigate to Recovery
                }
              },
            ),

            const SizedBox(height: 28),

            // Business Impact & Strategy Comparison
            BusinessImpactCard(
              key: ValueKey('business_imp_$_selectedIncidentId'),
              incidentId: _selectedIncidentId!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopHeader(WorkerHeartbeatModel? orchHeartbeat, WorkerHeartbeatModel? detectorHeartbeat) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.hub_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Agent Operations Center',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          _lastUpdated != null
                              ? 'Industrial Autonomous Specialist Fleet • Live sync: ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}'
                              : 'Industrial Autonomous Specialist Fleet • Real-Time Pipeline Telemetry',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _buildWorkerBadge(
                      'Orchestrator Worker',
                      orchHeartbeat?.status ?? 'STOPPED',
                      orchHeartbeat?.isRunning ?? false,
                    ),
                    _buildWorkerBadge(
                      'Anomaly Detector',
                      detectorHeartbeat?.status ?? 'STOPPED',
                      detectorHeartbeat?.isRunning ?? false,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0F1D),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Text(
                        'Total Executions: ${_overview?.overallMetrics.totalExecutions ?? 0}',
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Controlled 1-Click Expo Demonstration Mode Button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 2,
                ),
                onPressed: _isTriggeringDemo ? null : _triggerDemoScenario,
                icon: _isTriggeringDemo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_circle_filled_rounded, size: 18),
                label: Text(
                  _isTriggeringDemo ? 'Executing Simulation...' : '1-Click PSG Expo Demo',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'SIMULATION MODE • WEV-AJ-02 Bearing Fault',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerBadge(String name, String status, bool isRunning) {
    final color = isRunning ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$name: $status',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialistAgentCard(SpecialistAgentModel agent) {
    final statusColor = _getStatusColor(agent.currentStatus);
    final latest = agent.latestExecution;
    final isSelected = latest?.incidentId != null && latest?.incidentId == _selectedIncidentId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFF38BDF8).withAlpha(150) : const Color(0xFF1E293B),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Agent Name, Type, and Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      agent.role,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  agent.currentStatus.replaceAll('_', ' '),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Provenance Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.memory_rounded, size: 11, color: Color(0xFFA855F7)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    latest?.provenance ?? agent.modelName,
                    style: const TextStyle(color: Color(0xFFA855F7), fontSize: 10, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Latest Execution Evidence or Empty State
          if (latest != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Machine: ${latest.machineCode}',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${latest.latencyMs} ms',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Incident: ${latest.incidentCode}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    latest.latestFindings.isNotEmpty ? latest.latestFindings : latest.executionSummary,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (latest.recommendedAction != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.arrow_forward_rounded, color: Color(0xFF10B981), size: 10),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Action: ${latest.recommendedAction!['action_name'] ?? "Execute"}',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            Container(
              height: 105,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: const Center(
                child: Text(
                  'No execution events recorded yet.\nAgent standing by for incident trigger.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Card Footer: Metrics & Details Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Runs: ${agent.metrics.totalExecutions} (${agent.metrics.completedExecutions} ok)',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
              ),
              if (latest != null)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF38BDF8),
                  ),
                  onPressed: () {
                    // Open detailed audit dialog
                    AgentExecutionDetailDialog.show(context, latest.executionId);
                  },
                  child: const Text('Audit Trace', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),

          // Set as active workflow incident if user clicks row
          if (latest?.incidentId != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                  ),
                  backgroundColor: isSelected ? const Color(0xFF38BDF8).withAlpha(20) : Colors.transparent,
                ),
                onPressed: () {
                  setState(() {
                    _selectedIncidentId = latest!.incidentId;
                    _selectedIncidentCode = latest.incidentCode;
                    _selectedMachineCode = latest.machineCode;
                  });
                },
                child: Text(
                  isSelected ? '• Monitoring In Workflow Below •' : 'Track In Live Monitor',
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
