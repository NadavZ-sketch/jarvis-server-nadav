import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';
import '../task_edit_sheet.dart';
import 'ai_suggestions_panel.dart';
import 'task_category.dart';

/// Reusable interactive task card used by every tasks view.
///
/// Inline editing, swipe / long-press affordances and AI suggestions are all
/// driven through the shared [TasksController] so each surface stays in sync.
class SmartTaskCard extends StatefulWidget {
  final TasksController controller;
  final Map<String, dynamic> task;
  final bool dense;
  // When true the card responds to long-press as a drag handle. Views that
  // need drag-and-drop (kanban, eisenhower) wrap the card in a Draggable; this
  // flag disables the long-press edit shortcut so it doesn't conflict.
  final bool draggableMode;

  const SmartTaskCard({
    super.key,
    required this.controller,
    required this.task,
    this.dense = false,
    this.draggableMode = false,
  });

  @override
  State<SmartTaskCard> createState() => _SmartTaskCardState();
}

class _SmartTaskCardState extends State<SmartTaskCard> {
  bool _showSuggestions = false;
  bool _editing = false;
  late final TextEditingController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: _title);
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  String get _title {
    final raw = widget.task['content']?.toString() ?? '';
    final sepIdx = raw.indexOf('\n<<<AI_PROMPT>>>\n');
    return sepIdx == -1 ? raw : raw.substring(0, sepIdx);
  }

  bool get _isDone => widget.task['done'] == true;

  bool get _overdue {
    if (_isDone) return false;
    final iso = widget.task['due_date'];
    if (iso == null) return false;
    try {
      return DateTime.parse(iso.toString())
          .toLocal()
          .isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  String _formatDue(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day == today) return 'היום';
      if (day == today.add(const Duration(days: 1))) return 'מחר';
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Color get _priorityColor => switch (widget.task['priority']?.toString()) {
        'high' => JC.cancelRed,
        'low' => JC.green500,
        _ => JC.amber400,
      };

  void _openEdit() {
    showTaskEditSheet(
      context,
      settings: widget.controller.settings,
      task: widget.task,
      onChanged: widget.controller.notify,
    );
  }

  Future<void> _toggleSuggestions() async {
    final shouldOpen = !_showSuggestions;
    setState(() => _showSuggestions = shouldOpen);
    if (shouldOpen) {
      final id = widget.task['id'].toString();
      if (!widget.controller.suggestions.containsKey(id)) {
        await widget.controller.fetchSuggestions(widget.task);
      }
    }
  }

  void _commitEdit() {
    final newTitle = _editCtrl.text.trim();
    setState(() => _editing = false);
    if (newTitle.isEmpty || newTitle == _title) return;
    final raw = widget.task['content']?.toString() ?? '';
    final sepIdx = raw.indexOf('\n<<<AI_PROMPT>>>\n');
    final newContent = sepIdx == -1
        ? newTitle
        : '$newTitle${raw.substring(sepIdx)}';
    final prev = widget.task['content'];
    widget.task['content'] = newContent;
    widget.controller.notify();
    widget.controller.api
        .updateTask(widget.task['id'].toString(), content: newContent)
        .catchError((_) {
      widget.task['content'] = prev;
      widget.controller.notify();
      return <String, dynamic>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel = _formatDue(widget.task['due_date']);
    // Kanban / Eisenhower / story-points are project-methodology concepts.
    // On a standalone personal task they are pure noise, so only surface them
    // when the task actually belongs to a project.
    final inProject =
        (widget.task['project_id']?.toString().isNotEmpty ?? false);
    final quad = inProject ? widget.task['eisenhower_quad']?.toString() : null;
    final col = inProject ? widget.task['kanban_column']?.toString() : null;
    final pts = inProject ? widget.task['story_points'] : null;
    // Hide the 'general' category chip — it carries no signal and adds noise.
    final cat = categoryById(widget.task['category']?.toString());
    final showCat = cat != null && cat.id != 'general';

    return Container(
      margin: EdgeInsets.only(bottom: widget.dense ? 6 : 10),
      decoration: BoxDecoration(
        color: _isDone ? JC.surface.withValues(alpha: 0.6) : JC.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _overdue
              ? JC.cancelRed.withValues(alpha: 0.4)
              : JC.border,
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onLongPress: widget.draggableMode ? null : _openEdit,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.dense ? 10 : 14,
                  vertical: widget.dense ? 8 : 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.controller.toggleDone(widget.task);
                    },
                    child: Icon(
                      _isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: _isDone
                          ? JC.blue400.withValues(alpha: 0.6)
                          : JC.blue500,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _editing
                            ? TextField(
                                controller: _editCtrl,
                                autofocus: true,
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                    color: JC.textPrimary,
                                    fontSize: 15,
                                    fontFamily: 'Heebo'),
                                decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    border: InputBorder.none),
                                onSubmitted: (_) => _commitEdit(),
                                onTapOutside: (_) => _commitEdit(),
                              )
                            : GestureDetector(
                                onTap: _isDone
                                    ? null
                                    : () => setState(() => _editing = true),
                                child: Text(
                                  _title,
                                  style: TextStyle(
                                    color: _isDone
                                        ? JC.textMuted
                                        : JC.textPrimary,
                                    fontSize: 15,
                                    fontFamily: 'Heebo',
                                    decoration: _isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                        if (dueLabel.isNotEmpty ||
                            (quad?.isNotEmpty ?? false) ||
                            (col?.isNotEmpty ?? false) ||
                            pts != null ||
                            showCat)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                if (showCat)
                                  _chip('${cat.emoji} ${cat.label}',
                                      color: cat.color()),
                                if (dueLabel.isNotEmpty)
                                  _chip(dueLabel,
                                      color: _overdue
                                          ? JC.cancelRed
                                          : JC.textMuted,
                                      icon: Icons.event_outlined),
                                if (quad != null && quad.isNotEmpty)
                                  _chip(_quadLabel(quad), color: JC.indigo300),
                                if (col != null && col.isNotEmpty)
                                  _chip(_colLabel(col), color: JC.blue400),
                                if (pts is num)
                                  _chip('$pts SP',
                                      color: JC.amber400,
                                      icon: Icons.star_outline_rounded),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_isDone) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _toggleSuggestions,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: _showSuggestions
                              ? JC.indigo500.withValues(alpha: 0.25)
                              : JC.indigo500.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.auto_awesome_rounded,
                            size: 14, color: JC.indigo300),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _priorityColor),
                  ),
                ],
              ),
            ),
          ),
          if (_showSuggestions)
            AiSuggestionsPanel(
              controller: widget.controller,
              task: widget.task,
              onClose: () => setState(() => _showSuggestions = false),
            ),
        ],
      ),
    );
  }

  Widget _chip(String text, {required Color color, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(text,
              style: TextStyle(
                  color: color, fontFamily: 'Heebo', fontSize: 10.5)),
        ],
      ),
    );
  }

  static String _quadLabel(String q) => switch (q) {
        'q1' => 'דחוף וחשוב',
        'q2' => 'חשוב',
        'q3' => 'דחוף',
        'q4' => 'שולי',
        _ => q,
      };

  static String _colLabel(String c) => switch (c) {
        'todo' => 'לעשות',
        'doing' => 'בביצוע',
        'done' => 'הושלם',
        _ => c,
      };
}

