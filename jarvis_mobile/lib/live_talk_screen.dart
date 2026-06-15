// Thin wrapper — preserves all existing navigation call sites unchanged.
// All logic has moved to ChatScreen + VoicePanel + TextPanel.
export 'screens/chat/chat_screen.dart' show ChatScreen;

import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'screens/chat/chat_screen.dart';

class LiveTalkScreen extends StatelessWidget {
  final String chatId;
  final AppSettings settings;
  final List<Map<String, dynamic>>? initialMessages;

  const LiveTalkScreen({
    super.key,
    required this.chatId,
    required this.settings,
    this.initialMessages,
  });

  @override
  Widget build(BuildContext context) => ChatScreen(
        chatId: chatId,
        settings: settings,
        initialMessages: initialMessages,
      );
}
