import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';
import '../task_edit_sheet.dart';

/// Phase 5 — Inline expand panel shown below a task card when tapped.
///
/// Editable properties: date, priority, recurrence, project, tags.
/// Smart subtask suggestions (AI, lazy) + existing subtasks list.
class TaskInlineExpand extends StatefulWidget {
  final TasksController controller;
  final Map<String, dynamic> task;

  const TaskInlineExpand({
    super.key,
    required this.controller,
    required this.task,
  });

  @override
  State<TaskInlineExpand> createState() => _TaskInlineExpandState();
}

class _TaskInlineExpandState extends State<TaskInlineExpand> {
  TasksController get _c => widget.controller;
  Map<String, dynamic> get _t => widget.task;

  bool _subtasksLoading = false;
  List<Map<String, dynamic>> _subtasks = [];
  bool _subtasksLoaded = false;
  final _addSubCtrl = TextEditingController();
  bool _addingSubtask = false;

  Timer? _enhanceDebounce;
  String? _enhancedText;
  bool _enhancing = false;

  @override
  void initState() {
    super.initState();
    _loadSubtasks();
    _loadAISuggestions();
  }

  @override
  void dispose() {
    _enhanceDebounce?.cancel();
    _addSubCtrl.dispose();
    super.dispose();
  }

  String get _taskTitle {
    final raw = _t['content']?.toString() ?? '';
    final withoutAI = raw.contains('\n<<<AI_PROMPT>>>\n')
        ? raw.split('\n<<<AI_PROMPT>>>\n').first
        : raw;
    return withoutAI.split('\n').first.trim();
  }

  void _onSubtaskChanged(String text) {
    _enhanceDebounce?.cancel();
    if (_enhancedText != null) setState(() => _enhancedText = null);
    if (text.trim().length < 4) return;
    _enhanceDebounce = Timer(const Duration(milliseconds: 700), () => _enhance(text));
  }

  Future<void> _enhance(String text) async {
    if (!mounted) return;
    setState(() => _enhancing = true);
    try {
      final enhanced = await _c.api.enhanceSubtask(_taskTitle, text);
      if (mounted && enhanced.trim() != text.trim()) {
        setState(() => _enhancedText = enhanced.trim());
      }
    } catch (_) {}
    if (mounted) setState(() => _enhancing = false);
  }

  Future<void> _loadSubtasks() async {
    if (_subtasksLoaded) return;
    final raw = _t['subtasks'];
    if (raw is List) {
      _subtasks = List<Map<String, dynamic>>.from(raw);
      _subtasksLoaded = true;
      return;
    }
    setState(() => _subtasksLoading = true);
    try {
      _subtasks = await _c.api.getSubtasks(_t['id'].toString());
      _t['subtasks'] = _subtasks;
      _subtasksLoaded = true;
    } catch (_) {}
    if (mounted) setState(() => _subtasksLoading = false);
  }

  void _loadAISuggestions() {
    final id = _t['id'].toString();
    if (!_c.suggestions.containsKey(id)) {
      _c.fetchSuggestions(_t);
    }
  }

  Future<void> _addSubtask([String? overrideText]) async {
    final text = (overrideText ?? _addSubCtrl.text).trim();
    if (text.isEmpty || _addingSubtask) return;
    setState(() { _addingSubtask = true; _enhancedText = null; _enhancing = false; });
    _enhanceDebounce?.cancel();
    try {
      final r = await _c.api.addSubtask(_t['id'].toString(), text);
      final sub = r['subtask'] as Map<String, dynamic>?;
      if (sub != null) {
        setState(() {
          _subtasks.add(sub);
          _t['subtasks'] = _subtasks;
        });
        _addSubCtrl.clear();
      }
    } catch (_) {
      _c.showSnack('נכשל בהוספת תת-משימה');
    }
    if (mounted) setState(() => _addingSubtask = false);
  }

  Future<void> _toggleSubtask(Map<String, dynamic> sub) async {
    final prevDone = sub['done'] == true;
    setState(() => sub['done'] = !prevDone);
    try {
      await _c.api.updateSubtask(
        _t['id'].toString(),
        sub['id'].toString(),
        done: !prevDone,
      );
    } catch (_) {
      setState(() => sub['done'] = prevDone);
    }
  }

