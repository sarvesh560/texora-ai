import 'package:flutter/material.dart';
import '../../core/theme/texora_design_system.dart';
import '../../data/models/copilot_models.dart';
import '../../data/services/copilot_service.dart';

class FactoryCopilotScreen extends StatefulWidget {
  final VoidCallback onExit;
  final Function(int targetTabIndex, {String? targetMachine})? onNavigate;

  const FactoryCopilotScreen({
    super.key,
    required this.onExit,
    this.onNavigate,
  });

  @override
  State<FactoryCopilotScreen> createState() => _FactoryCopilotScreenState();
}

class _FactoryCopilotScreenState extends State<FactoryCopilotScreen> {
  final CopilotService _service = CopilotService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CopilotSessionModel> _sessions = [];
  String? _selectedSessionId;
  CopilotSessionModel? _activeSession;
  List<CopilotMessageModel> _messages = [];
  List<SuggestedQuestionModel> _suggestions = [];
  bool _isLoading = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      final suggestions = await _service.getSuggestions();
      final sessions = await _service.getSessions();

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _sessions = sessions;
          if (sessions.isNotEmpty) {
            _selectedSessionId = sessions.first.sessionId;
            _activeSession = sessions.first;
          }
          _isLoading = false;
        });

        if (_selectedSessionId != null) {
          _fetchMessages(_selectedSessionId!);
        } else {
          // If no session exists, create a default one
          _createNewSession();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMessages(String sessionId) async {
    final msgs = await _service.getSessionMessages(sessionId);
    if (mounted) {
      setState(() {
        _messages = msgs;
      });
      _scrollToBottom();
    }
  }

  Future<void> _createNewSession() async {
    final s = await _service.createSession(title: 'Executive Shift Consultation');
    if (s != null && mounted) {
      setState(() {
        _sessions.insert(0, s);
        _selectedSessionId = s.sessionId;
        _activeSession = s;
        _messages = [];
      });
    }
  }

  Future<void> _handleSendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    _textController.clear();

    if (_selectedSessionId == null) {
      await _createNewSession();
      if (_selectedSessionId == null) return;
    }

    final userMsg = CopilotMessageModel(
      role: 'user',
      content: query,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final response = await _service.sendMessage(_selectedSessionId!, query);
      if (response != null && mounted) {
        setState(() {
          _messages.add(response);
          _isSending = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _isSending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleReferenceTap(CopilotReference ref) {
    if (widget.onNavigate == null) return;
    widget.onExit(); // Close full-screen first
    if (ref.type == 'machine') {
      widget.onNavigate!(2, targetMachine: ref.id);
    } else if (ref.type == 'incident') {
      widget.onNavigate!(3);
    } else if (ref.type == 'ticket') {
      widget.onNavigate!(5);
    } else if (ref.type == 'approval') {
      widget.onNavigate!(0); // approvals accessible contextually
    } else if (ref.type == 'order' || ref.type == 'department') {
      widget.onNavigate!(4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showInspector = width >= 1150;

    return Scaffold(
      backgroundColor: TexoraColors.workspaceBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(),
            Expanded(
              child: Row(
                children: [
                  // Left: Sessions & Active Focus
                  Container(
                    width: 280,
                    decoration: const BoxDecoration(
                      color: TexoraColors.cardBg,
                      border: Border(right: BorderSide(color: TexoraColors.cardBorder)),
                    ),
                    child: _buildLeftPane(),
                  ),

                  // Center: Main Chat Stream
                  Expanded(
                    child: Container(
                      color: TexoraColors.workspaceBg,
                      child: Column(
                        children: [
                          Expanded(child: _buildChatStream()),
                          if (_suggestions.isNotEmpty) _buildSuggestionsCarousel(),
                          _buildChatInputBar(),
                        ],
                      ),
                    ),
                  ),

                  // Right: Grounded Evidence Drawer (on wide viewports)
                  if (showInspector)
                    Container(
                      width: 320,
                      decoration: const BoxDecoration(
                        color: TexoraColors.cardBg,
                        border: Border(left: BorderSide(color: TexoraColors.cardBorder)),
                      ),
                      child: _buildEvidenceInspector(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(bottom: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onExit,
            icon: const Icon(Icons.arrow_back_rounded, color: TexoraColors.primary, size: 20),
            tooltip: 'Return to Operations Dashboard',
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), TexoraColors.primary],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Factory AI Copilot Workspace',
                  style: TextStyle(
                    color: TexoraColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Grounded Multi-Cloud Industrial Reasoning • Read-Only Advisory',
                  style: TextStyle(
                    color: TexoraColors.textSecondary,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Advisory disclosure pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: TexoraColors.badgeWarningBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: TexoraColors.badgeWarningText, size: 12),
                SizedBox(width: 5),
                Text(
                  'READ-ONLY INDUSTRIAL ADVISORY',
                  style: TextStyle(color: TexoraColors.badgeWarningText, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Provider provenance chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: TexoraColors.badgeInfoBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: const Row(
              children: [
                Icon(Icons.hub_rounded, color: TexoraColors.primary, size: 12),
                SizedBox(width: 6),
                Text(
                  'GroqCloud / Gemini / Fallback Active',
                  style: TextStyle(color: TexoraColors.primary, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPane() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // New Consultation Action
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            onPressed: _createNewSession,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New Consultation', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: TexoraColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(38),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        // Active Focus Card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: TexoraColors.tableHeaderBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: TexoraColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.my_location_rounded, color: TexoraColors.primary, size: 12),
                  SizedBox(width: 6),
                  Text(
                    'ACTIVE CONTEXT FOCUS',
                    style: TextStyle(color: TexoraColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Machine: ${_activeSession?.activeMachineCode ?? 'General Plant'}',
                style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(
                'Incident: ${_activeSession?.activeIncidentCode ?? 'None in focus'}',
                style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ),

        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'SAVED SESSIONS',
            style: TextStyle(color: TexoraColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),

        // Session list
        Expanded(
          child: ListView.builder(
            itemCount: _sessions.length,
            itemBuilder: (context, index) {
              final s = _sessions[index];
              final isSelected = s.sessionId == _selectedSessionId;
              return ListTile(
                selected: isSelected,
                selectedTileColor: TexoraColors.badgeInfoBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: isSelected ? TexoraColors.primary : TexoraColors.textMuted,
                  size: 16,
                ),
                title: Text(
                  s.title,
                  style: TextStyle(
                    color: isSelected ? TexoraColors.primary : TexoraColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${s.messageCount} turns • ${s.updatedAt.hour}:${s.updatedAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: TexoraColors.textMuted, fontSize: 9.5),
                ),
                onTap: () {
                  setState(() {
                    _selectedSessionId = s.sessionId;
                    _activeSession = s;
                  });
                  _fetchMessages(s.sessionId);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatStream() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: TexoraColors.primary,
        ),
      );
    }

    if (_messages.isEmpty && !_isSending) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TexoraColors.cardBg,
                shape: BoxShape.circle,
                border: Border.all(color: TexoraColors.cardBorder),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: TexoraColors.primary, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'Texora AI Factory Copilot Ready',
              style: TextStyle(color: TexoraColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Select a prompt below or ask about any weaving loom, incident, or maintenance order.',
              style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length + (_isSending ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isSending) {
          return _buildTypingIndicator();
        }
        return _buildWorkspaceBubble(_messages[index]);
      },
    );
  }

  Widget _buildWorkspaceBubble(CopilotMessageModel msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14, left: 100),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: TexoraColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            msg.content,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
        ),
      );
    }

    // Assistant response
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18, right: 60),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TexoraColors.cardBorder),
          boxShadow: const [
            BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metadata header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: msg.provider == 'deterministic_fallback'
                        ? TexoraColors.badgeWarningBg
                        : TexoraColors.badgeInfoBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: msg.provider == 'deterministic_fallback'
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFBAE6FD),
                    ),
                  ),
                  child: Text(
                    msg.provider == 'deterministic_fallback'
                        ? 'DETERMINISTIC FALLBACK (${msg.latencyMs}ms)'
                        : '${msg.provider.toUpperCase()} / ${msg.model} (${msg.latencyMs}ms)',
                    style: TextStyle(
                      color: msg.provider == 'deterministic_fallback'
                          ? TexoraColors.badgeWarningText
                          : TexoraColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: TexoraColors.textMuted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Content body
            Text(
              msg.content,
              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13, height: 1.5),
            ),

            // Facts Section
            if (msg.facts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TexoraColors.badgeSuccessBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: TexoraColors.badgeSuccessText, size: 12),
                        SizedBox(width: 6),
                        Text('VERIFIED FACTUAL EVIDENCE', style: TextStyle(color: TexoraColors.badgeSuccessText, fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...msg.facts.map((f) => Padding(
                          padding: const EdgeInsets.only(bottom: 3.0),
                          child: Text('• $f', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11)),
                        )),
                  ],
                ),
              ),
            ],

            // Recommendations Section
            if (msg.recommendations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD8B4FE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, color: Color(0xFF7E22CE), size: 12),
                        SizedBox(width: 6),
                        Text('ACTIONABLE RECOMMENDATIONS', style: TextStyle(color: Color(0xFF7E22CE), fontSize: 10, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...msg.recommendations.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 3.0),
                          child: Text('• $r', style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 11)),
                        )),
                  ],
                ),
              ),
            ],

            // Reference Chips
            if (msg.references.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: msg.references.map((r) {
                  return ActionChip(
                    avatar: Icon(
                      r.type == 'machine'
                          ? Icons.precision_manufacturing_rounded
                          : r.type == 'incident'
                              ? Icons.warning_amber_rounded
                              : r.type == 'order'
                                  ? Icons.assignment_outlined
                                  : r.type == 'department'
                                      ? Icons.factory_rounded
                                      : Icons.bookmark_border_rounded,
                      color: TexoraColors.primary,
                      size: 14,
                    ),
                    label: Text(r.label, style: const TextStyle(color: TexoraColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                    backgroundColor: TexoraColors.tableHeaderBg,
                    side: const BorderSide(color: TexoraColors.cardBorder, width: 0.8),
                    onPressed: () => _handleReferenceTap(r),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: TexoraColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TexoraColors.cardBorder),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: TexoraColors.primary),
            ),
            SizedBox(width: 10),
            Text('Synthesizing verified factory database records...', style: TextStyle(color: TexoraColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsCarousel() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(top: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _suggestions.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final sug = _suggestions[index];
          return ActionChip(
            label: Text(sug.prompt, style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11)),
            backgroundColor: TexoraColors.tableHeaderBg,
            side: const BorderSide(color: TexoraColors.cardBorder),
            onPressed: () => _handleSendMessage(sug.prompt),
          );
        },
      ),
    );
  }

  Widget _buildChatInputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: TexoraColors.cardBg,
        border: Border(top: BorderSide(color: TexoraColors.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter question for Factory Copilot (e.g., "What happened to WEV-AJ-02?", "What should we do next?")...',
                hintStyle: const TextStyle(color: TexoraColors.textMuted, fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                filled: true,
                fillColor: TexoraColors.workspaceBg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TexoraColors.cardBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: TexoraColors.primary)),
              ),
              onSubmitted: _handleSendMessage,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => _handleSendMessage(_textController.text),
            icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: TexoraColors.primary,
              padding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvidenceInspector() {
    final latestAssistant = _messages.reversed.firstWhere(
      (m) => m.isAssistant,
      orElse: () => CopilotMessageModel(
        role: 'assistant',
        content: 'No response yet',
        createdAt: DateTime.now(),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: TexoraColors.primary, size: 14),
              SizedBox(width: 8),
              Text(
                'GROUNDED EVIDENCE LOG',
                style: TextStyle(color: TexoraColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Safe Industrial Mode Banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: TexoraColors.badgeSuccessBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined, color: TexoraColors.badgeSuccessText, size: 12),
                    SizedBox(width: 6),
                    Text('READ-ONLY ENFORCEMENT', style: TextStyle(color: TexoraColors.badgeSuccessText, fontSize: 10, fontWeight: FontWeight.w700)),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Copilot cannot approve gates, close tickets, deduct parts, or control machinery.',
                  style: TextStyle(color: TexoraColors.textSecondary, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'Evidence Records (${latestAssistant.evidenceRecords.length})',
            style: const TextStyle(color: TexoraColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: latestAssistant.evidenceRecords.isEmpty
                ? const Center(
                    child: Text('No evidence records retrieved for current turn.', style: TextStyle(color: TexoraColors.textMuted, fontSize: 11)),
                  )
                : ListView.builder(
                    itemCount: latestAssistant.evidenceRecords.length,
                    itemBuilder: (context, index) {
                      final item = latestAssistant.evidenceRecords[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: TexoraColors.tableHeaderBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: TexoraColors.cardBorder),
                        ),
                        child: Text(
                          item.toString(),
                          style: const TextStyle(color: TexoraColors.textPrimary, fontSize: 10.5, fontFamily: 'monospace'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
