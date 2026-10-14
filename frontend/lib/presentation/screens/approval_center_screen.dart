import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';

class ApprovalCenterScreen extends StatefulWidget {
  final Function(int, {String? targetMachine})? onNavigate;
  final VoidCallback? onClose;

  const ApprovalCenterScreen({super.key, this.onNavigate, this.onClose});

  @override
  State<ApprovalCenterScreen> createState() => _ApprovalCenterScreenState();
}

class _ApprovalCenterScreenState extends State<ApprovalCenterScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _approvals = [];
  String _selectedStatusFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApprovals();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApprovals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _apiService.fetchApprovalRequestsList(
        status: _selectedStatusFilter == 'ALL' ? null : _selectedStatusFilter,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) {
        setState(() {
          _approvals = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load manager approval requests: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredApprovals {
    return _approvals.where((item) {
      final code = (item['approval_code'] ?? '').toString().toLowerCase();
      final title = (item['title'] ?? '').toString().toLowerCase();
      final incCode = (item['incident_code'] ?? '').toString().toLowerCase();
      final incSumm = (item['incident_summary'] ?? '').toString().toLowerCase();
      final action = (item['requested_action'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchesQuery = q.isEmpty ||
          code.contains(q) ||
          title.contains(q) ||
          incCode.contains(q) ||
          incSumm.contains(q) ||
          action.contains(q);

      final status = (item['status'] ?? '').toString();
      final matchesStatus = _selectedStatusFilter == 'ALL' || status == _selectedStatusFilter;

      return matchesQuery && matchesStatus;
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'ALL') return _approvals.length;
    return _approvals.where((a) => a['status'] == status).length;
  }

  void _showApproveDialog(Map<String, dynamic> approval) {
    final code = approval['approval_code'] ?? 'APR-${approval['id']}';
    final action = approval['requested_action'] ?? approval['title'] ?? 'Execute Recovery';
    final TextEditingController nameController = TextEditingController(text: 'Operations Director');
    final TextEditingController notesController = TextEditingController(text: 'Authorized production reroute and maintenance dispatch.');
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: TexoraColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: TexoraColors.cardBorder),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TexoraColors.successBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: TexoraColors.successBorder),
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: TexoraColors.successText, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Authorize AI Action [$code]',
                      style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: TexoraColors.workspaceBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: TexoraColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TARGET OPERATIONAL ACTION:',
                              style: TextStyle(color: TexoraColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              action,
                              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Server-side authorization will execute the requested recovery strategy via ActionSafetyService and create an immutable audit record.',
                        style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Authorizing Manager / Role:',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Chief Operations Officer',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.inputBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Authorization Notes:',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter justification or operational remarks...',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.inputBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: TexoraColors.textMuted)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final approvalId = approval['id'] as int;
                          final resp = await _apiService.approveApprovalRequest(
                            approvalId,
                            approvedBy: nameController.text.trim(),
                            responseNotes: notesController.text.trim(),
                          );
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                          }
                          if (resp['error'] != null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Approval Failed: ${resp['error']}'),
                                  backgroundColor: TexoraColors.critical,
                                ),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Action Authorized successfully. Autonomous execution pipeline triggered.'),
                                  backgroundColor: TexoraColors.success,
                                ),
                              );
                              _loadApprovals();
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TexoraColors.success,
                    foregroundColor: Colors.white,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(isSubmitting ? 'Authorizing...' : 'Authorize Action'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRevisionDialog(Map<String, dynamic> approval) {
    final code = approval['approval_code'] ?? 'APR-${approval['id']}';
    final TextEditingController nameController = TextEditingController(text: 'Shift Supervisor');
    final TextEditingController notesController = TextEditingController(text: 'Requesting alternative line reassignment with lower maintenance downtime.');
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: TexoraColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: TexoraColors.cardBorder),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TexoraColors.warningBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: TexoraColors.warningBorder),
                    ),
                    child: const Icon(Icons.history_edu_rounded, color: TexoraColors.warningText, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Request Strategy Revision [$code]',
                      style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Requesting revision returns this gate to the AI Recovery Orchestrator with human operator feedback to regenerate an updated proposal.',
                        style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Reviewing Manager / Engineer:',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Lead Maintenance Engineer',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.inputBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Revision Instructions for AI Agents:',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Specify parameter constraints, alternative machines, or parts...',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.inputBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: TexoraColors.textMuted)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final approvalId = approval['id'] as int;
                          final resp = await _apiService.requestRevisionApprovalRequest(
                            approvalId,
                            reviewedBy: nameController.text.trim(),
                            revisionNotes: notesController.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (resp['error'] != null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Revision Failed: ${resp['error']}'), backgroundColor: TexoraColors.critical),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Revision request submitted to AI Orchestrator.'), backgroundColor: TexoraColors.info),
                              );
                              _loadApprovals();
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TexoraColors.warning,
                    foregroundColor: Colors.white,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.rate_review_rounded, size: 16),
                  label: Text(isSubmitting ? 'Submitting...' : 'Submit Revision Request'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRejectDialog(Map<String, dynamic> approval) {
    final code = approval['approval_code'] ?? 'APR-${approval['id']}';
    final TextEditingController nameController = TextEditingController(text: 'Plant Manager');
    final TextEditingController notesController = TextEditingController(text: 'Rejected: Line intervention deemed unnecessary during current shift schedule.');
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: TexoraColors.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: TexoraColors.cardBorder),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TexoraColors.criticalBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: TexoraColors.criticalBorder),
                    ),
                    child: const Icon(Icons.block_rounded, color: TexoraColors.criticalText, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reject AI Proposal [$code]',
                      style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rejecting this proposal halts autonomous execution of the mitigation strategy. An immutable incident audit log entry will record this human override.',
                        style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Rejecting Authority:',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Factory General Manager',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.inputBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Rejection Rationale:',
                        style: TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter mandatory audit justification...',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.inputBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: TexoraColors.textMuted)),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final approvalId = approval['id'] as int;
                          final resp = await _apiService.rejectApprovalRequest(
                            approvalId,
                            rejectedBy: nameController.text.trim(),
                            responseNotes: notesController.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (resp['error'] != null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Rejection Failed: ${resp['error']}'), backgroundColor: TexoraColors.critical),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Request marked Rejected and logged to Audit Trail.'), backgroundColor: TexoraColors.critical),
                              );
                              _loadApprovals();
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TexoraColors.critical,
                    foregroundColor: Colors.white,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.block_rounded, size: 16),
                  label: Text(isSubmitting ? 'Rejecting...' : 'Reject Request'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TexoraColors.workspaceBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          _buildTopHeader(),

          // KPI Metric Cards
          _buildKpiMetrics(),

          // Filter Tabs & Search
          _buildFilterToolbar(),

          // Main Approvals List / Table
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: TexoraColors.primaryBlue.withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.gavel_rounded, color: TexoraColors.primaryBlue, size: 20),
                    ),
                    const Text(
                      'Manager Approval Center',
                      style: TextStyle(
                        color: TexoraColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: TexoraColors.inputBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: TexoraColors.cardBorder),
                      ),
                      child: const Text(
                        'Human-In-The-Loop Governance',
                        style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Review and authorize high-impact AI agent actions, production reroutes, and factory maintenance dispatches.',
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loadApprovals,
                icon: const Icon(Icons.refresh_rounded, size: 16, color: TexoraColors.textSecondary),
                label: const Text('Refresh', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: TexoraColors.cardBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiMetrics() {
    final pendingCount = _countForStatus('PENDING');
    final approvedCount = _countForStatus('APPROVED');
    final revisionCount = _countForStatus('REVISION_REQUESTED');
    final rejectedCount = _countForStatus('REJECTED');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        children: [
          _buildKpiCard(
            title: 'PENDING ACTION GATES',
            value: '$pendingCount',
            icon: Icons.hourglass_top_rounded,
            color: pendingCount > 0 ? TexoraColors.warning : TexoraColors.textMuted,
            isAlert: pendingCount > 0,
          ),
          const SizedBox(width: 14),
          _buildKpiCard(
            title: 'AUTHORIZED & EXECUTED',
            value: '$approvedCount',
            icon: Icons.check_circle_outline_rounded,
            color: TexoraColors.success,
          ),
          const SizedBox(width: 14),
          _buildKpiCard(
            title: 'REVISIONS REQUESTED',
            value: '$revisionCount',
            icon: Icons.history_edu_rounded,
            color: TexoraColors.info,
          ),
          const SizedBox(width: 14),
          _buildKpiCard(
            title: 'REJECTED BY MANAGERS',
            value: '$rejectedCount',
            icon: Icons.cancel_outlined,
            color: TexoraColors.critical,
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isAlert = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: TexoraColors.workspaceBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAlert ? color.withAlpha(140) : TexoraColors.cardBorder,
            width: isAlert ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: TexoraColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(color: isAlert ? color : TexoraColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToolbar() {
    final tabs = [
      {'id': 'ALL', 'label': 'All Requests'},
      {'id': 'PENDING', 'label': 'Pending Review'},
      {'id': 'APPROVED', 'label': 'Approved'},
      {'id': 'REVISION_REQUESTED', 'label': 'Revision Requested'},
      {'id': 'REJECTED', 'label': 'Rejected'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        children: [
          // Filter Tabs (Horizontally Scrollable)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tabs.map((tab) {
                  final isSelected = _selectedStatusFilter == tab['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${tab['label']} (${_countForStatus(tab['id']!)})'),
                      selected: isSelected,
                      selectedColor: TexoraColors.sidebarActivePill,
                      backgroundColor: TexoraColors.workspaceBg,
                      labelStyle: TextStyle(
                        color: isSelected ? TexoraColors.primaryBlue : TexoraColors.textSecondary,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: isSelected ? TexoraColors.primaryBlue : TexoraColors.cardBorder,
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedStatusFilter = tab['id']!;
                          });
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Search Field
          SizedBox(
            width: 280,
            height: 36,
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search code, incident, action...',
                hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                prefixIcon: const Icon(Icons.search_rounded, color: TexoraColors.textMuted, size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14, color: TexoraColors.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: TexoraColors.inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: TexoraColors.cardBorder),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: TexoraColors.primaryBlue),
            SizedBox(height: 16),
            Text('Loading approval requests from backend...', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: TexoraColors.critical, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadApprovals,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(backgroundColor: TexoraColors.primaryBlue),
              ),
            ],
          ),
        ),
      );
    }

    final list = _filteredApprovals;

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: TexoraColors.inputBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.task_alt_rounded, color: TexoraColors.textMuted, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Approval Requests Found',
              style: TextStyle(color: TexoraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No approval matching search criteria "$_searchQuery".'
                  : 'All autonomous workflows are running normally with no pending gates.',
              style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: list.length,
      itemBuilder: (context, index) {
        return _buildApprovalCard(list[index]);
      },
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> item) {
    final status = item['status'] ?? 'PENDING';
    final risk = item['risk_level'] ?? 'HIGH';
    final code = item['approval_code'] ?? 'APR-${item['id']}';
    final title = item['title'] ?? 'AI Decision Approval';
    final action = item['requested_action'] ?? 'Unspecified Action';
    final agent = item['requested_by_agent'] ?? 'AI Recovery Orchestrator';
    final desc = item['description'] ?? '';
    final incCode = item['incident_code'] ?? 'INC-000';
    final incSumm = item['incident_summary'] ?? 'Factory Incident';
    final createdAt = item['created_at']?.toString() ?? '';
    final approvedBy = item['approved_by']?.toString() ?? '';
    final responseNotes = item['response_notes']?.toString() ?? '';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (status) {
      case 'APPROVED':
        statusColor = TexoraColors.success;
        statusLabel = 'APPROVED & EXECUTED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'REJECTED':
        statusColor = TexoraColors.critical;
        statusLabel = 'REJECTED BY MANAGER';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'REVISION_REQUESTED':
        statusColor = TexoraColors.warning;
        statusLabel = 'REVISION REQUESTED';
        statusIcon = Icons.history_edu_rounded;
        break;
      default:
        statusColor = TexoraColors.warning;
        statusLabel = 'ACTION GATE PENDING';
        statusIcon = Icons.hourglass_top_rounded;
    }

    Color riskColor;
    switch (risk.toString().toUpperCase()) {
      case 'CRITICAL':
        riskColor = TexoraColors.critical;
        break;
      case 'HIGH':
        riskColor = const Color(0xFFF97316);
        break;
      case 'MEDIUM':
        riskColor = TexoraColors.warning;
        break;
      default:
        riskColor = TexoraColors.info;
    }

    final isPending = status == 'PENDING';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: TexoraColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending ? statusColor.withAlpha(120) : TexoraColors.cardBorder,
          width: isPending ? 1.4 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Bar of Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: isPending ? statusColor.withAlpha(15) : TexoraColors.workspaceBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: const Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: TexoraColors.cardBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: TexoraColors.cardBorder),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: riskColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: riskColor.withAlpha(100)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_rounded, size: 11, color: riskColor),
                          const SizedBox(width: 4),
                          Text(
                            '$risk RISK',
                            style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Card Body
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: TexoraColors.inputBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: TexoraColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.bolt_rounded, size: 15, color: TexoraColors.primaryBlue),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    action,
                                    style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    desc,
                    style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12, height: 1.4),
                  ),
                ],
                const SizedBox(height: 14),

                // Incident & Source Agent Row
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smart_toy_outlined, size: 14, color: TexoraColors.textMuted),
                        const SizedBox(width: 6),
                        const Text('Source Agent: ', style: TextStyle(color: TexoraColors.textMuted, fontSize: 11)),
                        Text(agent, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 14, color: TexoraColors.warning),
                        const SizedBox(width: 6),
                        const Text('Incident: ', style: TextStyle(color: TexoraColors.textMuted, fontSize: 11)),
                        Text('$incCode — $incSumm', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    if (createdAt.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: TexoraColors.textMuted),
                          const SizedBox(width: 6),
                          Text(createdAt, style: const TextStyle(color: TexoraColors.textMuted, fontSize: 11)),
                        ],
                      ),
                  ],
                ),

                // Review Audit History (if not pending)
                if (!isPending) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: TexoraColors.inputBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: TexoraColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Decision by: $approvedBy ${responseNotes.isNotEmpty ? "— Remarks: $responseNotes" : ""}',
                            style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Action Buttons for Pending Approvals
                if (isPending) ...[
                  const SizedBox(height: 16),
                  const Divider(color: TexoraColors.cardBorder, height: 1),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showRejectDialog(item),
                        icon: const Icon(Icons.close_rounded, size: 14, color: TexoraColors.critical),
                        label: const Text('Reject', style: TextStyle(color: TexoraColors.critical, fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: TexoraColors.criticalBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _showRevisionDialog(item),
                        icon: const Icon(Icons.history_edu_rounded, size: 14, color: TexoraColors.warning),
                        label: const Text('Request Revision', style: TextStyle(color: TexoraColors.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: TexoraColors.warningBorder),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _showApproveDialog(item),
                        icon: const Icon(Icons.check_circle_rounded, size: 15),
                        label: const Text('Authorize & Execute', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TexoraColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
