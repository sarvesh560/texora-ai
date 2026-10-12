import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/models/workflow_timeline_models.dart';
import '../../data/services/api_service.dart';

class AutonomousWorkflowMonitor extends StatefulWidget {
  final int incidentId;
  final bool isCompact;
  final VoidCallback? onNavigateToApprovals;
  final VoidCallback? onNavigateToRecovery;

  const AutonomousWorkflowMonitor({
    super.key,
    required this.incidentId,
    this.isCompact = false,
    this.onNavigateToApprovals,
    this.onNavigateToRecovery,
  });

  @override
  State<AutonomousWorkflowMonitor> createState() => _AutonomousWorkflowMonitorState();
}

class _AutonomousWorkflowMonitorState extends State<AutonomousWorkflowMonitor> {
  final ApiService _apiService = ApiService();
  Timer? _pollingTimer;

  bool _isLoading = true;
  String? _errorMessage;
  IncidentWorkflowModel? _workflow;
  DateTime? _lastUpdated;
  int? _selectedStageIndex;

  @override
  void initState() {
    super.initState();
    _fetchWorkflow(showLoading: true);
    // Poll every 3 seconds for live updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        _fetchWorkflow(showLoading: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AutonomousWorkflowMonitor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incidentId != widget.incidentId) {
      _fetchWorkflow(showLoading: true);
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWorkflow({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _apiService.getIncidentWorkflow(widget.incidentId);
      if (!mounted) return;

      if (data != null && data['stages'] != null) {
        final parsed = IncidentWorkflowModel.fromJson(data);
        setState(() {
          _workflow = parsed;
          _isLoading = false;
          _errorMessage = null;
          _lastUpdated = DateTime.now();
        });
      } else {
        if (showLoading) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Workflow data currently unavailable for Incident #${widget.incidentId}';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (showLoading) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Network error fetching live workflow: $e';
        });
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return const Color(0xFF10B981); // Emerald
      case 'RUNNING':
        return const Color(0xFF38BDF8); // Cyan/Sky Blue
      case 'WAITING_FOR_APPROVAL':
        return const Color(0xFFF59E0B); // Amber
      case 'BLOCKED':
        return const Color(0xFFEF4444); // Red
      case 'FAILED':
        return const Color(0xFFDC2626); // Dark Red
      case 'SKIPPED':
        return const Color(0xFF64748B); // Slate
      case 'PENDING':
        return const Color(0xFF818CF8); // Indigo
      default:
        return const Color(0xFF475569); // Muted Slate
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return Icons.check_circle_rounded;
      case 'RUNNING':
        return Icons.sync_rounded;
      case 'WAITING_FOR_APPROVAL':
        return Icons.gavel_rounded;
      case 'BLOCKED':
        return Icons.block_rounded;
      case 'FAILED':
        return Icons.error_outline_rounded;
      case 'SKIPPED':
        return Icons.redo_rounded;
      case 'PENDING':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _workflow == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
              ),
              SizedBox(height: 12),
              Text(
                'Connecting to Autonomous Pipeline Stream...',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && _workflow == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 18),
              onPressed: () => _fetchWorkflow(showLoading: true),
            ),
          ],
        ),
      );
    }

    if (widget.isCompact) {
      return _buildCompactView();
    }

    return _buildFullView();
  }

  Widget _buildCompactView() {
    final stages = _workflow?.stages ?? [];
    final currentStage = _workflow?.currentStage ?? 'UNKNOWN';

    // Count completed
    final completedCount = stages.where((s) => s.isCompleted).length;
    final total = stages.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
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
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LIVE WORKFLOW PIPELINE',
                    style: TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$completedCount / $total Stages Done',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mini progress track of 12 stages
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? (completedCount / total) : 0,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),

          // Current active stage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Active Stage: $currentStage',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_workflow?.approvalStatus == 'PENDING')
                InkWell(
                  onTap: widget.onNavigateToApprovals,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withAlpha(40),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gavel_rounded, size: 10, color: Color(0xFFF59E0B)),
                        SizedBox(width: 4),
                        Text(
                          'AWAITING APPROVAL',
                          style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFullView() {
    final stages = _workflow?.stages ?? [];
    final incident = _workflow?.incident ?? {};

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.account_tree_rounded, color: Color(0xFF38BDF8), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Autonomous Incident Execution Monitor',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: const Text(
                            'LIVE DATABASE STREAM',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Incident: ${incident['incident_code'] ?? 'N/A'} • Machine: ${incident['machine_code'] ?? 'N/A'} (${incident['department_name'] ?? 'Manufacturing'})',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_lastUpdated != null)
                      Text(
                        'Updated ${_lastUpdated!.hour.toString().padLeft(2, '0')}:${_lastUpdated!.minute.toString().padLeft(2, '0')}:${_lastUpdated!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 20),
                      tooltip: 'Refresh Workflow',
                      onPressed: () => _fetchWorkflow(showLoading: false),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Stage Stepper List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: stages.length,
            separatorBuilder: (context, index) => Container(
              margin: const EdgeInsets.only(left: 23),
              width: 2,
              height: 12,
              color: const Color(0xFF1E293B),
            ),
            itemBuilder: (context, index) {
              final stage = stages[index];
              final isSelected = _selectedStageIndex == index;
              return _buildStageTile(stage, index, isSelected);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStageTile(WorkflowStageModel stage, int index, bool isSelected) {
    final statusColor = _getStatusColor(stage.status);
    final statusIcon = _getStatusIcon(stage.status);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _selectedStageIndex = isSelected ? null : index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? statusColor.withAlpha(150) : const Color(0xFF1E293B),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Step Number & Icon
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    shape: BoxShape.circle,
                    border: Border.all(color: statusColor, width: 1.5),
                  ),
                  child: Center(
                    child: Icon(statusIcon, color: statusColor, size: 14),
                  ),
                ),
                const SizedBox(width: 12),

                // Title & Component
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${stage.stageIndex}. ${stage.title}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              stage.component,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stage.outputSummary,
                        style: TextStyle(
                          color: stage.isCompleted ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                          fontSize: 11,
                        ),
                        maxLines: isSelected ? null : 1,
                        overflow: isSelected ? null : TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Status Badge & Duration
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        stage.status.replaceAll('_', ' '),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (stage.durationMs != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${stage.durationMs}ms',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            // Expanded Evidence Details
            if (isSelected) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1D),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'STAGE EXECUTION EVIDENCE',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (stage.timestamp != null)
                          Text(
                            'Timestamp: ${stage.timestamp}',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'AI Provenance: ${stage.provenance}',
                      style: const TextStyle(
                        color: Color(0xFFA855F7),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (stage.databaseRecord != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Database Record: ${stage.databaseRecord!['model']} #${stage.databaseRecord!['id'] ?? stage.databaseRecord!['code'] ?? 'N/A'}',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                      ),
                    ],
                    if (stage.evidence.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Evidence Snapshot:',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.all(8),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          stage.evidence.toString(),
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                    if (stage.isWaitingApproval && widget.onNavigateToApprovals != null) ...[
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: widget.onNavigateToApprovals,
                        icon: const Icon(Icons.gavel_rounded, size: 14),
                        label: const Text('Open in Approval Center'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
