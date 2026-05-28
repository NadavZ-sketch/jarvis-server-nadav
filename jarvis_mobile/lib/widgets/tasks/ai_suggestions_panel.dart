import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';

class AiSuggestionsPanel extends StatelessWidget {
  final TasksController controller;
  final Map<String, dynamic> task;
  final VoidCallback onClose;

  const AiSuggestionsPanel({
    super.key,
    required this.controller,
    required this.task,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final id = task['id'].toString();
    final loading = controller.suggestionLoading.contains(id);
    final list = controller.suggestions[id];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.indigo500.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: JC.indigo500.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 14, color: JC.indigo300),
              const SizedBox(width: 6),
              Text('הצעות AI',
                  style: TextStyle(
                      color: JC.indigo300,
                      fontFamily: 'Heebo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: Icon(Icons.close_rounded,
                    size: 16, color: JC.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: JC.indigo300),
                  ),
                  const SizedBox(width: 8),
                  Text('יוצר הצעות...',
                      style: TextStyle(
                          color: JC.textMuted,
                          fontFamily: 'Heebo',
                          fontSize: 12)),
                ],
              ),
            )
          else if (list == null || list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('אין הצעות זמינות',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      color: JC.textMuted,
                      fontFamily: 'Heebo',
                      fontSize: 12)),
            )
          else
            for (var i = 0; i < list.length; i++)
              _SuggestionRow(
                text: (list[i]['content'] ??
                        list[i]['text'] ??
                        list[i]['title'] ??
                        '')
                    .toString(),
                onAccept: () =>
                    controller.acceptSuggestionAsSubtask(task, _textOf(list[i])),
                onDismiss: () => controller.dismissSuggestion(task, i),
              ),
        ],
      ),
    );
  }

  static String _textOf(Map<String, dynamic> s) =>
      (s['content'] ?? s['text'] ?? s['title'] ?? '').toString();
}

class _SuggestionRow extends StatelessWidget {
  final String text;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const _SuggestionRow({
    required this.text,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontFamily: 'Heebo',
                    fontSize: 13)),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onAccept,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: JC.blue500.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 12, color: JC.blue400),
                  const SizedBox(width: 3),
                  Text('כתת-משימה',
                      style: TextStyle(
                          color: JC.blue400,
                          fontFamily: 'Heebo',
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded, size: 14, color: JC.textMuted),
          ),
        ],
      ),
    );
  }
}