  Future<void> _pickDate(BuildContext ctx) async {
    final now = DateTime.now();
    final current = _t['due_date'] != null
        ? DateTime.tryParse(_t['due_date'].toString())?.toLocal()
        : null;
    final picked = await showDatePicker(
      context: ctx,
      initialDate: current ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 730)),
      builder: (c, child) => Theme(
        data: Theme.of(c).copyWith(
            colorScheme: ColorScheme.dark(
                primary: JC.blue500, surface: JC.surface)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    await _c.setDueDate(_t, picked);
    setState(() {});
  }

  void _setPriority(String p) {
    final id = _t['id'].toString();
    final prev = _t['priority'];
    setState(() => _t['priority'] = p);
    _c.api.updateTask(id, priority: p).catchError((_) {
      setState(() => _t['priority'] = prev);
      return <String, dynamic>{};
    });
    _c.notify();
  }

  void _openFullEdit(BuildContext ctx) {
    showTaskEditSheet(
      ctx,
      settings: _c.settings,
      task: _t,
      onChanged: _c.notify,
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = _t['id'].toString();
    final suggestions = _c.suggestions[id] ?? [];
    final suggestionsLoading = _c.suggestionLoading.contains(id);
    final priority = _t['priority']?.toString() ?? 'medium';
    final dueIso = _t['due_date'] as String?;
    DateTime? due;
    if (dueIso != null) {
      try { due = DateTime.parse(dueIso).toLocal(); } catch (_) {}
    }

    // Extract description (everything after first line, before AI separator)
    final rawContent = _t['content']?.toString() ?? '';
    final withoutAI = rawContent.contains('\n<<<AI_PROMPT>>>\n')
        ? rawContent.split('\n<<<AI_PROMPT>>>\n').first
        : rawContent;
    final contentLines = withoutAI.split('\n');
    final description = contentLines.length > 1
        ? contentLines.skip(1).join('\n').trim()
        : '';

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        border: Border(
          top: BorderSide(color: JC.border, width: 0.6),
          bottom: BorderSide(color: JC.border, width: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Full description ───────────────────────────────────────────────
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: JC.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: JC.border, width: 0.6),
                ),
                child: Text(
                  description,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: JC.textSecondary,
                    fontSize: 12.5,
                    fontFamily: 'Heebo',
                    height: 1.55,
                  ),
                ),
              ),
            ),

          // ── Properties ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date row
                _propRow(
                  icon: Icons.calendar_today_outlined,
                  label: due == null
                      ? 'הוסף תאריך'
                      : '${due.day}/${due.month}/${due.year}',
                  color: due == null
                      ? JC.textMuted
                      : (due.isBefore(DateTime.now()) ? JC.cancelRed : JC.green500),
                  onTap: () => _pickDate(context),
                  trailing: due != null
                      ? GestureDetector(
                          onTap: () async {
                            final prev = _t['due_date'];
                            setState(() => _t['due_date'] = null);
                            try {
                              await _c.api.updateTask(_t['id'].toString(), clearDueDate: true);
                            } catch (_) {
                              setState(() => _t['due_date'] = prev);
                            }
                            _c.notify();
                          },
                          child: Icon(Icons.close_rounded, size: 14, color: JC.textMuted),
                        )
                      : null,
                ),
                const SizedBox(height: 6),

