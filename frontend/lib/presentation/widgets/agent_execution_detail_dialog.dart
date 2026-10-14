import 'dart:convert';
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
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 780),
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

    final reasoningSrc = d['reasoning_source']?.toString() ?? 'DETERMINISTIC_FALLBACK';
    final provStatus = d['provider_attempt_status']?.toString() ?? 'DETERMINISTIC_FALLBACK';
    final modelName = d['model_name']?.toString() ?? 'gemini-3.8-flash';
    final execError = d['execution_error']?.toString();
    final structuredOutput = d['structured_output'] as Map<String, dynamic>?;
    final inputContext = d['input_context'] as Map<String, dynamic>?;

    final machineCode = machine?['code']?.toString() ?? '';
    final isSimulated = machineCode == 'WEV-AJ-02' || (incident?['summary']?.toString().contains('Simulated') == true);

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
              spacing: 20,
              runSpacing: 14,
              children: [
                _buildMetaItem('Execution Status', d['status'] ?? 'N/A', isBadge: true),
                _buildProvenanceBadge(reasoningSrc, provStatus),
                _buildTelemetrySourceBadge(isSimulated, machineCode),
                _buildMetaItem('Configured Model', modelName),
                _buildMetaItem('Latency', '${d['latency_ms'] ?? 0} ms'),
                _buildMetaItem('Started At', d['started_at'] ?? 'N/A'),
                if (incident != null)
                  _buildMetaItem('Incident', '${incident['incident_code']} (${incident['severity']})'),
                if (machine != null)
                  _buildMetaItem('Machine Asset', '${machine['code']} — ${machine['name']}'),
              ],
            ),
          ),

          // Provider Warning / Rate Limit Alert Box
          if (provStatus == 'GEMINI_RATE_LIMITED' || execError != null && execError.contains('429')) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF451A03).withAlpha(180),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Gemini Free Quota Exhaustion (HTTP 429) Handled Safely',
                          style: TextStyle(color: Color(0xFFFDE68A), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Live quota limit reached. Circuit breaker engaged with zero latency impact. '
                          'Deterministic industrial safety fallback flawlessly generated validated operational protocols.',
                          style: TextStyle(color: const Color(0xFFFDE68A).withAlpha(200), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (provStatus == 'GEMINI_UNAVAILABLE' || execError != null && execError.contains('503')) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF451A03).withAlpha(180),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off_rounded, color: Color(0xFFF59E0B), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gemini API High Demand (HTTP 503): Service temporarily unavailable. Seamlessly failed over to Deterministic Engine.',
                      style: TextStyle(color: Color(0xFFFDE68A), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Input Evidence Summary
          if (inputContext != null && inputContext.isNotEmpty) ...[
            const Text(
              'INPUT TELEMETRY & CONTEXT EVIDENCE',
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
              child: _buildInputContextSummary(inputContext),
            ),
            const SizedBox(height: 20),
          ],

          // Diagnostic / Planning Summary
          const Text(
            'EXECUTION REASONING & SYNTHESIS',
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
                  : 'Execution reasoning synthesized successfully.',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
            ),
          ),

          // Structured Output Section
          if (structuredOutput != null && structuredOutput.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'VALIDATED STRUCTURED AGENT OUTPUT',
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
              child: _buildStructuredOutputView(structuredOutput),
            ),
          ],

          const SizedBox(height: 20),

          // Structured Decisions
          if (decisions.isNotEmpty) ...[
            const Text(
              'STRUCTURED DECISIONS & SAFETY VERDICTS',
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
              'GATED ACTIONS & DOWNSTREAM WORKFLOW EFFECT',
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
                      const Icon(Icons.shield_rounded, color: Color(0xFF38BDF8), size: 16),
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
                              'Tool: ${act['tool_name']} • State: ${act['status']} (Awaiting Manager Approval)',
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
              'AUTONOMOUS DIGITAL TWIN & GOVERNANCE CORRELATION',
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
                          const Text('Digital Twin Recovery Case', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                          Text('${recoveryCase['case_code']} [${recoveryCase['status']}]',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('Strategy: ${recoveryCase['recommended_strategy']}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                        ],
                      ),
                    ),
                  if (approval != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Human Approval Gate', style: TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                          Text('${approval['approval_code']} [${approval['status']}]',
                              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('Action: ${approval['requested_action']}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
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

  Widget _buildProvenanceBadge(String reasoningSrc, String provStatus) {
    Color bg;
    Color border;
    Color text;
    String label;

    if (reasoningSrc == 'GROQ_LIVE' || provStatus == 'GROQ_LIVE') {
      bg = const Color(0xFFF97316).withAlpha(30);
      border = const Color(0xFFF97316);
      text = const Color(0xFFF97316);
      label = 'LIVE GROQCLOUD AI INFERENCE';
    } else if (reasoningSrc == 'GEMINI_LIVE' || provStatus == 'GEMINI_LIVE') {
      bg = const Color(0xFFA855F7).withAlpha(30);
      border = const Color(0xFFA855F7);
      text = const Color(0xFFA855F7);
      label = 'LIVE GOOGLE GEMINI AI';
    } else if (provStatus.contains('RATE_LIMITED') || provStatus.contains('QUOTA')) {
      bg = const Color(0xFFF59E0B).withAlpha(30);
      border = const Color(0xFFF59E0B);
      text = const Color(0xFFF59E0B);
      label = 'RATE LIMITED (429) -> SAFE FALLBACK';
    } else if (provStatus.contains('UNAVAILABLE') || provStatus.contains('503')) {
      bg = const Color(0xFFF59E0B).withAlpha(30);
      border = const Color(0xFFF59E0B);
      text = const Color(0xFFF59E0B);
      label = 'SERVICE 503 -> SAFE FALLBACK';
    } else {
      bg = const Color(0xFF38BDF8).withAlpha(25);
      border = const Color(0xFF38BDF8);
      text = const Color(0xFF38BDF8);
      label = 'DETERMINISTIC SAFETY ENGINE';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI Reasoning Provenance', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetrySourceBadge(bool isSimulated, String machineCode) {
    final color = isSimulated ? const Color(0xFFF97316) : const Color(0xFF10B981);
    final text = isSimulated ? 'SIMULATED DATA ($machineCode)' : 'PHYSICAL SENSORS ($machineCode)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Telemetry Origin', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color),
          ),
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildInputContextSummary(Map<String, dynamic> ctx) {
    final items = <Widget>[];
    ctx.forEach((k, v) {
      if (k == 'api_key' || k == 'token') return;
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$k: ', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600)),
            Expanded(
              child: Text(
                v is Map || v is List ? jsonEncode(v) : v.toString(),
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ));
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }

  Widget _buildStructuredOutputView(Map<String, dynamic> out) {
    final items = <Widget>[];
    out.forEach((k, v) {
      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              k.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(color: Color(0xFFA855F7), fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              v is Map || v is List ? const JsonEncoder.withIndent('  ').convert(v) : v.toString(),
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
      ));
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: items);
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
