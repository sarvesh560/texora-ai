import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/services/api_service.dart';

class AuditTrailScreen extends StatefulWidget {
  final VoidCallback? onClose;

  const AuditTrailScreen({super.key, this.onClose});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _auditLogs = [];

  String _selectedEntityType = 'ALL';
  String _selectedActorType = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAuditLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final logs = await _apiService.fetchAuditLogs(
        entityType: _selectedEntityType == 'ALL' ? null : _selectedEntityType,
        actorType: _selectedActorType == 'ALL' ? null : _selectedActorType,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) {
        setState(() {
          _auditLogs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load audit logs: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    return _auditLogs.where((log) {
      final q = _searchQuery.toLowerCase();
      final entId = (log['entity_id'] ?? '').toString().toLowerCase();
      final actorId = (log['actor_id'] ?? '').toString().toLowerCase();
      final desc = (log['description'] ?? '').toString().toLowerCase();
      final action = (log['action'] ?? '').toString().toLowerCase();

      final matchesQ = q.isEmpty ||
          entId.contains(q) ||
          actorId.contains(q) ||
          desc.contains(q) ||
          action.contains(q);

      final entType = (log['entity_type'] ?? '').toString();
      final matchesEnt = _selectedEntityType == 'ALL' || entType == _selectedEntityType;

      final actorType = (log['actor_type'] ?? '').toString();
      final matchesActor = _selectedActorType == 'ALL' || actorType == _selectedActorType;

      return matchesQ && matchesEnt && matchesActor;
    }).toList();
  }

  void _showPayloadModal(Map<String, dynamic> log) {
    final payload = log['changes_payload'];
    final jsonStr = payload != null
        ? const JsonEncoder.withIndent('  ').convert(payload)
        : '{}';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: TexoraColors.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: TexoraColors.cardBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.code_rounded, color: TexoraColors.primaryBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Audit Payload [${log['entity_type']}:${log['entity_id']}]',
                  style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TexoraColors.inputBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TexoraColors.cardBorder),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  jsonStr,
                  style: const TextStyle(
                    color: TexoraColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close', style: TextStyle(color: TexoraColors.textMuted)),
            ),
          ],
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
          _buildHeader(),

          // Filter Controls
          _buildFilterBar(),

          // Main Table / List
          Expanded(
            child: _buildLogTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (widget.onClose != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: TexoraColors.primaryBlue),
              onPressed: widget.onClose,
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
          ],
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
                        color: TexoraColors.purple.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shield_outlined, color: TexoraColors.purple, size: 20),
                    ),
                    const Text(
                      'Immutable Audit Trail & Governance',
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
                        'Append-Only Cryptographic Log',
                        style: TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Complete traceability of AI agent inferences, human manager approvals, telemetry anomalies, and machine interventions.',
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _loadAuditLogs,
            icon: const Icon(Icons.refresh_rounded, size: 16, color: TexoraColors.textSecondary),
            label: const Text('Refresh Logs', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: TexoraColors.cardBorder),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        children: [
          // Entity Type Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: TexoraColors.inputBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TexoraColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedEntityType,
                dropdownColor: TexoraColors.cardBg,
                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All Entities')),
                  DropdownMenuItem(value: 'INCIDENT', child: Text('Incidents')),
                  DropdownMenuItem(value: 'AGENT', child: Text('AI Agent Runs')),
                  DropdownMenuItem(value: 'APPROVAL', child: Text('Manager Approvals')),
                  DropdownMenuItem(value: 'MACHINE', child: Text('Machines')),
                  DropdownMenuItem(value: 'TICKET', child: Text('Work Orders')),
                  DropdownMenuItem(value: 'ORDER', child: Text('Production Orders')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedEntityType = val);
                    _loadAuditLogs();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Actor Type Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: TexoraColors.inputBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TexoraColors.cardBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedActorType,
                dropdownColor: TexoraColors.cardBg,
                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('All Actors')),
                  DropdownMenuItem(value: 'AI_AGENT', child: Text('AI Agents')),
                  DropdownMenuItem(value: 'MANAGER', child: Text('Managers / Directors')),
                  DropdownMenuItem(value: 'OPERATOR', child: Text('Floor Operators')),
                  DropdownMenuItem(value: 'SYSTEM', child: Text('System Daemons')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedActorType = val);
                    _loadAuditLogs();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Search Field
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search entity ID, actor, description, or action...',
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
          ),
        ],
      ),
    );
  }

  Widget _buildLogTable() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: TexoraColors.primaryBlue),
            SizedBox(height: 16),
            Text('Loading audit trail records...', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: const TextStyle(color: TexoraColors.critical, fontSize: 13)),
      );
    }

    final logs = _filteredLogs;

    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'No Audit Logs Found',
          style: TextStyle(color: TexoraColors.textMuted, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TexoraColors.cardBorder),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(160), // Timestamp
            1: FixedColumnWidth(120), // Entity
            2: FixedColumnWidth(160), // Action
            3: FixedColumnWidth(160), // Actor
            4: FlexColumnWidth(),    // Description
            5: FixedColumnWidth(90),  // Payload Inspect
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Table Header
            TableRow(
              decoration: const BoxDecoration(
                color: TexoraColors.workspaceBg,
                border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 1.2)),
              ),
              children: [
                _buildHeaderCell('TIMESTAMP'),
                _buildHeaderCell('ENTITY'),
                _buildHeaderCell('ACTION'),
                _buildHeaderCell('ACTOR / ROLE'),
                _buildHeaderCell('DESCRIPTION & CONTEXT'),
                _buildHeaderCell('DETAILS'),
              ],
            ),

            // Rows
            ...logs.map((log) {
              final ts = log['timestamp']?.toString() ?? '';
              final entType = log['entity_type'] ?? '';
              final entId = log['entity_id'] ?? '';
              final action = log['action'] ?? '';
              final actorType = log['actor_type'] ?? '';
              final actorId = log['actor_id'] ?? '';
              final desc = log['description'] ?? '';

              Color actorColor = TexoraColors.textSecondary;
              if (actorType == 'AI_AGENT') actorColor = TexoraColors.purple;
              if (actorType == 'MANAGER') actorColor = TexoraColors.success;
              if (actorType == 'OPERATOR') actorColor = TexoraColors.info;

              return TableRow(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: TexoraColors.cardBorder, width: 0.8)),
                ),
                children: [
                  // Timestamp
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      ts.length > 19 ? ts.substring(0, 19).replaceAll('T', ' ') : ts,
                      style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),

                  // Entity
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entType,
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          entId,
                          style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),

                  // Action
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: TexoraColors.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: TexoraColors.cardBorder),
                      ),
                      child: Text(
                        action,
                        style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),

                  // Actor
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          actorType,
                          style: TextStyle(color: actorColor, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          actorId,
                          style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Description
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      desc,
                      style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11.5, height: 1.3),
                    ),
                  ),

                  // Details Inspect Button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: IconButton(
                      icon: const Icon(Icons.code_rounded, size: 16, color: TexoraColors.textMuted),
                      tooltip: 'View JSON Payload',
                      onPressed: () => _showPayloadModal(log),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: TexoraColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
