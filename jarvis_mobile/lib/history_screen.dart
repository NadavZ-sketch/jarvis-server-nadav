import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

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
      MaterialPageRoute(
        builder: (_) => _SessionDetailScreen(
          date: _formatDate(session['date'] as String?),
          messages: msgs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'היסטוריית שיחות',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
      body: _sessions.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, color: Color(0xFF3A3A3A), size: 56),
                  SizedBox(height: 16),
                  Text(
                    'אין היסטוריית שיחות עדיין',
                    style: TextStyle(color: Color(0xFF6E6E6E), fontSize: 15),
                  ),
                ],
              ),
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
                  key: Key(session['date'] as String? ?? '$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A0A0A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 26),
                  ),
                  onDismissed: (_) => _deleteSession(index),
                  child: InkWell(
                    onTap: () => _viewSession(session),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  preview,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  textDirection: TextDirection.rtl,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${msgs.length} הודעות',
                                  style: const TextStyle(
                                    color: Color(0xFF6E6E6E),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            date,
                            style: const TextStyle(color: Color(0xFF555555), fontSize: 12),
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

class _SessionDetailScreen extends StatelessWidget {
  final String date;
  final List<Map<String, dynamic>> messages;

  const _SessionDetailScreen({required this.date, required this.messages});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1C),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          date,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final msg = messages[index];
          final isUser = msg['sender'] == 'user';
          return Align(
            alignment: isUser ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2A2A2A) : const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 0 : 14),
                  bottomRight: Radius.circular(isUser ? 14 : 0),
                ),
                border: isUser
                    ? null
                    : Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    msg['text'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      height: 1.4,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  if (msg['time'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      msg['time'] as String,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF555555),
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
