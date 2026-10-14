import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';
import '../../data/models/work_order_models.dart';
import '../../core/utils/numeric_parser.dart';

class MaintenanceExecutionScreen extends StatefulWidget {
  final Function(int, {String? targetMachine})? onNavigate;
  final String? initialTicketNumber;

  const MaintenanceExecutionScreen({
    super.key,
    this.onNavigate,
    this.initialTicketNumber,
  });

  @override
  State<MaintenanceExecutionScreen> createState() => _MaintenanceExecutionScreenState();
}

class _MaintenanceExecutionScreenState extends State<MaintenanceExecutionScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  bool _isLoadingList = true;
  bool _isLoadingDetail = false;
  String? _errorMessage;
  String? _actionFeedback;
  bool _actionSuccess = true;

  List<Map<String, dynamic>> _tickets = [];
  int? _selectedTicketId;
  ExecutionDetailResponse? _executionDetail;

  String _statusFilter = 'ALL';
  final String _priorityFilter = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  // Inspection form controllers
  final TextEditingController _confirmedFaultController = TextEditingController();
  final TextEditingController _faultNotesController = TextEditingController();

  // Repair form controllers
  final TextEditingController _repairPerformedController = TextEditingController();
  final TextEditingController _repairDurationController = TextEditingController(text: '45');
  final TextEditingController _remainingIssuesController = TextEditingController();

  // Parts selector
  String? _selectedPartCode;
  final TextEditingController _partQuantityController = TextEditingController(text: '1');

  // Signoff form controllers
  final TextEditingController _signoffUserController = TextEditingController(text: 'Plant Operations Manager');
  final TextEditingController _signoffNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTickets();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _confirmedFaultController.dispose();
    _faultNotesController.dispose();
    _repairPerformedController.dispose();
    _repairDurationController.dispose();
    _remainingIssuesController.dispose();
    _partQuantityController.dispose();
    _signoffUserController.dispose();
    _signoffNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    setState(() {
      _isLoadingList = true;
      _errorMessage = null;
    });

    try {
      final list = await _apiService.fetchMaintenanceTickets(
        status: _statusFilter == 'ALL' ? null : _statusFilter,
        priority: _priorityFilter == 'ALL' ? null : _priorityFilter,
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _tickets = list;
          _isLoadingList = false;
        });

        if (list.isNotEmpty) {
          int targetId = parseIntWithFallback(list.first['id'], 0);
          if (widget.initialTicketNumber != null) {
            final match = list.firstWhere(
              (t) => t['ticket_number'] == widget.initialTicketNumber,
              orElse: () => list.first,
            );
            targetId = parseIntWithFallback(match['id'], 0);
          } else if (_selectedTicketId != null) {
            final exists = list.any((t) => parseIntWithFallback(t['id'], 0) == _selectedTicketId);
            if (exists) targetId = _selectedTicketId!;
          }
          _selectTicket(targetId);
        } else {
          setState(() {
            _selectedTicketId = null;
            _executionDetail = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load maintenance tickets: ${e.toString()}';
          _isLoadingList = false;
        });
      }
    }
  }

  Future<void> _selectTicket(int ticketId) async {
    setState(() {
      _selectedTicketId = ticketId;
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      final jsonMap = await _apiService.fetchWorkOrderExecutionDetail(ticketId);
      if (mounted) {
        if (jsonMap != null) {
          final detail = ExecutionDetailResponse.fromJson(jsonMap);
          setState(() {
            _executionDetail = detail;
            _isLoadingDetail = false;

            // Pre-populate fields
            _confirmedFaultController.text = detail.ticket.confirmedFault;
            _faultNotesController.text = detail.ticket.faultConfirmationNotes;
            _repairPerformedController.text = detail.ticket.repairPerformed;
            if (detail.ticket.actualRepairDurationMinutes > 0) {
              _repairDurationController.text = detail.ticket.actualRepairDurationMinutes.toString();
            }
            if (detail.sparePartsCatalog.isNotEmpty && _selectedPartCode == null) {
              _selectedPartCode = detail.sparePartsCatalog.first['item_code'] as String?;
            }
          });

          // Sync tab with lifecycle state
          final status = detail.ticket.status;
          if (status == 'AWAITING_VERIFICATION' || status == 'VERIFIED') {
            _tabController.animateTo(2); // Go to verification tab
          } else if (status == 'REPAIR_IN_PROGRESS') {
            _tabController.animateTo(1); // Go to repair tab
          }
        } else {
          setState(() {
            _isLoadingDetail = false;
            _errorMessage = 'Could not load execution details for ticket #$ticketId';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetail = false;
          _errorMessage = 'Error loading execution detail: ${e.toString()}';
        });
      }
    }
  }

  // Lifecycle action handler
  Future<void> _handleTransition(String targetState, String reason) async {
    if (_selectedTicketId == null) return;
    setState(() => _isLoadingDetail = true);

    final res = await _apiService.transitionWorkOrder(
      _selectedTicketId!,
      newState: targetState,
      actor: 'Lead Field Specialist',
      reason: reason,
    );

    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      _showFeedback('Work order transitioned to $targetState.', true);
      await _loadTickets();
    }
    setState(() => _isLoadingDetail = false);
  }

  // Inspection submit handler
  Future<void> _submitInspection() async {
    if (_selectedTicketId == null || _executionDetail == null) return;
    final ticket = _executionDetail?.ticket;
    if (ticket != null && (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')) {
      _showFeedback('Diagnostic inspection is already completed for ${ticket.ticketNumber} (${ticket.status}).', false);
      return;
    }

    final fault = _confirmedFaultController.text.trim();
    if (fault.isEmpty) {
      _showFeedback('Please record the confirmed physical fault before proceeding.', false);
      return;
    }

    setState(() => _isLoadingDetail = true);
    final checklistPayload = _executionDetail!.ticket.inspectionChecklist
        .map((item) => item.toJson())
        .toList();

    final res = await _apiService.submitWorkOrderInspection(
      _selectedTicketId!,
      checklist: checklistPayload,
      confirmedFault: fault,
      notes: _faultNotesController.text.trim(),
      actor: 'R. Sharma (Senior Diagnostic Tech)',
    );

    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      _showFeedback('Diagnostic inspection submitted and repair initiated.', true);
      _tabController.animateTo(1);
      await _loadTickets();
    }
    setState(() => _isLoadingDetail = false);
  }

  // Parts consumption handler
  Future<void> _consumePart() async {
    if (_selectedTicketId == null || _selectedPartCode == null) {
      _showFeedback('Please select a spare part from the warehouse inventory.', false);
      return;
    }

    final ticket = _executionDetail?.ticket;
    if (ticket != null && (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')) {
      _showFeedback('Cannot deduct parts: Physical repair is already completed for ${ticket.ticketNumber}.', false);
      return;
    }

    final qty = int.tryParse(_partQuantityController.text) ?? 1;
    setState(() => _isLoadingDetail = true);

    final res = await _apiService.consumeWorkOrderParts(
      _selectedTicketId!,
      parts: [
        {'item_code': _selectedPartCode, 'quantity': qty}
      ],
      actor: 'R. Sharma (Senior Diagnostic Tech)',
    );

    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      _showFeedback('Spare part safely deducted from inventory.', true);
      await _loadTickets();
      await _selectTicket(_selectedTicketId!);
    }
    setState(() => _isLoadingDetail = false);
  }

  // Physical repair completion handler
  Future<void> _completeRepair() async {
    if (_selectedTicketId == null) return;
    final action = _repairPerformedController.text.trim();
    if (action.isEmpty) {
      _showFeedback('Please describe the repair work carried out before completing.', false);
      return;
    }

    final duration = int.tryParse(_repairDurationController.text) ?? 45;
    setState(() => _isLoadingDetail = true);

    final res = await _apiService.completeWorkOrderRepair(
      _selectedTicketId!,
      repairPerformed: action,
      durationMinutes: duration,
      remainingIssues: _remainingIssuesController.text.trim(),
      actor: 'R. Sharma (Senior Diagnostic Tech)',
    );

    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      _showFeedback('Physical repair documented. Machine entered telemetry verification window.', true);
      _tabController.animateTo(2);
      await _loadTickets();
      await _selectTicket(_selectedTicketId!);
    }
    setState(() => _isLoadingDetail = false);
  }

  // Live recovery evaluation handler
  Future<void> _evaluateRecovery() async {
    if (_selectedTicketId == null) return;
    setState(() => _isLoadingDetail = true);

    final res = await _apiService.verifyWorkOrderRecovery(_selectedTicketId!);
    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      final outcome = res['outcome'] as String? ?? 'EVALUATED';
      _showFeedback('Telemetry evaluated: $outcome', true);
      await _loadTickets();
      await _selectTicket(_selectedTicketId!);
    }
    setState(() => _isLoadingDetail = false);
  }

  // Authorized signoff handler
  Future<void> _authorizeReturnToService() async {
    if (_selectedTicketId == null) return;
    final user = _signoffUserController.text.trim();
    if (user.isEmpty) {
      _showFeedback('Please provide the authorized personnel name.', false);
      return;
    }

    setState(() => _isLoadingDetail = true);

    final res = await _apiService.authorizeReturnToService(
      _selectedTicketId!,
      authorizedBy: user,
      notes: _signoffNotesController.text.trim(),
    );

    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      _showFeedback('Machine verified and authorized to return to service.', true);
      await _loadTickets();
      await _selectTicket(_selectedTicketId!);
    }
    setState(() => _isLoadingDetail = false);
  }

  // Evidence-based incident closure
  Future<void> _closeWithEvidence() async {
    if (_selectedTicketId == null) return;
    setState(() => _isLoadingDetail = true);

    final res = await _apiService.transitionWorkOrder(
      _selectedTicketId!,
      newState: 'CLOSED',
      actor: _signoffUserController.text.trim().isNotEmpty
          ? _signoffUserController.text.trim()
          : 'Plant Operations Manager',
      reason: 'Closed following full verification lifecycle.',
    );

    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      _showFeedback('Work order and factory incident closed with verified recovery evidence.', true);
      await _loadTickets();
    }
    setState(() => _isLoadingDetail = false);
  }

  // Demo simulation runner
  Future<void> _runDemoFlow(String mode) async {
    if (_selectedTicketId == null) return;
    final ticket = _executionDetail?.ticket;
    if (ticket != null && (ticket.status == 'CLOSED' || ticket.status == 'CANCELLED')) {
      _showFeedback('Action unavailable: Work order ${ticket.ticketNumber} is ${ticket.status}.', false);
      return;
    }

    setState(() => _isLoadingDetail = true);

    final res = await _apiService.simulateTechnicianFlow(_selectedTicketId!, mode: mode);
    if (res.containsKey('error')) {
      _showFeedback(res['error'].toString(), false);
    } else {
      final isAwaiting = ticket?.status == 'AWAITING_VERIFICATION';
      final msg = isAwaiting
          ? 'Post-repair sensor data simulated ($mode). Evaluated by Recovery Verification Engine.'
          : 'Simulated technician flow executed ($mode). Post-repair telemetry generated.';
      _showFeedback(msg, true);
      _tabController.animateTo(2);
      await _loadTickets();
      await _selectTicket(_selectedTicketId!);
    }
    setState(() => _isLoadingDetail = false);
  }

  void _showFeedback(String msg, bool isSuccess) {
    if (!mounted) return;
    setState(() {
      _actionFeedback = msg;
      _actionSuccess = isSuccess;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: Column(
        children: [
          _buildTopHeader(),
          if (_actionFeedback != null) _buildFeedbackBanner(),
          if (_errorMessage != null) _buildErrorBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Panel: Work Orders List
                SizedBox(
                  width: 360,
                  child: _buildMasterListPanel(),
                ),
                Container(width: 1, color: TexoraColors.cardBorder),
                // Right Panel: Detailed Execution Workspace
                Expanded(
                  child: _buildExecutionDetailPanel(),
                ),
              ],
            ),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x20EA580C),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.build_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Maintenance Execution Center',
                    style: TextStyle(
                      color: TexoraColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'AI-Guided Field Repairs • Sensor Verification • Evidence-Based Incident Closure',
                    style: TextStyle(
                      color: TexoraColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              // Navigation Quick Links
              if (widget.onNavigate != null) ...[
                OutlinedButton.icon(
                  onPressed: () => widget.onNavigate!(3), // Incident Intelligence
                  icon: const Icon(Icons.insights_rounded, size: 14, color: TexoraColors.primary),
                  label: const Text('Incidents', style: TextStyle(color: TexoraColors.primary, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: TexoraColors.cardBorder),
                    backgroundColor: TexoraColors.tableHeaderBg,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              IconButton(
                onPressed: _loadTickets,
                icon: const Icon(Icons.refresh_rounded, color: TexoraColors.textSecondary),
                tooltip: 'Refresh Work Orders',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: _actionSuccess
          ? TexoraColors.badgeSuccessBg
          : TexoraColors.badgeDangerBg,
      child: Row(
        children: [
          Icon(
            _actionSuccess ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: _actionSuccess ? TexoraColors.badgeSuccessText : TexoraColors.badgeDangerText,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _actionFeedback!,
              style: TextStyle(
                color: _actionSuccess ? TexoraColors.badgeSuccessText : TexoraColors.badgeDangerText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _actionFeedback = null),
            icon: Icon(
              Icons.close,
              color: _actionSuccess ? TexoraColors.badgeSuccessText : TexoraColors.badgeDangerText,
              size: 16,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: TexoraColors.badgeDangerBg,
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: TexoraColors.badgeDangerText, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: TexoraColors.badgeDangerText, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // LEFT PANEL: WORK ORDERS MASTER LIST
  // -------------------------------------------------------------
  Widget _buildMasterListPanel() {
    return Container(
      color: TexoraColors.cardBg,
      child: Column(
        children: [
          // Filter & Search Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _loadTickets(),
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Search ticket, machine, or fault...',
                    hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16, color: TexoraColors.textMuted),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14, color: TexoraColors.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              _loadTickets();
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: TexoraColors.workspaceBg,
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
                      borderSide: const BorderSide(color: TexoraColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ALL', 'ALL'),
                      _buildFilterChip('CREATED', 'CREATED'),
                      _buildFilterChip('ACCEPTED', 'ACCEPTED'),
                      _buildFilterChip('INSPECTION', 'INSPECTION_IN_PROGRESS'),
                      _buildFilterChip('REPAIRING', 'REPAIR_IN_PROGRESS'),
                      _buildFilterChip('VERIFYING', 'AWAITING_VERIFICATION'),
                      _buildFilterChip('VERIFIED', 'VERIFIED'),
                      _buildFilterChip('CLOSED', 'CLOSED'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: TexoraColors.cardBorder, height: 1),
          // Ticket items list
          Expanded(
            child: _isLoadingList
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFEA580C)))
                : _tickets.isEmpty
                    ? const Center(
                        child: Text(
                          'No maintenance work orders found',
                          style: TextStyle(color: TexoraColors.textMuted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _tickets.length,
                        itemBuilder: (context, index) {
                          final t = _tickets[index];
                          final isSelected = t['id'] == _selectedTicketId;
                          return _buildTicketListItem(t, isSelected);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final active = _statusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 10, color: active ? Colors.white : TexoraColors.textSecondary, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        selected: active,
        selectedColor: const Color(0xFFEA580C),
        backgroundColor: TexoraColors.tableHeaderBg,
        side: const BorderSide(color: TexoraColors.cardBorder),
        onSelected: (_) {
          setState(() => _statusFilter = value);
          _loadTickets();
        },
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildTicketListItem(Map<String, dynamic> t, bool isSelected) {
    final status = t['status'] as String? ?? 'CREATED';
    final priority = t['priority'] as String? ?? 'MEDIUM';
    final machineCode = t['machine_code'] as String? ?? '';
    final ticketNumber = t['ticket_number'] as String? ?? '';
    final technician = t['assigned_technician'] as String? ?? 'Unassigned';
    final verStatus = t['verification_status'] as String? ?? 'PENDING_EVIDENCE';

    return InkWell(
      onTap: () => _selectTicket(parseIntWithFallback(t['id'], 0)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? TexoraColors.badgeInfoBg : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? const Color(0xFFEA580C) : Colors.transparent,
              width: 3,
            ),
            bottom: const BorderSide(color: TexoraColors.cardBorder, width: 0.8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ticketNumber,
                  style: const TextStyle(
                    color: TexoraColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                _buildPriorityBadge(priority),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: TexoraColors.tableHeaderBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: TexoraColors.cardBorder),
                  ),
                  child: Text(
                    machineCode,
                    style: const TextStyle(color: TexoraColors.primary, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    t['title'] as String? ?? '',
                    style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusPill(status),
                _buildVerificationPill(verStatus),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 12, color: TexoraColors.textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    technician,
                    style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // RIGHT PANEL: DETAILED EXECUTION WORKSPACE
  // -------------------------------------------------------------
  Widget _buildExecutionDetailPanel() {
    if (_isLoadingDetail) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFEA580C)));
    }
    if (_executionDetail == null) {
      return const Center(
        child: Text(
          'Select a work order from the list to begin maintenance execution.',
          style: TextStyle(color: TexoraColors.textMuted, fontSize: 14),
        ),
      );
    }

    final ticket = _executionDetail!.ticket;

    return Column(
      children: [
        _buildTicketSummaryHeader(ticket),
        _buildLifecycleProgressTimeline(ticket.status),
        // Tabs
        Container(
          decoration: const BoxDecoration(
            color: TexoraColors.cardBg,
            border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFEA580C),
            labelColor: const Color(0xFFEA580C),
            unselectedLabelColor: TexoraColors.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            tabs: const [
              Tab(icon: Icon(Icons.checklist_rtl_rounded, size: 16), text: '1. AI Investigation & Checklist'),
              Tab(icon: Icon(Icons.hardware_rounded, size: 16), text: '2. Physical Repair & Spare Parts'),
              Tab(icon: Icon(Icons.verified_rounded, size: 16), text: '3. Recovery Verification'),
              Tab(icon: Icon(Icons.history_rounded, size: 16), text: '4. History & Audit Trail'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTabInvestigation(ticket),
              _buildTabPhysicalRepair(ticket),
              _buildTabVerificationDashboard(ticket),
              _buildTabHistoryAndAudit(ticket),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTicketSummaryHeader(WorkOrderTicket ticket) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
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
                    Text(
                      ticket.ticketNumber,
                      style: const TextStyle(
                        color: TexoraColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildPriorityBadge(ticket.priority),
                    const SizedBox(width: 8),
                    _buildStatusPill(ticket.status),
                    if (ticket.isSimulation) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: TexoraColors.tableHeaderBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: TexoraColors.cardBorder),
                        ),
                        child: const Text('FIELD SIMULATION VERIFICATION', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              // Controlled Field Simulation Actions
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (ticket.status == 'CLOSED' || ticket.status == 'CANCELLED')
                        ? null
                        : () => _runDemoFlow('HEALTHY'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 14, color: Color(0xFF10B981)),
                    label: const Text('Simulate Repair (Healthy)', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: (ticket.status == 'CLOSED' || ticket.status == 'CANCELLED')
                            ? TexoraColors.cardBorder
                            : const Color(0xFF10B981),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: (ticket.status == 'CLOSED' || ticket.status == 'CANCELLED')
                        ? null
                        : () => _runDemoFlow('FAULTY'),
                    icon: const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                    label: const Text('Simulate Repair (Faulty)', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: (ticket.status == 'CLOSED' || ticket.status == 'CANCELLED')
                            ? TexoraColors.cardBorder
                            : const Color(0xFFEF4444),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Machine: ${ticket.machineCode} — ${ticket.machineName} (${ticket.departmentName})',
                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
              ),
              if (ticket.incidentReference.isNotEmpty) ...[
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: TexoraColors.badgeDangerBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    'Incident: ${ticket.incidentReference}',
                    style: const TextStyle(color: TexoraColors.badgeDangerText, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLifecycleProgressTimeline(String currentStatus) {
    final stages = [
      'CREATED',
      'ACCEPTED',
      'INSPECTION_IN_PROGRESS',
      'REPAIR_IN_PROGRESS',
      'REPAIR_COMPLETED',
      'AWAITING_VERIFICATION',
      'VERIFIED',
      'CLOSED',
    ];

    int currentIndex = stages.indexOf(currentStatus);
    if (currentIndex == -1) {
      if (currentStatus == 'OPEN') currentIndex = 0;
      if (currentStatus == 'IN_PROGRESS') currentIndex = 3;
      if (currentStatus == 'RESOLVED') currentIndex = 6;
      if (currentStatus == 'VERIFICATION_FAILED') currentIndex = 5;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        children: List.generate(stages.length, (idx) {
          final isPast = idx < currentIndex;
          final isCurrent = idx == currentIndex;
          final label = _formatStageLabel(stages[idx]);

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: isPast
                              ? const Color(0xFF10B981)
                              : isCurrent
                                  ? const Color(0xFFEA580C)
                                  : TexoraColors.cardBorder,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 9,
                          color: isCurrent
                              ? const Color(0xFFEA580C)
                              : isPast
                                  ? const Color(0xFF10B981)
                                  : TexoraColors.textMuted,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (idx < stages.length - 1)
                  const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  String _formatStageLabel(String stage) {
    switch (stage) {
      case 'CREATED':
        return '1. Created';
      case 'ACCEPTED':
        return '2. Accepted';
      case 'INSPECTION_IN_PROGRESS':
        return '3. Inspecting';
      case 'REPAIR_IN_PROGRESS':
        return '4. Repairing';
      case 'REPAIR_COMPLETED':
        return '5. Repaired';
      case 'AWAITING_VERIFICATION':
        return '6. Verifying';
      case 'VERIFIED':
        return '7. Verified';
      case 'CLOSED':
        return '8. Closed';
      default:
        return stage;
    }
  }

  // -------------------------------------------------------------
  // TAB 1: AI GUIDED INVESTIGATION & CHECKLIST
  // -------------------------------------------------------------
  Widget _buildTabInvestigation(WorkOrderTicket ticket) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Suspected Causes Box (Framed strictly as hypotheses)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDDD6FE)),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.psychology_rounded, color: Color(0xFF7C3AED), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'AI Health Specialist Investigation (Potential Causes)',
                      style: TextStyle(
                        color: TexoraColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    Text(
                      'DIAGNOSTIC HYPOTHESES — TECHNICIAN CONFIRMATION REQUIRED',
                      style: TextStyle(color: Color(0xFF7C3AED), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'The AI specialist analyzed telemetry frequency patterns and identified the following potential causes. '
                  'These are hypotheses, not confirmed diagnoses. Technicians must conduct physical inspection to confirm the actual root cause.',
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: ticket.aiSuspectedCauses.map((cause) {
                    final name = cause['cause'] as String? ?? '';
                    final likelihood = cause['likelihood'] as String? ?? 'MEDIUM';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: TexoraColors.tableHeaderBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: TexoraColors.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bubble_chart_outlined, size: 12, color: _likelihoodColor(likelihood)),
                          const SizedBox(width: 6),
                          Text(name, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: _likelihoodColor(likelihood).withAlpha(30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              likelihood,
                              style: TextStyle(color: _likelihoodColor(likelihood), fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Guided Inspection Checklist
          const Text(
            'Technician Guided Inspection Checklist',
            style: TextStyle(color: TexoraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Conduct physical checks and record measured values before disassembly.',
            style: TextStyle(color: TexoraColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TexoraColors.cardBorder),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ticket.inspectionChecklist.length,
              separatorBuilder: (_, _) => const Divider(color: TexoraColors.cardBorder, height: 1),
              itemBuilder: (context, idx) {
                final item = ticket.inspectionChecklist[idx];
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: TexoraColors.tableHeaderBg,
                        child: Text('${item.stepId}', style: const TextStyle(color: TexoraColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.task, style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
                            if (item.expectedThreshold.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text('Expected threshold: ${item.expectedThreshold}', style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10)),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                SizedBox(
                                  width: 220,
                                  height: 32,
                                  child: TextField(
                                    style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11),
                                    decoration: InputDecoration(
                                      hintText: 'Observed value / reading',
                                      hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      filled: true,
                                      fillColor: TexoraColors.workspaceBg,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                                    ),
                                    onChanged: (val) => item.observedValue = val,
                                    controller: TextEditingController(text: item.observedValue)
                                      ..selection = TextSelection.collapsed(offset: item.observedValue.length),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                DropdownButton<String>(
                                  value: item.status,
                                  dropdownColor: TexoraColors.cardBg,
                                  style: const TextStyle(fontSize: 11),
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: 'PENDING', child: Text('PENDING', style: TextStyle(color: TexoraColors.textMuted))),
                                    DropdownMenuItem(value: 'PASS', child: Text('PASS', style: TextStyle(color: Color(0xFF10B981)))),
                                    DropdownMenuItem(value: 'DEFECT_FOUND', child: Text('DEFECT FOUND', style: TextStyle(color: Color(0xFFEF4444)))),
                                    DropdownMenuItem(value: 'SKIPPED', child: Text('SKIPPED', style: TextStyle(color: TexoraColors.textMuted))),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => item.status = val);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),

          // Fault Confirmation & Next Action
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDBA74)),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: Color(0xFFEA580C), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Technician Physical Fault Confirmation',
                      style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmedFaultController,
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Confirmed Physical Fault *',
                    labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                    hintText: 'e.g. Deep groove ball bearing #6204 inner race fatigue spalling and micro-cracking',
                    hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                    filled: true,
                    fillColor: TexoraColors.workspaceBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _faultNotesController,
                  maxLines: 2,
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Diagnostic Findings & Observations',
                    labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                    hintText: 'Acoustic stethoscope inspection detected high frequency squeal. Thermal probe registered 76.4°C.',
                    hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                    filled: true,
                    fillColor: TexoraColors.workspaceBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (ticket.status == 'CREATED' || ticket.status == 'OPEN' || ticket.status == 'ASSIGNED')
                      ElevatedButton.icon(
                        onPressed: () => _handleTransition('ACCEPTED', 'Technician accepted assignment'),
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text('Accept Work Order', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: TexoraColors.primary, foregroundColor: Colors.white),
                      ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                          ? () => _showFeedback('Diagnostic inspection is already completed for ${ticket.ticketNumber}.', false)
                          : _submitInspection,
                      icon: Icon(
                        (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                            ? Icons.check_circle_outline
                            : Icons.send_rounded,
                        size: 14,
                      ),
                      label: Text(
                        (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                            ? 'Inspection Documented'
                            : 'Submit Inspection & Begin Physical Repair',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                            ? TexoraColors.textMuted
                            : const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 2: PHYSICAL REPAIR & SPARE PARTS
  // -------------------------------------------------------------
  Widget _buildTabPhysicalRepair(WorkOrderTicket ticket) {
    final catalog = _executionDetail!.sparePartsCatalog;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Repair Documentation Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TexoraColors.cardBorder),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Physical Repair Documentation',
                  style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _repairPerformedController,
                  maxLines: 4,
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'Repair Work Carried Out *',
                    labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                    hintText: 'Disassembled main drive shaft assembly. Removed bearing #6204. Flushed housing and installed new SKF bearing with induction heater. Repacked with synthetic grease and realigned drive belt.',
                    hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                    filled: true,
                    fillColor: TexoraColors.workspaceBg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _repairDurationController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Actual Duration (Minutes) *',
                          labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.workspaceBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _remainingIssuesController,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Remaining Observations / Pending Adjustments',
                          labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                          hintText: 'None. Rotates smoothly with zero binding.',
                          hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                          filled: true,
                          fillColor: TexoraColors.workspaceBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Spare Parts Allocation & Warehouse Safety Barrier
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TexoraColors.cardBorder),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Spare Parts Allocation & Stock Transaction',
                      style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'SAFETY BARRIER: TRANSACTION-SAFE INVENTORY DEDUCTION',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedPartCode,
                        dropdownColor: TexoraColors.cardBg,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Select Warehouse Part',
                          labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.workspaceBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                        ),
                        items: catalog.map((p) {
                          final code = p['item_code'] as String;
                          final name = p['name'] as String;
                          final stock = parseDoubleWithFallback(p['current_stock'], 0.0, fieldName: 'current_stock');
                          return DropdownMenuItem(
                            value: code,
                            child: Text('$code — $name (Stock: $stock)', maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _selectedPartCode = val),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _partQuantityController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Qty',
                          labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                          filled: true,
                          fillColor: TexoraColors.workspaceBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                          ? () => _showFeedback('Cannot deduct parts: Physical repair is already completed for ${ticket.ticketNumber}.', false)
                          : _consumePart,
                      icon: Icon(
                        (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                            ? Icons.lock_outline
                            : Icons.add_shopping_cart,
                        size: 14,
                      ),
                      label: Text(
                        (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                            ? 'Stock Locked'
                            : 'Deduct Stock',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (ticket.status == 'AWAITING_VERIFICATION' || ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                            ? TexoraColors.textMuted
                            : const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Parts Consumed List
                if (ticket.partsReplaced.isNotEmpty) ...[
                  const Text('Parts Consumed for this Work Order:', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: TexoraColors.tableHeaderBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: TexoraColors.cardBorder),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ticket.partsReplaced.length,
                      separatorBuilder: (_, _) => const Divider(color: TexoraColors.cardBorder, height: 1),
                      itemBuilder: (context, idx) {
                        final part = ticket.partsReplaced[idx];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                          title: Text(
                            '${part['name'] ?? part['item_code']} (${part['item_code']})',
                            style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                          ),
                          subtitle: Text(
                            'Deducted: ${part['quantity']} ${part['unit'] ?? 'PCS'} • Safe reference registered',
                            style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10),
                          ),
                          trailing: const Text('LEDGER LOCKED', style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold)),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action button to complete repair
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (ticket.status == 'AWAITING_VERIFICATION')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: TexoraColors.badgeSuccessBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Physical Repair Completed • Awaiting Verification',
                        style: TextStyle(color: TexoraColors.badgeSuccessText, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        onPressed: () => _tabController.animateTo(2),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                        label: const Text('Go to Verification Dashboard', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TexoraColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                )
              else if (ticket.status == 'VERIFIED' || ticket.status == 'CLOSED')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: TexoraColors.badgeInfoBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, color: TexoraColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Work Order ${ticket.status} — Physical Repair Signed Off',
                        style: const TextStyle(color: TexoraColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _completeRepair,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Complete Physical Repair & Enter Telemetry Verification Window', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEA580C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: RECOVERY VERIFICATION DASHBOARD
  // -------------------------------------------------------------
  Widget _buildTabVerificationDashboard(WorkOrderTicket ticket) {
    final eval = _executionDetail!.verificationEvaluation;
    final limits = _executionDetail!.limits;
    final trend = _executionDetail!.telemetryTrend;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Evaluation Banner
          _buildVerificationOutcomeBanner(eval.outcome, eval.summary),
          const SizedBox(height: 20),

          // Telemetry Before & After Trend Visualization
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TexoraColors.cardBorder),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Multi-Sample Telemetry Trend & Operating Threshold Comparison',
                      style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: _evaluateRecovery,
                      icon: const Icon(Icons.sync_rounded, size: 14),
                      label: const Text('Re-Evaluate Live Engine', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TexoraColors.tableHeaderBg,
                        foregroundColor: TexoraColors.primary,
                        elevation: 0,
                        side: const BorderSide(color: TexoraColors.cardBorder),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Telemetry metrics cards
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        'Observed Peak Vibration',
                        '${eval.maxVibration.toStringAsFixed(2)} mm/s',
                        'Limit: < ${limits.warningVibrationMms} mm/s',
                        eval.maxVibration <= limits.warningVibrationMms,
                        Icons.vibration_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Observed Peak Temperature',
                        '${eval.maxTemp.toStringAsFixed(1)} °C',
                        'Limit: < ${limits.warningTempC} °C',
                        eval.maxTemp <= limits.warningTempC,
                        Icons.thermostat_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Telemetry Window Samples',
                        '${eval.readingsCount} samples',
                        'Required: 5 consecutive',
                        eval.readingsCount >= 5,
                        Icons.timelapse_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        'Sensor Stability',
                        eval.isStable ? 'STABLE' : 'VOLATILE',
                        'Delta < 1.2 mm/s',
                        eval.isStable,
                        Icons.equalizer_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Data Points Table
                const Text('Recent Sensor Readings (Pre & Post Repair):', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: TexoraColors.cardBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: TexoraColors.cardBorder),
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                      4: FlexColumnWidth(2),
                      5: FlexColumnWidth(2),
                    },
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: TexoraColors.tableHeaderBg),
                        children: [
                          Padding(padding: EdgeInsets.all(8), child: Text('Time', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Vibration (mm/s)', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Temperature (°C)', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Speed (RPM)', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Power (kW)', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                          Padding(padding: EdgeInsets.all(8), child: Text('Threshold Status', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold))),
                        ],
                      ),
                      ...trend.take(6).map((pt) {
                        final vibExceeded = pt.vibrationMms >= limits.warningVibrationMms;
                        return TableRow(
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: TexoraColors.cardBorder, width: 0.5)),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                '${pt.timestamp.hour.toString().padLeft(2, '0')}:${pt.timestamp.minute.toString().padLeft(2, '0')}:${pt.timestamp.second.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                pt.vibrationMms.toStringAsFixed(2),
                                style: TextStyle(
                                  color: vibExceeded ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Padding(padding: const EdgeInsets.all(8), child: Text('${pt.temperatureC.toStringAsFixed(1)} °C', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11))),
                            Padding(padding: const EdgeInsets.all(8), child: Text(pt.speedRpm.toStringAsFixed(0), style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11))),
                            Padding(padding: const EdgeInsets.all(8), child: Text(pt.powerKw.toStringAsFixed(1), style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11))),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                vibExceeded ? 'EXCEEDED' : 'NOMINAL',
                                style: TextStyle(
                                  color: vibExceeded ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Verification Checks Matrix & Authorized Sign-Off
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TexoraColors.cardBorder),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Authorized Personnel Sign-Off & Return to Service Gate',
                  style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Safety protocol mandates human verification: Even when telemetry normalizes, qualified operations personnel '
                  'must authorize the machine restart and return to service.',
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 12),
                if (ticket.authorizedSignoffBy.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TexoraColors.badgeSuccessBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: Color(0xFF10B981), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Authorized by: ${ticket.authorizedSignoffBy}',
                                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              if (ticket.signoffNotes.isNotEmpty)
                                Text(
                                  'Notes: ${ticket.signoffNotes}',
                                  style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _closeWithEvidence,
                        icon: const Icon(Icons.lock_rounded, size: 14),
                        label: const Text('Close Factory Incident with Verified Evidence', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _signoffUserController,
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                          decoration: InputDecoration(
                            labelText: 'Authorized Personnel Name & Role *',
                            labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                            filled: true,
                            fillColor: TexoraColors.workspaceBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _signoffNotesController,
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                          decoration: InputDecoration(
                            labelText: 'Authorization Notes',
                            labelStyle: const TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                            hintText: 'Observed vibration normalized at full production speed.',
                            hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 11),
                            filled: true,
                            fillColor: TexoraColors.workspaceBg,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: eval.isHealthy ? _authorizeReturnToService : null,
                        icon: const Icon(Icons.verified_user_rounded, size: 14),
                        label: const Text('Authorize Safe Return to Service', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: TexoraColors.tableHeaderBg,
                          disabledForegroundColor: TexoraColors.textMuted,
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

  Widget _buildVerificationOutcomeBanner(String outcome, String summary) {
    Color bannerBg;
    Color bannerBorder;
    Color bannerText;
    IconData bannerIcon;

    switch (outcome) {
      case 'VERIFIED':
        bannerBg = TexoraColors.badgeSuccessBg;
        bannerBorder = const Color(0xFF86EFAC);
        bannerText = TexoraColors.badgeSuccessText;
        bannerIcon = Icons.verified_rounded;
        break;
      case 'PASSED_TELEMETRY_CHECKS':
      case 'AWAITING_AUTHORIZED_SIGNOFF':
        bannerBg = TexoraColors.badgeInfoBg;
        bannerBorder = const Color(0xFFBAE6FD);
        bannerText = TexoraColors.primary;
        bannerIcon = Icons.hourglass_top_rounded;
        break;
      case 'MONITORING':
        bannerBg = TexoraColors.badgeWarningBg;
        bannerBorder = const Color(0xFFFDE68A);
        bannerText = TexoraColors.badgeWarningText;
        bannerIcon = Icons.monitor_heart_rounded;
        break;
      case 'FAILED':
        bannerBg = TexoraColors.badgeDangerBg;
        bannerBorder = const Color(0xFFFECACA);
        bannerText = TexoraColors.badgeDangerText;
        bannerIcon = Icons.cancel_rounded;
        break;
      case 'INCONCLUSIVE':
        bannerBg = const Color(0xFFFAF5FF);
        bannerBorder = const Color(0xFFDDD6FE);
        bannerText = const Color(0xFF7C3AED);
        bannerIcon = Icons.help_outline_rounded;
        break;
      default:
        bannerBg = TexoraColors.tableHeaderBg;
        bannerBorder = TexoraColors.cardBorder;
        bannerText = TexoraColors.textSecondary;
        bannerIcon = Icons.pending_actions_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bannerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bannerIcon, color: bannerText, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Verification Status: $outcome',
                      style: TextStyle(color: bannerText, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, bool isNominal, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TexoraColors.tableHeaderBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNominal ? const Color(0xFF86EFAC) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10)),
              Icon(icon, size: 14, color: isNominal ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: isNominal ? TexoraColors.textPrimary : const Color(0xFFDC2626),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 4: HISTORY & AUDIT TRAIL
  // -------------------------------------------------------------
  Widget _buildTabHistoryAndAudit(WorkOrderTicket ticket) {
    final transitions = ticket.transitions;
    final history = _executionDetail!.maintenanceHistory;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Immutable Work Order State Transitions:', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: TexoraColors.cardBorder),
            ),
            child: transitions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No transitions recorded yet.', style: TextStyle(color: TexoraColors.textMuted, fontSize: 12)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: transitions.length,
                    separatorBuilder: (_, _) => const Divider(color: TexoraColors.cardBorder, height: 1),
                    itemBuilder: (context, idx) {
                      final tr = transitions[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.arrow_circle_right, color: Color(0xFFEA580C), size: 16),
                        title: Text('${tr.previousState} ➔ ${tr.newState}', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Text('By ${tr.actor} (${tr.actorRole}) • ${tr.reason}', style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10)),
                        trailing: Text(
                          '${tr.timestamp.hour.toString().padLeft(2, '0')}:${tr.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 20),

          const Text('Historical Asset Maintenance Log:', style: TextStyle(color: TexoraColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: TexoraColors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: TexoraColors.cardBorder),
            ),
            child: history.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No previous service events recorded.', style: TextStyle(color: TexoraColors.textMuted, fontSize: 12)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: history.length,
                    separatorBuilder: (_, _) => const Divider(color: TexoraColors.cardBorder, height: 1),
                    itemBuilder: (context, idx) {
                      final h = history[idx];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.build, color: TexoraColors.primary, size: 16),
                        title: Text(h['summary'] as String? ?? 'Service event', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12)),
                        subtitle: Text('Type: ${h['maintenance_type']} • Downtime: ${h['downtime_minutes']} mins', style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // HELPER BADGES & PILLS
  // -------------------------------------------------------------
  Widget _buildPriorityBadge(String priority) {
    Color color;
    switch (priority) {
      case 'CRITICAL':
        color = const Color(0xFFEF4444);
        break;
      case 'HIGH':
        color = const Color(0xFFF97316);
        break;
      case 'MEDIUM':
        color = const Color(0xFFF59E0B);
        break;
      default:
        color = const Color(0xFF3B82F6);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        priority,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    Color color;
    switch (status) {
      case 'CLOSED':
      case 'RESOLVED':
        color = const Color(0xFF10B981);
        break;
      case 'VERIFIED':
        color = const Color(0xFF0D9488);
        break;
      case 'AWAITING_VERIFICATION':
        color = TexoraColors.primary;
        break;
      case 'REPAIR_COMPLETED':
        color = const Color(0xFF6366F1);
        break;
      case 'REPAIR_IN_PROGRESS':
      case 'IN_PROGRESS':
        color = const Color(0xFFEA580C);
        break;
      case 'INSPECTION_IN_PROGRESS':
        color = const Color(0xFFA855F7);
        break;
      case 'ACCEPTED':
      case 'ASSIGNED':
        color = const Color(0xFF0284C7);
        break;
      case 'VERIFICATION_FAILED':
        color = const Color(0xFFEF4444);
        break;
      default:
        color = TexoraColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildVerificationPill(String verStatus) {
    Color color;
    switch (verStatus) {
      case 'VERIFIED':
        color = const Color(0xFF10B981);
        break;
      case 'PASSED_TELEMETRY_CHECKS':
      case 'AWAITING_AUTHORIZED_SIGNOFF':
        color = TexoraColors.primary;
        break;
      case 'MONITORING':
        color = const Color(0xFFF59E0B);
        break;
      case 'FAILED':
        color = const Color(0xFFEF4444);
        break;
      default:
        color = TexoraColors.textMuted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        verStatus.replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w600),
      ),
    );
  }

  Color _likelihoodColor(String likelihood) {
    switch (likelihood.toUpperCase()) {
      case 'HIGH':
        return const Color(0xFFEF4444);
      case 'MEDIUM':
        return const Color(0xFFF59E0B);
      default:
        return TexoraColors.primary;
    }
  }
}
