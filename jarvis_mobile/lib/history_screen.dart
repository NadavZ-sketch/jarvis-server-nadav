import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart' show JC;
import 'transitions/slide_fade_route.dart';
import 'widgets/empty_state.dart';

class HistoryScreen extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>>? onResume;

  const HistoryScreen({super.key, this.onResume});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_sessions') ?? '[]';
    final List decoded = jsonDecode(raw);
    setState(() {
      _sessions = decoded.cast<Map<String, dynamic>>().reversed.toList();
    });
  }

  Future<void> _deleteSession(int reversedIndex) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_sessions') ?? '[]';
    final List sessions = jsonDecode(raw);
    final origIndex = sessions.length - 1 - reversedIndex;
    if (origIndex >= 0) sessions.removeAt(origIndex);
    await prefs.setString('chat_sessions', jsonEncode(sessions));
    setState(() => _sessions.removeAt(reversedIndex));
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt).inDays;
      if (diff == 0) {
        return 'היום ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (diff == 1) return 'אתמול';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _getPreview(List msgs) {
    for (final m in msgs) {
      if (m['sender'] == 'user') {
        final text = m['text'] as String? ?? '';
        return text.length > 70 ? '${text.substring(0, 70)}...' : text;
      }
    }
    return msgs.isNotEmpty ? (msgs[0]['text'] as String? ?? '') : '';
  }

  void _viewSession(Map<String, dynamic> session) {
    final msgs = (session['messages'] as List).cast<Map<String, dynamic>>();
    Navigator.push(
      context,
      SlideFadeRoute(
        page: _SessionDetailScreen(
          date: _formatDate(session['date'] as String?),
          messages: msgs,
          onResume: widget.onResume != null
              ? () {
                  widget.onResume!(session);
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: JC.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: JC.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'היסטוריית שיחות',
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: _sessions.isEmpty
          ? const EmptyState(
              icon: Icons.history_rounded,
              title: 'אין היסטוריית שיחות עדיין',
              subtitle: 'השיחות שלך עם ג׳רביס יופיעו כאן',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final msgs = session['messages'] as List? ?? [];
                final preview = _getPreview(msgs);
                final date = _formatDate(session['date'] as String?);

                return Dismissible(
                  key: Key(session['chat_id'] as String? ?? session['date'] as String? ?? '$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 24),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: JC.cancelRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline,
                        color: JC.cancelRed, size: 26),
                  ),
                  onDismissed: (_) => _deleteSession(index),
                  child: InkWell(
                    onTap: () => _viewSession(session),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: JC.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JC.border, width: 0.5),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  preview,
                                  style: TextStyle(
                                    color: JC.textPrimary,
                                    fontSize: 14,
                                    fontFamily: 'Heebo',
                                  ),
                                  textDirection: TextDirection.rtl,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${msgs.length} הודעות',
                                  style: TextStyle(
                                    color: JC.textMuted,
                                    fontSize: 12,
                                    fontFamily: 'Heebo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                date,
                                style: TextStyle(
                                  color: JC.textMuted,
                                  fontSize: 12,
                                  fontFamily: 'Heebo',
                                ),
                              ),
                              if (widget.onResume != null) ...[
                                const SizedBox(height: 6),
                                Icon(Icons.reply_rounded,
                                    color: JC.blue400, size: 16),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _SessionDetailScreen extends StatefulWidget {
  final String date;
  final List<Map<String, dynamic>> messages;
  final VoidCallback? onResume;

  const _SessionDetailScreen({
    required this.date,
    required this.messages,
    this.onResume,
  });

  @override
  State<_SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<_SessionDetailScreen> {
  Future<void> _deleteSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('מחיקת שיחה',
            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
        content: Text('האם למחוק את השיחה הזאת? לא ניתן לשחזר.',
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('ביטול',
                style: TextStyle(color: JC.blue400, fontFamily: 'Heebo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחק',
                style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_sessions') ?? '[]';
      final List sessions = jsonDecode(raw);
      final dateStr = widget.date;
      sessions.removeWhere((s) => _formatDate(s['date']) == dateStr);
      await prefs.setString('chat_sessions', jsonEncode(sessions));
      if (mounted) Navigator.pop(context);
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt).inDays;
      if (diff == 0) {
        return 'היום ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (diff == 1) return 'אתמול';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: JC.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: JC.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.date,
          style: TextStyle(
            color: JC.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'Heebo',
          ),
        ),
        actions: [
          if (widget.onResume != null)
            TextButton.icon(
              onPressed: widget.onResume,
              icon: Icon(Icons.reply_rounded, size: 18, color: JC.blue400),
              label: Text('המשך',
                  style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 13)),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            onPressed: _deleteSession,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) {
          final msg = widget.messages[index];
          final isUser = msg['sender'] == 'user';
          return Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              decoration: BoxDecoration(
                color: isUser ? JC.userBubble : JC.jarvisBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 0),
                  bottomRight: Radius.circular(isUser ? 0 : 14),
                ),
                border: isUser
                    ? null
                    : Border.all(color: JC.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    msg['text'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 15,
                      color: JC.textPrimary,
                      height: 1.4,
                      fontFamily: 'Heebo',
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  if (msg['time'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      msg['time'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        color: JC.textMuted,
                        fontFamily: 'Heebo',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