                // Priority chips
                Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 14, color: JC.textMuted),
                    const SizedBox(width: 6),
                    for (final entry in [
                      ('high', '🔴 גבוה', JC.cancelRed),
                      ('medium', '🟡 בינוני', JC.amber400),
                      ('low', '🟢 נמוך', JC.green500),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 5),
                        child: GestureDetector(
                          onTap: () => _setPriority(entry.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: priority == entry.$1
                                  ? entry.$3.withValues(alpha: 0.2)
                                  : JC.surfaceAlt,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: priority == entry.$1
                                    ? entry.$3
                                    : JC.border,
                                width: priority == entry.$1 ? 1.2 : 0.6,
                              ),
                            ),
                            child: Text(entry.$2,
                                style: TextStyle(
                                  color: priority == entry.$1
                                      ? entry.$3
                                      : JC.textMuted,
                                  fontSize: 11,
                                  fontFamily: 'Heebo',
                                  fontWeight: priority == entry.$1
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                )),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // ── AI subtask suggestions ────────────────────────────────────────
          if (suggestionsLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: JC.indigo300),
                ),
                const SizedBox(width: 8),
                Text('מייצר תת-משימות...',
                    style: TextStyle(
                        color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
              ]),
            )
          else if (suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('הצעות AI',
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 10,
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < suggestions.length && i < 5; i++)
                        GestureDetector(
                          onTap: () async {
                            final s = suggestions[i];
                            await _c.acceptSuggestionAsSubtask(
                                _t, s['text'] as String? ?? '');
                            await _loadSubtasks();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: JC.indigo500.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: JC.indigo300.withValues(alpha: 0.35),
                                  width: 0.8),
                            ),
                            child: Text(
                              '＋ ${suggestions[i]['text'] ?? ''}',
                              style: TextStyle(
                                  color: JC.indigo300,
                                  fontSize: 11.5,
                                  fontFamily: 'Heebo',
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

          // ── Existing subtasks ─────────────────────────────────────────────
          if (_subtasksLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 1.5))),
            )
          else
            for (final sub in _subtasks)
              _SubtaskRow(
                subtask: sub,
                onToggle: () => _toggleSubtask(sub),
              ),

          // ── Add subtask field ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 14, 4),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 16, color: JC.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _addSubCtrl,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 13,
                        fontFamily: 'Heebo'),
                    decoration: InputDecoration(
                      hintText: 'הוסף תת-משימה...',
                      hintStyle: TextStyle(
                          color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: _onSubtaskChanged,
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                if (_addingSubtask)
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: JC.blue400))
                else if (_enhancing)
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: JC.indigo300))
                else
                  GestureDetector(
                    onTap: _addSubtask,
                    child: Icon(Icons.keyboard_return_rounded,
                        size: 16, color: JC.blue400),
                  ),
              ],
            ),
          ),

          // ── AI-enhanced suggestion chip ────────────────────────────────────
          if (_enhancedText != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
              child: GestureDetector(
                onTap: () => _addSubtask(_enhancedText),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: JC.indigo500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: JC.indigo300.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Text('✨', style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _enhancedText!,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                              color: JC.indigo300,
                              fontSize: 12,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('הוסף',
                          style: TextStyle(
                              color: JC.indigo300,
                              fontSize: 10.5,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Action row ────────────────────────────────────────────────────
          Container(
            decoration:
                BoxDecoration(border: Border(top: BorderSide(color: JC.border, width: 0.5))),
            padding:
                const EdgeInsetsDirectional.fromSTEB(14, 6, 14, 10),
            child: Row(
              children: [
                _actionBtn(
                    icon: Icons.edit_note_rounded,
                    label: 'עוד פרטים',
                    color: JC.blue400,
                    onTap: () => _openFullEdit(context)),
                const Spacer(),
                _actionBtn(
                    icon: Icons.delete_outline_rounded,
                    label: 'מחק',
                    color: JC.cancelRed,
                    onTap: () {
                      Navigator.of(context, rootNavigator: false);
                      _c.deleteTask(_t);
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _propRow({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w500)),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Subtask row ──────────────────────────────────────────────────────────────

class _SubtaskRow extends StatelessWidget {
  final Map<String, dynamic> subtask;
  final VoidCallback onToggle;

  const _SubtaskRow({required this.subtask, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final done = subtask['done'] == true;
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding:
            const EdgeInsetsDirectional.fromSTEB(14, 3, 14, 3),
        child: Row(
          children: [
            Icon(
              done
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 16,
              color: done ? JC.blue400.withValues(alpha: 0.6) : JC.border,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtask['content']?.toString() ?? '',
                style: TextStyle(
                  color: done ? JC.textMuted : JC.textSecondary,
                  fontSize: 12.5,
                  fontFamily: 'Heebo',
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
