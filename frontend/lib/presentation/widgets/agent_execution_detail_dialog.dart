import 'package:flutter/material.dart';
import '../../data/services/api_service.dart';

class AgentExecutionDetailDialog extends StatefulWidget {
  final String executionId;

  const AgentExecutionDetailDialog({
    super.key,
    required this.executionId,
  });

  static Future<void> show(BuildContext context, String executionId) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AgentExecutionDetailDialog(executionId: executionId),
    );
  }

  @override
  State<AgentExecutionDetailDialog> createState() => _AgentExecutionDetailDialogState();
}

class _AgentExecutionDetailDialogState extends State<AgentExecutionDetailDialog> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _details;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.getAgentExecutionAuditDetails(widget.executionId);
      if (!mounted) return;

      if (res != null) {
        setState(() {
          _details = res;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Execution audit record #${widget.executionId} not found.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading execution record: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF1E293B)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA855F7).withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.psychology_rounded, color: Color(0xFFA855F7), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _details?['agent_name'] ?? 'Agent Execution Audit Record',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Execution UUID: ${widget.executionId}',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFEF4444))),
                        )
                      : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final d = _details!;
    final incident = d['incident'] as Map<String, dynamic>?;
    final machine = d['machine'] as Map<String, dynamic>?;
    final decisions = (d['decisions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final actions = (d['actions'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final recoveryCase = d['recovery_case'] as Map<String, dynamic>?;
    final approval = d['approval_request'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metadata Overview Grid
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                _buildMetaItem('Status', d['status'] ?? 'N/A', isBadge: true),
                _buildMetaItem('Latency', '${d['latency_ms'] ?? 0} ms'),
                _buildMetaItem('Started At', d['started_at'] ?? 'N/A'),
                _buildMetaItem('Completed At', d['completed_at'] ?? 'N/A'),
                _buildMetaItem('Model / Engine', d['model_name'] ?? 'N/A'),
                if (incident != null)
                  _buildMetaItem('Incident', '${incident['incident_code']} (${incident['severity']})'),
                if (machine != null)
                  _buildMetaItem('Machine Asset', '${machine['code']} — ${machine['name']}'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Diagnostic / Planning Summary
          const Text(
            'EXECUTION REASONING & SUMMARY',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Text(
              d['execution_summary']?.toString().isNotEmpty == true
                  ? d['execution_summary'].toString()
                  : 'Execution reasoning recorded without errors.',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
            ),
          ),

          const SizedBox(height: 20),

          // Structured Decisions
          if (decisions.isNotEmpty) ...[
            const Text(
              'STRUCTURED DECISIONS & VERDICTS',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ...decisions.map((dec) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0F1D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dec['decision_type_display'] ?? dec['decision_type'] ?? 'Decision',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Confidence: ${dec['confidence_score']}%',
                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dec['rationale'] ?? '',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
          ],

          // Actions Invoked
          if (actions.isNotEmpty) ...[
            const Text(
              'TOOLS & OPERATIONS SCHEDULED',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ...actions.map((act) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0F1D),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFF38BDF8), size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              act['action_name'] ?? 'Action',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Tool: ${act['tool_name']} • Status: ${act['status']}',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
          ],

          // Related Links
          if (recoveryCase != null || approval != null) ...[
            const Text(
              'CROSS-SYSTEM RECOVERY & GOVERNANCE CORRELATION',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Row(
                children: [
                  if (recoveryCase != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Recovery Case', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                          Text('${recoveryCase['case_code']} [${recoveryCase['status']}]',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  if (approval != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Approval Request', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                          Text('${approval['approval_code']} [${approval['status']}]',
                              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaItem(String label, String value, {bool isBadge = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withAlpha(30),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w700),
            ),
          )
        else
          Text(
            value,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}
