import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../widgets/chat/voice_panel.dart';
import '../../widgets/chat/text_panel.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String sender; // 'user' | 'jarvis'
  final String text;
  final bool fromVoice;
  final String? fileName;
  final DateTime at;

  ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.fromVoice = false,
    this.fileName,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  static ChatMessage fromLegacy(Map<String, dynamic> m) => ChatMessage(
        id: UniqueKey().toString(),
        sender: (m['sender'] as String? ?? 'jarvis'),
        text: (m['text'] as String? ?? ''),
        fromVoice: m['fromVoice'] as bool? ?? false,
      );
}

// ─── Mode enum ────────────────────────────────────────────────────────────────

enum ChatMode { voice, text }

// ─── Shell ────────────────────────────────────────────────────────────────────

class ChatScreen extends StatefulWidget {
  // chatId is optional — if null, generated internally via SharedPreferences.
  final String? chatId;
  final List<Map<String, dynamic>>? initialMessages;
  final AppSettings? initialSettings;
  final ValueChanged<AppSettings>? onSettingsChanged;
  final VoidCallback? onOpenDrawer;
  final String? pendingCommand;
  final VoidCallback? onCommandConsumed;
  final void Function(Future<void> Function())? onRegisterArchive;
  final void Function(String target)? onNavigate;

  const ChatScreen({
    super.key,
    this.chatId,
    this.initialMessages,
    this.initialSettings,
    this.onSettingsChanged,
    this.onOpenDrawer,
    this.pendingCommand,
    this.onCommandConsumed,
    this.onRegisterArchive,
    this.onNavigate,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  ChatMode _mode = ChatMode.text;
  final GlobalKey<VoicePanelState> _voicePanelKey = GlobalKey();
  late final AnimationController _modeCtrl;

  // Session management
  String _chatId = '';
  AppSettings _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _modeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _settings = widget.initialSettings ?? AppSettings();
    if (widget.initialMessages != null) {
      _messages.addAll(widget.initialMessages!.map(ChatMessage.fromLegacy));
    }
    _loadChatHistory();
    if (widget.onRegisterArchive != null) {
      widget.onRegisterArchive!(_archiveSessionToHistory);
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSettings != null &&
        widget.initialSettings != oldWidget.initialSettings) {
      setState(() => _settings = widget.initialSettings!);
    }
    if (widget.pendingCommand != null &&
        widget.pendingCommand != oldWidget.pendingCommand) {
      if (_mode != ChatMode.text) _switchMode(ChatMode.text);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onCommandConsumed?.call();
      });
    }
  }

  @override
  void dispose() {
    _modeCtrl.dispose();
    super.dispose();
  }

  void _addMessage(ChatMessage msg) {
    if (!mounted) return;
    setState(() => _messages.add(msg));
    _persistMessages();
  }

  Future<void> _loadChatHistory() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load or generate chatId
    final externalId = widget.chatId;
    if (externalId != null && externalId.isNotEmpty) {
      _chatId = externalId;
    } else {
      final saved = prefs.getString('current_chat_id');
      if (saved != null && saved.isNotEmpty) {
        _chatId = saved;
      } else {
        _chatId = 'chat-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(100000)}';
        await prefs.setString('current_chat_id', _chatId);
      }
    }

    // 2. Load cached messages immediately (instant first paint)
    final cached = prefs.getString('current_messages');
    if (cached != null && cached.isNotEmpty && mounted) {
      try {
        final List decoded = jsonDecode(cached);
        final loaded = decoded
            .cast<Map<String, dynamic>>()
            .map(ChatMessage.fromLegacy)
            .toList();
        if (loaded.isNotEmpty) {
          setState(() { _messages.clear(); _messages.addAll(loaded); });
        }
      } catch (_) {}
    }

    // 3. Fetch fresh from server in background
    if (_settings.serverUrl.isEmpty) return;
    try {
      final url = Uri.parse('${_settings.serverUrl}/chat-history?limit=60&chatId=$_chatId');
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final List raw = (data['messages'] ?? data['history'] ?? []) as List;
        if (raw.isNotEmpty) {
          final serverMsgs = raw.map<ChatMessage>((m) {
            final role = (m['role'] as String? ?? m['sender'] as String? ?? 'jarvis');
            return ChatMessage(
              id: UniqueKey().toString(),
              sender: role == 'user' ? 'user' : 'jarvis',
              text: (m['text'] as String? ?? m['content'] as String? ?? '').trim(),
            );
          }).where((m) => m.text.isNotEmpty).toList();
          if (mounted) {
            setState(() { _messages.clear(); _messages.addAll(serverMsgs); });
            await _persistMessages();
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _persistMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = _messages.map((m) => {
        'sender': m.sender,
        'text': m.text,
        'fromVoice': m.fromVoice,
      }).toList();
      await prefs.setString('current_messages', jsonEncode(serialized));
    } catch (_) {}
  }

  Future<void> _archiveSessionToHistory() async {
    if (_messages.length <= 1) return;
    if (_chatId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_sessions') ?? '[]';
      final List sessions = jsonDecode(raw) as List;
      final serialized = _messages.map((m) => {'sender': m.sender, 'text': m.text}).toList();
      sessions.removeWhere((s) => (s as Map)['chat_id'] == _chatId);
      sessions.add({
        'date': DateTime.now().toIso8601String(),
        'messages': serialized,
        'chat_id': _chatId,
      });
      final trimmed = sessions.length > 50
          ? sessions.sublist(sessions.length - 50)
          : sessions;
      await prefs.setString('chat_sessions', jsonEncode(trimmed));
    } catch (_) {}
  }

  Future<void> _startNewChat() async {
    await _archiveSessionToHistory();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    _chatId = 'chat-${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(100000)}';
    await prefs.setString('current_chat_id', _chatId);
    await prefs.remove('current_messages');
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.add(ChatMessage(
          id: 'greeting-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'jarvis',
          text: 'שיחה חדשה! מוכן לעזור.',
        ));
      });
    }
    await _persistMessages();
  }

  void _switchMode(ChatMode mode) {
    if (mode == _mode) return;
    HapticFeedback.mediumImpact();
    if (_mode == ChatMode.voice) {
      _voicePanelKey.currentState?.stopVoice();
    }
    setState(() => _mode = mode);
    if (mode == ChatMode.voice) {
      _modeCtrl.reverse();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _voicePanelKey.currentState?.resumeVoice();
      });
    } else {
      _modeCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'ג׳רביס',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
          ),
        ),
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: Icon(Icons.menu_rounded, color: JC.textSecondary),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        automaticallyImplyLeading: widget.onOpenDrawer == null,
      ),
      body: _mode == ChatMode.voice
          ? _buildVoicePanel()
          : _buildTextPanel(),
    );
  }

  Widget _buildVoicePanel() {
    return VoicePanel(
      key: _voicePanelKey,
      chatId: _chatId,
      settings: _settings,
      messages: _messages,
      onNewMessage: _addMessage,
      onOrbTap: () => _switchMode(ChatMode.text),
    );
  }

  Widget _buildTextPanel() {
    return TextPanel(
      key: const ValueKey('text'),
      messages: _messages,
      settings: _settings,
      chatId: _chatId,
      onNewMessage: _addMessage,
      onSwitchToVoice: () => _switchMode(ChatMode.voice),
      onNavigate: widget.onNavigate,
      pendingCommand: widget.pendingCommand,
    );
  }
}
