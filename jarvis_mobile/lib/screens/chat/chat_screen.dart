import 'package:flutter/material.dart';

import '../../app_settings.dart';
import '../../main.dart' show JC;

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
  final String chatId;
  final AppSettings settings;
  final List<Map<String, dynamic>>? initialMessages;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.settings,
    this.initialMessages,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final List<ChatMessage> _messages = [];
  ChatMode _mode = ChatMode.voice;

  static const _voiceKey = ValueKey('voice');
  static const _textKey  = ValueKey('text');

  @override
  void initState() {
    super.initState();
    if (widget.initialMessages != null) {
      _messages.addAll(widget.initialMessages!.map(ChatMessage.fromLegacy));
    }
  }

  void _addMessage(ChatMessage msg) {
    if (!mounted) return;
    setState(() => _messages.add(msg));
  }

  void _switchMode(ChatMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: JC.textSecondary),
          onPressed: () => Navigator.of(context)
              .pop(_messages.map((m) => {'sender': m.sender, 'text': m.text}).toList()),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: SegmentedButton<ChatMode>(
              segments: const [
                ButtonSegment(value: ChatMode.voice, label: Text('🎤 קול')),
                ButtonSegment(value: ChatMode.text,  label: Text('💬 טקסט')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _switchMode(s.first),
              style: ButtonStyle(
                textStyle: WidgetStateProperty.all(const TextStyle(
                  fontFamily: 'Heebo', fontSize: 12,
                )),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == (_mode == ChatMode.voice ? _voiceKey : _textKey);
          final offset = isIncoming
              ? Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(animation)
              : Tween(begin: Offset.zero, end: const Offset(0, 0.08)).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: _mode == ChatMode.voice
            ? _buildVoicePanel()
            : _buildTextPanel(),
      ),
    );
  }

  Widget _buildVoicePanel() {
    // VoicePanel is wired in Task 4.
    return const SizedBox.expand(key: _voiceKey);
  }

  Widget _buildTextPanel() {
    // TextPanel is wired in Task 5.
    return const SizedBox.expand(key: _textKey);
  }
}
