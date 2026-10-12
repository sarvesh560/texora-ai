import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../widgets/industrial_widgets.dart';

class AiActivityCenterWidget extends StatelessWidget {
  final List<dynamic> executions;
  final List<dynamic> incidents;
  final List<dynamic> recoveryCases;
  final Function(String routeName, Map<String, dynamic>? params)? onNavigate;

  const AiActivityCenterWidget({
    super.key,
    required this.executions,
    required this.incidents,
    required this.recoveryCases,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accentPurple.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.hub_rounded, color: AppColors.accentPurple, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Autonomous AI Operations Stream',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Multi-agent incident triage, planning, approval & verification workflow',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'REAL-TIME AUDIT STREAM',
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Lifecycle Workflow Path Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildWorkflowStepPill('1. Telemetry', Icons.sensors_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('2. Anomaly', Icons.radar_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('3. Incident', Icons.warning_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('4. AI Agent', Icons.psychology_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('5. Recovery Plan', Icons.assignment_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('6. Manager Approval', Icons.verified_user_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('7. Maintenance', Icons.build_circle_rounded, true),
                  _buildArrow(),
                  _buildWorkflowStepPill('8. Verified', Icons.check_circle_rounded, true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Real Backend Events List
          if (executions.isEmpty && incidents.isEmpty && recoveryCases.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No autonomous agent activities recorded yet.', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: (executions.length + incidents.length + recoveryCases.length).clamp(0, 6),
              separatorBuilder: (context, index) => const Divider(color: Color(0xFF1E293B), height: 16),
              itemBuilder: (context, index) {
                if (index < recoveryCases.length) {
                  final rc = recoveryCases[index];
                  final caseCode = rc['case_code'] ?? 'REC-2026';
                  final status = rc['status'] ?? 'ANALYZING';
                  final machineCode = rc['machine_code'] ?? 'WEV-AJ-02';
                  final strategy = rc['proposed_strategy'] ?? 'Immediate Repair & Part Replacement';

                  return _buildActivityRow(
                    icon: Icons.build_circle_rounded,
                    iconColor: const Color(0xFF0D9488),
                    badgeText: 'RECOVERY CASE',
                    badgeColor: const Color(0xFF0D9488),
                    title: '$caseCode on $machineCode: $strategy',
                    subtitle: 'Status: $status | Approved maintenance work order attached',
                    timestamp: rc['created_at']?.toString().split('T').first ?? 'Today',
                    statusWidget: ApprovalStatusChip(status: status),
                  );
                } else if (index - recoveryCases.length < executions.length) {
                  final ex = executions[index - recoveryCases.length];
                  final agentName = ex['agent_name'] ?? 'Machine Health Specialist';
                  final summary = ex['execution_summary'] ?? 'Autonomous telemetry diagnosis complete';
                  final status = ex['status'] ?? 'COMPLETED';

                  return _buildActivityRow(
                    icon: Icons.psychology_rounded,
                    iconColor: AppColors.accentPurple,
                    badgeText: 'AI INVESTIGATION',
                    badgeColor: AppColors.accentPurple,
                    title: '$agentName: $summary',
                    subtitle: 'Trigger: Anomaly threshold excursion | Token telemetry verified',
                    timestamp: ex['started_at']?.toString().split('T').first ?? 'Recent',
                    statusWidget: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(color: AppColors.successGreen, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                } else {
                  final incIdx = index - recoveryCases.length - executions.length;
                  final inc = incidents[incIdx.clamp(0, incidents.length - 1)];
                  final code = inc['incident_code'] ?? 'INC-001';
                  final summary = inc['summary'] ?? 'Sensor threshold excursion';
                  final severity = inc['severity'] ?? 'WARNING';

                  return _buildActivityRow(
                    icon: Icons.warning_amber_rounded,
                    iconColor: severity == 'CRITICAL' ? AppColors.errorRed : AppColors.warningOrange,
                    badgeText: 'INCIDENT DETECTED',
                    badgeColor: severity == 'CRITICAL' ? AppColors.errorRed : AppColors.warningOrange,
                    title: '$code: $summary',
                    subtitle: 'Origin: Autonomous Telemetry Engine | Machine status updated',
                    timestamp: inc['detected_at']?.toString().split('T').first ?? 'Recent',
                    statusWidget: IncidentSeverityBadge(severity: severity, isCompact: true),
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStepPill(String label, IconData icon, bool isPassed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPassed ? const Color(0xFF0F172A) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isPassed ? const Color(0xFF334155) : const Color(0xFF1E293B)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isPassed ? const Color(0xFF38BDF8) : const Color(0xFF64748B), size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isPassed ? Colors.white : const Color(0xFF64748B),
              fontSize: 10,
              fontWeight: isPassed ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.chevron_right_rounded, color: Color(0xFF475569), size: 14),
    );
  }

  Widget _buildActivityRow({
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required Color badgeColor,
    required String title,
    required String subtitle,
    required String timestamp,
    required Widget statusWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withAlpha(25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(color: badgeColor, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            statusWidget,
            const SizedBox(height: 4),
            Text(
              timestamp,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
