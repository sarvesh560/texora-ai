import 'package:flutter/material.dart';
import '../../data/models/copilot_models.dart';
import '../../data/services/copilot_service.dart';

class FloatingCopilotAssistant extends StatefulWidget {
  final VoidCallback onOpenFullScreen;
  final Function(int targetTabIndex, {String? targetMachine})? onNavigate;
  final double? panelWidth;
  final double? panelHeight;
  final bool initialExpanded;
  final bool initialLoading;
  final String? initialSessionId;
  final List<CopilotMessageModel>? initialMessages;
  final List<SuggestedQuestionModel>? initialSuggestions;

  const FloatingCopilotAssistant({
    super.key,
    required this.onOpenFullScreen,
    this.onNavigate,
    this.panelWidth,
    this.panelHeight,
    this.initialExpanded = false,
    this.initialLoading = false,
    this.initialSessionId,
    this.initialMessages,
    this.initialSuggestions,
  });

  @override
  State<FloatingCopilotAssistant> createState() => _FloatingCopilotAssistantState();
}

class _FloatingCopilotAssistantState extends State<FloatingCopilotAssistant> {
  final CopilotService _service = CopilotService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isExpanded = false;
  bool _isLoading = false;
  String? _sessionId;
  List<CopilotMessageModel> _messages = [];
  List<SuggestedQuestionModel> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
    _isLoading = widget.initialLoading;
    _sessionId = widget.initialSessionId;
    if (widget.initialMessages != null) {
      _messages = List.from(widget.initialMessages!);
    }
    if (widget.initialSuggestions != null) {
      _suggestions = List.from(widget.initialSuggestions!);
    }
    _loadInitialData();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final suggestions = await _service.getSuggestions();
      final sessions = await _service.getSessions();
      if (mounted) {
        setState(() {
          if (_suggestions.isEmpty) {
            _suggestions = suggestions;
          }
          if (sessions.isNotEmpty) {
            _sessionId = sessions.first.sessionId;
          }
        });
        if (_sessionId != null && _messages.isEmpty) {
          _loadMessages(_sessionId!);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadMessages(String sessionId) async {
    final msgs = await _service.getSessionMessages(sessionId);
    if (mounted) {
      setState(() {
        _messages = msgs;
      });
      _scrollToBottom();
    }
  }

  Future<void> _startNewSession() async {
    setState(() => _isLoading = true);
    final newSession = await _service.createSession(title: 'Quick Factory Consultation');
    if (newSession != null && mounted) {
      setState(() {
        _sessionId = newSession.sessionId;
        _messages = [];
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;

    _textController.clear();

    if (_sessionId == null) {
      final session = await _service.createSession();
      if (session != null) {
        _sessionId = session.sessionId;
      } else {
        _sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';
      }
    }

    // Add optimistic user message
    final optimisticMsg = CopilotMessageModel(
      role: 'user',
      content: text,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(optimisticMsg);
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final assistantMsg = await _service.sendMessage(_sessionId!, text);
      if (assistantMsg != null && mounted) {
        setState(() {
          _messages.add(assistantMsg);
          _isLoading = false;
        });
        _scrollToBottom();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
    if (ref.type == 'machine') {
      widget.onNavigate!(1, targetMachine: ref.id); // Digital Twin
    } else if (ref.type == 'incident') {
      widget.onNavigate!(2); // Incident Intelligence
    } else if (ref.type == 'ticket') {
      widget.onNavigate!(7); // Maintenance Execution
    } else if (ref.type == 'approval') {
      widget.onNavigate!(5); // Approval Center
    } else if (ref.type == 'order' || ref.type == 'department') {
      widget.onNavigate!(10); // Production Intelligence (Phase 15)
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isExpanded) {
      return _buildCollapsedFloatingButton();
    }

    return _buildExpandedFloatingDrawer();
  }

  Widget _buildCollapsedFloatingButton() {
    return Positioned(
      bottom: 24,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() => _isExpanded = true);
            if (_messages.isEmpty && _sessionId != null) {
              _loadMessages(_sessionId!);
            }
          },
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withAlpha(100),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              border: Border.all(
                color: const Color(0xFF38BDF8).withAlpha(150),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Factory Copilot',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildExpandedFloatingDrawer() {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    final targetWidth = widget.panelWidth ?? (screenWidth < 500 ? (screenWidth - 32).clamp(320.0, 440.0) : 440.0);
    final targetHeight = widget.panelHeight ?? (screenHeight < 700 ? (screenHeight - 48).clamp(400.0, 620.0) : 620.0);

    return Positioned(
      bottom: 24,
      right: 24,
      child: Container(
        width: targetWidth,
        height: targetHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F1D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF1E293B),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(180),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              _buildHeader(),
              _buildSessionToolbar(),
              Expanded(child: _buildMessagesList()),
              if (_suggestions.isNotEmpty && _messages.length < 3)
                _buildSuggestionsBar(),
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF2563EB)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Texora Factory Copilot',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  'Read-Only Industrial Advisory Engine',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onOpenFullScreen,
            icon: const Icon(Icons.open_in_full_rounded, color: Color(0xFF94A3B8), size: 16),
            tooltip: 'Open Fullscreen Workspace',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => setState(() => _isExpanded = false),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 18),
            tooltip: 'Minimize Copilot',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: const Color(0xFF131D31),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF38BDF8), size: 12),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _sessionId != null ? 'Session: ${_sessionId!.substring(0, 10)}...' : 'New Session',
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _startNewSession,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_rounded, color: Color(0xFF38BDF8), size: 12),
                  SizedBox(width: 4),
                  Text('New Chat', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty && !_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology_outlined, color: const Color(0xFF38BDF8).withAlpha(100), size: 48),
              const SizedBox(height: 12),
              const Text(
                'How can I assist your operations today?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Ask about machine telemetry, incident root causes, maintenance tickets, or spare parts.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isLoading) {
          return _buildLoadingBubble();
        }
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(CopilotMessageModel msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0369A1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            msg.content,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ),
      );
    }

    // Assistant message bubble
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 24),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Provenance badge
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: msg.provider == 'deterministic_fallback'
                          ? const Color(0xFFF59E0B).withAlpha(30)
                          : const Color(0xFF0284C7).withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: msg.provider == 'deterministic_fallback'
                            ? const Color(0xFFF59E0B).withAlpha(80)
                            : const Color(0xFF0284C7).withAlpha(80),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      msg.provider == 'deterministic_fallback'
                          ? 'Deterministic Fallback (${msg.latencyMs}ms)'
                          : '${msg.provider.toUpperCase()} / ${msg.model} (${msg.latencyMs}ms)',
                      style: TextStyle(
                        color: msg.provider == 'deterministic_fallback'
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFF38BDF8),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Content
            Text(
              msg.content,
              style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
            ),

            // References Chips
            if (msg.references.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: msg.references.map((ref) {
                  return InkWell(
                    onTap: () => _handleReferenceTap(ref),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF38BDF8).withAlpha(80)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ref.type == 'machine'
                                ? Icons.precision_manufacturing_rounded
                                : ref.type == 'incident'
                                    ? Icons.warning_amber_rounded
                                    : ref.type == 'order'
                                        ? Icons.assignment_outlined
                                        : ref.type == 'department'
                                            ? Icons.factory_rounded
                                            : Icons.bookmark_border_rounded,
                            color: const Color(0xFF38BDF8),
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              ref.label,
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Simulation disclosure
            const SizedBox(height: 6),
            Text(
              'SIMULATED DATA DEMONSTRATION',
              style: TextStyle(
                color: const Color(0xFFF59E0B).withAlpha(160),
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
    
  }

  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E293B)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF38BDF8)),
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Grounding query in factory records...',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsBar() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF0F172A),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _suggestions.length,
        separatorBuilder: (_, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final sug = _suggestions[index];
          return ActionChip(
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                sug.prompt,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            backgroundColor: const Color(0xFF1E293B),
            side: const BorderSide(color: Color(0xFF334155), width: 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onPressed: () => _sendMessage(sug.prompt),
          );
        },
      ),
    );
  }


  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Ask Copilot about loom telemetry, incidents, or parts...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _sendMessage(_textController.text),
            icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8), size: 18),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF0369A1).withAlpha(80),
              padding: const EdgeInsets.all(10),
            ),
          ),
        ],
      ),
    );
  }
}
