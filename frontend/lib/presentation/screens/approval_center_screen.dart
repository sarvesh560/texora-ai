import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/api_service.dart';

class ApprovalCenterScreen extends StatefulWidget {
  final Function(int, {String? targetMachine})? onNavigate;

  const ApprovalCenterScreen({super.key, this.onNavigate});

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
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.successGreen.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: AppColors.successGreen, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Authorize AI Action [$code]',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
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
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.successGreen.withAlpha(60)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TARGET OPERATIONAL ACTION:',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              action,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Server-side authorization will execute the requested recovery strategy via ActionSafetyService and create an immutable audit record.',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Authorizing Manager / Role:',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Chief Operations Officer',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Authorization Notes:',
                        style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Enter justification or operational remarks...',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF334155))),
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
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
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
                          if (resp['success'] == false) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Approval Failed: ${resp['error'] ?? 'Unknown error'}'),
                                  backgroundColor: AppColors.errorRed,
                                ),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Action Authorized & Dispatched to Factory Controllers successfully.'),
                                  backgroundColor: AppColors.successGreen,
                                ),
                              );
                              _loadApprovals();
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.successGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
    final TextEditingController roleController = TextEditingController(text: 'Factory Operations Director');
    final TextEditingController notesController = TextEditingController(
      text: 'Re-simulate Strategy B with lower speed constraint on alternate loom.',
    );
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.history_edu_rounded, color: Color(0xFFF59E0B), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Request Revision [$code]',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Return recommendation to autonomous agents for alternative simulation or parameter adjustment.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Requesting Authority:',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: roleController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Revision Instructions / Reason:',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Specify what agents need to adjust...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final approvalId = approval['id'] as int;
                          final ok = await _apiService.requestApprovalRevision(
                            approvalId,
                            notes: notesController.text.trim(),
                            requestedBy: roleController.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (ok) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Revision request submitted to AI Orchestrator.'),
                                  backgroundColor: Color(0xFFF59E0B),
                                ),
                              );
                              _loadApprovals();
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to submit revision request.'),
                                  backgroundColor: AppColors.errorRed,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.black,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(isSubmitting ? 'Submitting...' : 'Submit Revision'),
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
    final TextEditingController roleController = TextEditingController(text: 'Factory Operations Director');
    final TextEditingController notesController = TextEditingController(
      text: 'Rejected: Production schedule does not permit line stoppage at this time.',
    );
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.cancel_outlined, color: AppColors.errorRed, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Reject Action Request [$code]',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rejecting this request aborts the autonomous action execution and notifies the incident response team.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Deciding Authority:',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: roleController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Mandatory Rejection Rationale:',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'State explicit operational reason...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          final approvalId = approval['id'] as int;
                          final resp = await _apiService.rejectApprovalRequest(
                            approvalId,
                            rejectedBy: roleController.text.trim(),
                            responseNotes: notesController.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (resp['success'] == false) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Rejection Failed: ${resp['error'] ?? 'Unknown error'}'),
                                  backgroundColor: AppColors.errorRed,
                                ),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Request marked Rejected and logged to Audit Trail.'),
                                  backgroundColor: AppColors.errorRed,
                                ),
                              );
                              _loadApprovals();
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
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
      color: const Color(0xFF0B1120),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
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
                        color: AppColors.primaryBlue.withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.gavel_rounded, color: AppColors.primaryBlueLight, size: 20),
                    ),
                    const Text(
                      'Manager Approval Center',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Text(
                        'Human-In-The-Loop Governance',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Review and authorize high-impact AI agent actions, production reroutes, and factory maintenance dispatches.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loadApprovals,
                icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF94A3B8)),
                label: const Text('Refresh', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF334155)),
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
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          _buildKpiCard(
            title: 'PENDING ACTION GATES',
            value: '$pendingCount',
            icon: Icons.hourglass_top_rounded,
            color: pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
            isAlert: pendingCount > 0,
          ),
          const SizedBox(width: 14),
          _buildKpiCard(
            title: 'AUTHORIZED & EXECUTED',
            value: '$approvedCount',
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.successGreen,
          ),
          const SizedBox(width: 14),
          _buildKpiCard(
            title: 'REVISIONS REQUESTED',
            value: '$revisionCount',
            icon: Icons.history_edu_rounded,
            color: const Color(0xFF38BDF8),
          ),
          const SizedBox(width: 14),
          _buildKpiCard(
            title: 'REJECTED BY MANAGERS',
            value: '$rejectedCount',
            icon: Icons.cancel_outlined,
            color: AppColors.errorRed,
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
          color: const Color(0xFF1E293B).withAlpha(120),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isAlert ? color.withAlpha(140) : const Color(0xFF334155),
            width: isAlert ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withAlpha(35),
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
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
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
        color: Color(0xFF0B1120),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
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
                      selectedColor: AppColors.primaryBlue.withAlpha(60),
                      backgroundColor: const Color(0xFF1E293B),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppColors.primaryBlueLight : const Color(0xFF334155),
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
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search code, incident, action...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF94A3B8)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
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
            CircularProgressIndicator(color: AppColors.primaryBlueLight),
            SizedBox(height: 16),
            Text('Loading approval requests from backend...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.errorRed.withAlpha(100)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.errorRed, size: 36),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadApprovals,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
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
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.task_alt_rounded, color: Color(0xFF64748B), size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Approval Requests Found',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No approval matching search criteria "$_searchQuery".'
                  : 'All autonomous workflows are running normally with no pending gates.',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
        statusColor = AppColors.successGreen;
        statusLabel = 'APPROVED & EXECUTED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'REJECTED':
        statusColor = AppColors.errorRed;
        statusLabel = 'REJECTED BY MANAGER';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'REVISION_REQUESTED':
        statusColor = const Color(0xFF38BDF8);
        statusLabel = 'REVISION REQUESTED';
        statusIcon = Icons.history_edu_rounded;
        break;
      case 'EXPIRED':
        statusColor = const Color(0xFF94A3B8);
        statusLabel = 'EXPIRED / TIMEOUT';
        statusIcon = Icons.timer_off_rounded;
        break;
      default:
        statusColor = const Color(0xFFF59E0B);
        statusLabel = 'PENDING REVIEW';
        statusIcon = Icons.hourglass_top_rounded;
    }

    Color riskColor;
    switch (risk) {
      case 'CRITICAL':
        riskColor = AppColors.errorRed;
        break;
      case 'HIGH':
        riskColor = const Color(0xFFF59E0B);
        break;
      default:
        riskColor = const Color(0xFF38BDF8);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: status == 'PENDING' ? const Color(0xFFF59E0B).withAlpha(120) : const Color(0xFF334155),
          width: status == 'PENDING' ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withAlpha(180),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: const Border(bottom: BorderSide(color: Color(0xFF334155))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF475569)),
                      ),
                      child: Text(
                        code,
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: riskColor.withAlpha(35),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: riskColor.withAlpha(90)),
                      ),
                      child: Text(
                        '$risk RISK',
                        style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Requested by $agent',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(35),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withAlpha(100)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Card Body
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title & Incident Reference
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.link_rounded, color: Color(0xFF64748B), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Linked Incident: $incCode — $incSumm',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (createdAt.isNotEmpty)
                      Text(
                        'Created: ${createdAt.length > 19 ? createdAt.substring(0, 19).replaceAll('T', ' ') : createdAt}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Requested Action Highlight
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 10),
                      const Text(
                        'PROPOSED ACTION:',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          action,
                          style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    desc,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12, height: 1.4),
                  ),
                ],

                // Decision History (If approved, revision, or rejected)
                if (status != 'PENDING' && (approvedBy.isNotEmpty || responseNotes.isNotEmpty)) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withAlpha(60)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_pin_rounded, color: statusColor, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Decision Authority: $approvedBy',
                              style: TextStyle(color: statusColor, fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        if (responseNotes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Remarks: "$responseNotes"',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Action Buttons for PENDING
                if (status == 'PENDING') ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF334155), height: 1),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showRejectDialog(item),
                        icon: const Icon(Icons.block_rounded, size: 14, color: AppColors.errorRed),
                        label: const Text('Reject', style: TextStyle(color: AppColors.errorRed, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.errorRed.withAlpha(100)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => _showRevisionDialog(item),
                        icon: const Icon(Icons.history_edu_rounded, size: 14, color: Color(0xFF38BDF8)),
                        label: const Text('Request Revision', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFF38BDF8).withAlpha(100)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _showApproveDialog(item),
                        icon: const Icon(Icons.check_circle_rounded, size: 15),
                        label: const Text('Authorize & Execute Action', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
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
