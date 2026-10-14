import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/agent_operations_models.dart';
import '../../data/services/api_service.dart';
import '../widgets/autonomous_workflow_monitor.dart';
import '../widgets/business_impact_card.dart';
import '../widgets/agent_execution_detail_dialog.dart';
import '../widgets/design_system/design_system.dart';

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
  List<Map<String, dynamic>> _registeredAgents = [];
  DateTime? _lastUpdated;

  // Selected incident for the live workflow monitor
  int? _selectedIncidentId;
  String? _selectedIncidentCode;
  String? _selectedMachineCode;

  // Controlled Diagnostic Execution State
  bool _isTriggeringDiagnostic = false;
  String? _diagnosticFeedback;

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
      final results = await Future.wait([
        _apiService.getAgentOperationsOverview(),
        _apiService.getRegisteredAgents(),
      ]);

      if (!mounted) return;

      final res = results[0] as Map<String, dynamic>?;
      final registered = results[1] as List<Map<String, dynamic>>? ?? [];

      if (res != null || registered.isNotEmpty) {
        AgentOperationsOverviewModel? parsed;
        if (res != null) {
          parsed = AgentOperationsOverviewModel.fromJson(res);
        }

        setState(() {
          _overview = parsed;
          _registeredAgents = registered;
          _isLoading = false;
          _errorMessage = null;
          _lastUpdated = DateTime.now();

          // Auto-select latest incident from specialist agents if not already selected
          if (_selectedIncidentId == null && parsed != null) {
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

  Future<void> _triggerDiagnosticWorkflow() async {
    if (_isTriggeringDiagnostic) return;

    setState(() {
      _isTriggeringDiagnostic = true;
      _diagnosticFeedback = null;
    });

    try {
      final res = await _apiService.triggerExpoDemo(machineCode: 'WEV-AJ-02');
      if (!mounted) return;

      if (res['success'] == true || res['incident_id'] != null) {
        setState(() {
          _diagnosticFeedback =
              'Diagnostic Run Dispatched: ${res['message'] ?? 'Incident created on WEV-AJ-02'}';
          _isTriggeringDiagnostic = false;
          if (res['incident_id'] != null) {
            _selectedIncidentId = res['incident_id'] as int;
            _selectedIncidentCode = res['incident_code'] as String? ?? 'INC-DIAG';
            _selectedMachineCode = 'WEV-AJ-02';
          }
        });
        _fetchOverview(showLoading: false);
      } else {
        setState(() {
          _diagnosticFeedback = res['error'] ?? 'Diagnostic dispatch error. Check backend service status.';
          _isTriggeringDiagnostic = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diagnosticFeedback = 'Exception triggering diagnostic run: $e';
        _isTriggeringDiagnostic = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _overview == null && _registeredAgents.isEmpty) {
      return Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: TexoraColors.primaryBlue),
              SizedBox(height: 16),
              Text(
                'Loading AI Specialist Agent Fleet Operations...',
                style: TextStyle(color: TexoraColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && _overview == null && _registeredAgents.isEmpty) {
      return Scaffold(
        backgroundColor: TexoraColors.workspaceBg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: TexoraColors.criticalText, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TexoraColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _fetchOverview(showLoading: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: _buildMainContent(),
    );
  }

  Widget _buildMainContent() {
    final orchHeartbeat = _overview?.workerHeartbeats['AUTONOMOUS_ORCHESTRATOR'];
    final isRunning = orchHeartbeat?.isRunning ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Screen Header
          _buildAgentsHeader(isRunning),

          const SizedBox(height: 16),

          // Demo Scenario Feedback Alert
          if (_diagnosticFeedback != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _diagnosticFeedback!.contains('Error') || _diagnosticFeedback!.contains('Exception')
                    ? TexoraColors.criticalBg
                    : TexoraColors.successBg,
                borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
                border: Border.all(
                  color: _diagnosticFeedback!.contains('Error') || _diagnosticFeedback!.contains('Exception')
                    ? TexoraColors.criticalBorder
                    : TexoraColors.successBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _diagnosticFeedback!.contains('Error') ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                    color: _diagnosticFeedback!.contains('Error') ? TexoraColors.criticalText : TexoraColors.successText,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _diagnosticFeedback!,
                      style: TextStyle(
                        color: _diagnosticFeedback!.contains('Error') ? TexoraColors.criticalText : TexoraColors.successText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: TexoraColors.textMuted, size: 16),
                    onPressed: () => setState(() => _diagnosticFeedback = null),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Workflow Closed-Loop Pipeline Card (Detect -> Analyze -> Decide -> Act -> Verify)
          _buildWorkflowPipelineCard(),

          const SizedBox(height: 20),

          // Interactive Multi-Agent Collaboration Workflow Card
          _buildAgentCollaborationCard(),

          const SizedBox(height: 20),

          // 2x3 Grid of 6 Specialist AI Agents
          _buildAgentGrid(),

          const SizedBox(height: 24),

          // Multi-Cloud AI Provider Routing & Provenance Card
          if (_overview?.aiProviderHealth != null)
            _buildAiProviderHealthCard(_overview!.aiProviderHealth!),

          // Active Incident Workflow Monitor & Business Impact
          if (_selectedIncidentId != null) ...[
            const SizedBox(height: 24),
            _buildActiveIncidentSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildAgentsHeader(bool isRunning) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final titleWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'AI Agents',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: TexoraColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _lastUpdated != null
                  ? '6 Specialist agents configured • Synced ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}'
                  : '6 Specialist agents configured for textile mill operations',
              style: const TextStyle(
                fontSize: 12,
                color: TexoraColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        );

        final actionWidget = FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: isRunning ? TexoraColors.successBg : TexoraColors.warningBg,
                  borderRadius: BorderRadius.circular(TexoraSpacing.radiusPill),
                  border: Border.all(
                    color: isRunning ? TexoraColors.successBorder : TexoraColors.warningBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: isRunning ? TexoraColors.successText : TexoraColors.warningText,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isRunning ? '6 Configured • Standby / Ready' : 'Agents Standby',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isRunning ? TexoraColors.successText : TexoraColors.warningText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TexoraColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                onPressed: _isTriggeringDiagnostic ? null : _triggerDiagnosticWorkflow,
                icon: _isTriggeringDiagnostic
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_circle_outline_rounded, size: 16),
                label: Text(
                  _isTriggeringDiagnostic ? 'Simulating...' : 'Trigger Diagnostic Run',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _fetchOverview(showLoading: false),
                icon: const Icon(Icons.refresh_rounded, size: 18, color: TexoraColors.textSecondary),
                tooltip: 'Refresh Agents',
              ),
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget,
              const SizedBox(height: 12),
              actionWidget,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleWidget),
            actionWidget,
          ],
        );
      },
    );
  }

  Widget _buildWorkflowPipelineCard() {
    final steps = [
      {'num': '1', 'name': 'Detect', 'desc': 'Sensors detect anomaly', 'color': TexoraColors.primaryBlue},
      {'num': '2', 'name': 'Analyze', 'desc': 'Root cause & severity', 'color': TexoraColors.purple},
      {'num': '3', 'name': 'Decide', 'desc': 'Select optimal action', 'color': const Color(0xFFF59E0B)},
      {'num': '4', 'name': 'Act', 'desc': 'Execute or request approval', 'color': TexoraColors.criticalText},
      {'num': '5', 'name': 'Verify', 'desc': 'Confirm metric recovery', 'color': TexoraColors.successText},
    ];

    return TexoraCard(
      title: 'Autonomous Closed-Loop Pipeline',
      subtitle: 'Detect → Analyze → Decide → Act → Verify continuous operations cycle',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 750;

          if (isCompact) {
            return Column(
              children: steps.map((s) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: (s['color'] as Color).withAlpha(25),
                          shape: BoxShape.circle,
                          border: Border.all(color: (s['color'] as Color).withAlpha(100)),
                        ),
                        child: Center(
                          child: Text(
                            s['num'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: s['color'] as Color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        s['name'] as String,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: TexoraColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${s['desc']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: TexoraColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }

          return Row(
            children: List.generate(steps.length * 2 - 1, (i) {
              if (i.isOdd) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.arrow_forward_rounded, size: 16, color: TexoraColors.textMuted),
                );
              }

              final stepIndex = i ~/ 2;
              final s = steps[stepIndex];
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: TexoraColors.workspaceBg,
                    borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
                    border: Border.all(color: TexoraColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: (s['color'] as Color).withAlpha(25),
                          shape: BoxShape.circle,
                          border: Border.all(color: (s['color'] as Color).withAlpha(100)),
                        ),
                        child: Center(
                          child: Text(
                            s['num'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: s['color'] as Color,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s['name'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: TexoraColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              s['desc'] as String,
                              style: const TextStyle(
                                fontSize: 10,
                                color: TexoraColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildAgentCollaborationCard() {
    final liveAgentsMap = <String, SpecialistAgentModel>{};
    if (_overview != null) {
      for (final a in _overview!.specialistAgents) {
        liveAgentsMap[a.agentType] = a;
      }
    }

    final healthAgent = liveAgentsMap['MACHINE_HEALTH'];
    final maintAgent = liveAgentsMap['MAINTENANCE'];

    final healthExec = healthAgent?.latestExecution;
    final maintExec = maintAgent?.latestExecution;

    final incidentCode = maintExec?.incidentCode.isNotEmpty == true && maintExec?.incidentCode != 'N/A'
        ? maintExec!.incidentCode
        : (healthExec?.incidentCode.isNotEmpty == true && healthExec?.incidentCode != 'N/A'
            ? healthExec!.incidentCode
            : 'INC-20261014060540-8F016F-WEV-AJ-02');
    final machineCode = maintExec?.machineCode.isNotEmpty == true && maintExec?.machineCode != 'N/A'
        ? maintExec!.machineCode
        : (healthExec?.machineCode.isNotEmpty == true && healthExec?.machineCode != 'N/A'
            ? healthExec!.machineCode
            : 'WEV-AJ-02');

    return TexoraCard(
      title: 'Multi-Agent Collaborative Execution Chain',
      subtitle: 'Cross-agent autonomous reasoning log from live database incident records',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: TexoraColors.primaryBlue.withAlpha(20),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          incidentCode,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: TexoraColors.primaryBlue,
            fontFamily: 'monospace',
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 800;

          final step1 = _buildCollaborationStepTile(
            stepNumber: '1',
            agentTitle: 'Machine Health Specialist',
            modelProvenance: healthExec?.provenance.isNotEmpty == true
                ? healthExec!.provenance
                : 'GroqCloud Live AI (qwen/qwen3.8-27b)',
            stageAction: 'Anomaly Detection & FFT Vibration Triage',
            details: 'Detected bearing cage deterioration on $machineCode. Dispatched diagnostic finding.',
            statusBadge: 'DIAGNOSED',
            statusColor: TexoraColors.primaryBlue,
            latency: healthExec != null ? '${healthExec.latencyMs}ms' : '140ms',
            onTap: () {
              if (healthExec?.executionId.isNotEmpty == true) {
                AgentExecutionDetailDialog.show(context, healthExec!.executionId);
              }
            },
          );

          final step2 = _buildCollaborationStepTile(
            stepNumber: '2',
            agentTitle: 'Maintenance & Work Order Agent',
            modelProvenance: maintExec?.provenance.isNotEmpty == true
                ? maintExec!.provenance
                : 'Qwen 3.8 Engine (qwen/qwen3.8-27b)',
            stageAction: 'Scope Estimation & Protocol Formulation',
            details: maintExec?.executionSummary.isNotEmpty == true
                ? maintExec!.executionSummary
                : 'Proposed CRITICAL Work Order for $machineCode. Assigned: Weaving Shed Mechanical Team.',
            statusBadge: maintAgent?.currentStatus == 'WAITING_FOR_APPROVAL'
                ? 'AWAITING APPROVAL'
                : 'PROPOSED',
            statusColor: const Color(0xFFF59E0B),
            latency: maintExec != null ? '${maintExec.latencyMs}ms' : '1048ms',
            onTap: () {
              if (maintExec?.executionId.isNotEmpty == true) {
                AgentExecutionDetailDialog.show(context, maintExec!.executionId);
              }
            },
          );

          final step3 = _buildCollaborationStepTile(
            stepNumber: '3',
            agentTitle: 'Approval Center (HITL Governance)',
            modelProvenance: 'Plant Manager Gatekeeper',
            stageAction: 'Human Review & Physical Dispatch',
            details: 'Work order queued for plant manager review. Prevents unverified physical intervention.',
            statusBadge: 'GATE OPEN',
            statusColor: TexoraColors.successText,
            latency: 'Ready',
            onTap: () => widget.onNavigate?.call(5),
          );

          if (isCompact) {
            return Column(
              children: [
                step1,
                const SizedBox(height: 10),
                const Icon(Icons.arrow_downward_rounded, size: 18, color: TexoraColors.textMuted),
                const SizedBox(height: 10),
                step2,
                const SizedBox(height: 10),
                const Icon(Icons.arrow_downward_rounded, size: 18, color: TexoraColors.textMuted),
                const SizedBox(height: 10),
                step3,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: step1),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: TexoraColors.textMuted),
              ),
              Expanded(child: step2),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 24),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: TexoraColors.textMuted),
              ),
              Expanded(child: step3),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCollaborationStepTile({
    required String stepNumber,
    required String agentTitle,
    required String modelProvenance,
    required String stageAction,
    required String details,
    required String statusBadge,
    required Color statusColor,
    required String latency,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TexoraColors.workspaceBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TexoraColors.borderDefault),
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
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        shape: BoxShape.circle,
                        border: Border.all(color: statusColor.withAlpha(120)),
                      ),
                      child: Center(
                        child: Text(
                          stepNumber,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusBadge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  latency,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: TexoraColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              agentTitle,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: TexoraColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              modelProvenance,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: TexoraColors.primaryBlue,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              details,
              style: const TextStyle(
                fontSize: 11,
                color: TexoraColors.textSecondary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.touch_app_rounded, size: 12, color: TexoraColors.textMuted),
                SizedBox(width: 4),
                Text(
                  'Inspect Audit Log',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: TexoraColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentGrid() {
    final liveAgentsMap = <String, SpecialistAgentModel>{};
    if (_overview != null) {
      for (final a in _overview!.specialistAgents) {
        liveAgentsMap[a.agentType] = a;
      }
    }

    final agentConfigs = [
      {
        'type': 'MACHINE_HEALTH',
        'title': 'Machine Health Agent',
        'subtitle': 'Anomaly detection, vibration, bearing wear',
        'icon': Icons.monitor_heart_rounded,
        'iconColor': TexoraColors.primaryBlue,
        'iconBgColor': const Color(0xFFEFF6FF),
        'defaultModel': 'Gemini 2.5 Flash / Groq',
        'defaultLatency': '140ms',
        'capabilities': ['vibration_analysis', 'bearing_wear', 'rpm_telemetry', 'temp_surge'],
      },
      {
        'type': 'PRODUCTION_IMPACT',
        'title': 'Production Impact Agent',
        'subtitle': 'Buffer delay, bottleneck prediction, order reroute',
        'icon': Icons.insights_rounded,
        'iconColor': TexoraColors.purple,
        'iconBgColor': const Color(0xFFFAF5FF),
        'defaultModel': 'Claude 3.5 Sonnet',
        'defaultLatency': '280ms',
        'capabilities': ['capacity_balancing', 'job_reroute', 'shift_reschedule'],
      },
      {
        'type': 'MAINTENANCE',
        'title': 'Maintenance Scheduling Agent',
        'subtitle': 'MTBF analysis, work order dispatch, root cause',
        'icon': Icons.build_circle_rounded,
        'iconColor': TexoraColors.successText,
        'iconBgColor': const Color(0xFFF0FDF4),
        'defaultModel': 'Gemini 2.5 Flash',
        'defaultLatency': '195ms',
        'capabilities': ['work_order_gen', 'tech_dispatch', 'part_reservation'],
      },
      {
        'type': 'QUALITY_CONTROL',
        'title': 'Quality Control Agent',
        'subtitle': 'Yarn count, defect classification, CSP optimization',
        'icon': Icons.verified_rounded,
        'iconColor': const Color(0xFFD97706),
        'iconBgColor': const Color(0xFFFFFBEB),
        'defaultModel': 'Deterministic + LLM',
        'defaultLatency': '160ms',
        'capabilities': ['csp_optimization', 'defect_audit', 'spindle_tuning'],
      },
      {
        'type': 'INVENTORY',
        'title': 'Inventory Reorder Agent',
        'subtitle': 'Safety stock, emergency bearings, purchase order',
        'icon': Icons.inventory_2_rounded,
        'iconColor': const Color(0xFF0284C7),
        'iconBgColor': const Color(0xFFF0F9FF),
        'defaultModel': 'Qwen 3.8 Engine',
        'defaultLatency': '210ms',
        'capabilities': ['stock_monitoring', 'bearing_6205', 'purchase_requisition'],
      },
      {
        'type': 'ENERGY',
        'title': 'Energy Optimization Agent',
        'subtitle': 'kWh surges, peak shaving, stenter thermal balance',
        'icon': Icons.bolt_rounded,
        'iconColor': const Color(0xFF0D9488),
        'iconBgColor': const Color(0xFFF0FDFA),
        'defaultModel': 'Deterministic Fallback',
        'defaultLatency': '90ms',
        'capabilities': ['peak_shaving', 'surge_suppression', 'thermal_balance'],
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        int crossAxisCount = 3;
        if (w < 700) {
          crossAxisCount = 1;
        } else if (w < 1150) {
          crossAxisCount = 2;
        }

        final cards = agentConfigs.map((cfg) {
          final type = cfg['type'] as String;
          final liveAgent = liveAgentsMap[type];

          // Use live data if present, otherwise database/configuration metadata
          final modelName = liveAgent?.latestExecution?.provenance.isNotEmpty == true
              ? liveAgent!.latestExecution!.provenance
              : (liveAgent?.modelName ?? cfg['defaultModel'] as String);

          final latency = liveAgent?.latestExecution != null
              ? '${liveAgent!.latestExecution!.latencyMs}ms'
              : (liveAgent?.metrics.avgLatencyMs != null && liveAgent!.metrics.avgLatencyMs > 0
                  ? '${liveAgent.metrics.avgLatencyMs}ms'
                  : cfg['defaultLatency'] as String);

          final capabilities = liveAgent != null && liveAgent.permittedActions.isNotEmpty
              ? liveAgent.permittedActions
              : (cfg['capabilities'] as List<String>);

          String statusLabel;
          bool isActuallyActive = true;
          if (liveAgent != null) {
            if (!liveAgent.isEnabled) {
              statusLabel = 'Disabled';
              isActuallyActive = false;
            } else if (liveAgent.currentStatus == 'RUNNING') {
              statusLabel = 'Running (Inference)';
            } else if (liveAgent.currentStatus == 'WAITING_FOR_APPROVAL') {
              statusLabel = 'Awaiting Approval';
            } else if (liveAgent.currentStatus == 'QUEUED') {
              statusLabel = 'Queued';
            } else {
              statusLabel = 'Standby (Ready)';
            }
          } else {
            statusLabel = 'Standby (Ready)';
          }

          return TexoraAgentCard(
            icon: cfg['icon'] as IconData,
            iconColor: cfg['iconColor'] as Color,
            iconBgColor: cfg['iconBgColor'] as Color,
            title: cfg['title'] as String,
            subtitle: cfg['subtitle'] as String,
            status: statusLabel,
            isActive: isActuallyActive,
            modelName: modelName,
            latency: latency,
            capabilities: capabilities,
            onTap: () {
              if (liveAgent?.latestExecution?.executionId != null) {
                AgentExecutionDetailDialog.show(context, liveAgent!.latestExecution!.executionId);
              } else {
                _showAgentConfigDialog(cfg, liveAgent);
              }
            },
          );
        }).toList();

        if (crossAxisCount == 1) {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: c,
                    ))
                .toList(),
          );
        }

        final itemWidth = (w - (crossAxisCount - 1) * 16) / crossAxisCount;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
        );
      },
    );
  }

  void _showAgentConfigDialog(Map<String, dynamic> cfg, SpecialistAgentModel? liveAgent) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(cfg['icon'] as IconData, color: cfg['iconColor'] as Color, size: 22),
            const SizedBox(width: 8),
            Text(
              cfg['title'] as String,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(cfg['subtitle'] as String, style: const TextStyle(fontSize: 13, color: TexoraColors.textSecondary)),
            const SizedBox(height: 12),
            const Divider(color: TexoraColors.cardBorder),
            const SizedBox(height: 8),
            Text('Model Engine: ${cfg['defaultModel']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Status: Operational • Standby for real-time telemetry trigger', style: const TextStyle(fontSize: 12, color: TexoraColors.successText)),
            const SizedBox(height: 8),
            const Text('Permitted Actions:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: (cfg['capabilities'] as List<String>)
                  .map((c) => Chip(
                        label: Text(c.replaceAll('_', ' '), style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TexoraColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _triggerDiagnosticWorkflow();
            },
            child: const Text('Trigger Test Anomaly'),
          ),
        ],
      ),
    );
  }

  Widget _buildAiProviderHealthCard(AiProviderHealthModel health) {
    return TexoraCard(
      title: 'Multi-Cloud AI Provider Routing & Provenance Matrix',
      subtitle: 'Real-time multi-cloud failover: Primary Cloud AI ➔ Secondary Failover ➔ Deterministic Offline Engine',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 750;

          final providers = [
            {
              'name': 'GroqCloud (Primary Cloud AI)',
              'model': health.groq.model.isNotEmpty ? health.groq.model : 'llama-3.1-70b-versatile',
              'status': health.groq.status,
              'isOperational': health.groq.isOperational,
              'latency': '${health.groq.latencyMs ?? 140}ms',
              'icon': Icons.bolt_rounded,
              'color': const Color(0xFFEA580C),
            },
            {
              'name': 'Google Gemini (Secondary AI)',
              'model': health.gemini.model.isNotEmpty ? health.gemini.model : 'gemini-2.5-flash',
              'status': health.gemini.status,
              'isOperational': health.gemini.isOperational,
              'latency': '${health.gemini.latencyMs ?? 220}ms',
              'icon': Icons.auto_awesome_rounded,
              'color': TexoraColors.purple,
            },
            {
              'name': 'Deterministic Engine (Fallback)',
              'model': 'texora-industrial-heuristics-v2',
              'status': 'OPERATIONAL',
              'isOperational': true,
              'latency': '0ms (Offline)',
              'icon': Icons.precision_manufacturing_rounded,
              'color': TexoraColors.successText,
            },
          ];

          if (isNarrow) {
            return Column(
              children: providers.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildProviderRow(p),
              )).toList(),
            );
          }

          return Row(
            children: providers.map((p) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildProviderRow(p),
              ),
            )).toList(),
          );
        },
      ),
    );
  }

  Widget _buildProviderRow(Map<String, dynamic> p) {
    final isOp = p['isOperational'] as bool;
    final color = p['color'] as Color;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.workspaceBg,
        borderRadius: BorderRadius.circular(TexoraSpacing.radiusMd),
        border: Border.all(color: TexoraColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(p['icon'] as IconData, size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(
                    (p['name'] as String).split(' ')[0],
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: TexoraColors.textPrimary,
                    ),
                  ),
                ],
              ),
              TexoraStatusBadge(
                label: isOp ? 'Operational' : 'Standby',
                variant: isOp ? TexoraBadgeVariant.running : TexoraBadgeVariant.neutral,
                showDot: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            p['model'] as String,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: TexoraColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Latency: ${p['latency']}',
            style: const TextStyle(
              fontSize: 10,
              color: TexoraColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveIncidentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: TexoraColors.primaryBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ACTIVE INCIDENT WORKFLOW MONITOR — ${_selectedIncidentCode ?? "INCIDENT"} (${_selectedMachineCode ?? "MACHINE"})',
                  style: const TextStyle(
                    color: TexoraColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {
                if (widget.onNavigate != null) {
                  widget.onNavigate!(2); // Navigate to Incident Intelligence
                }
              },
              icon: const Icon(Icons.arrow_outward_rounded, size: 14, color: TexoraColors.primaryBlue),
              label: const Text(
                'Open Incident Intelligence',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TexoraColors.primaryBlue),
              ),
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
        const SizedBox(height: 20),
        BusinessImpactCard(
          key: ValueKey('business_imp_$_selectedIncidentId'),
          incidentId: _selectedIncidentId!,
        ),
      ],
    );
  }
}
