import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';

/// Reusable task editor used by the tasks screen and project detail. Edits
/// content, priority, due date and project link, manages subtasks, and offers
/// AI smart suggestions (each can be added as a subtask or a standalone task).
/// Mutates [task] in place and invokes [onChanged] after any change.
Future<void> showTaskEditSheet(
  BuildContext context, {
  required AppSettings settings,
  required Map<String, dynamic> task,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: JC.surfaceAlt,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => TaskEditSheet(
        settings: settings, task: task, onChanged: onChanged),
  );
}

class TaskEditSheet extends StatefulWidget {
  final AppSettings settings;
  final Map<String, dynamic> task;
  final VoidCallback? onChanged;

  const TaskEditSheet({
    super.key,
    required this.settings,
    required this.task,
    this.onChanged,
  });

  @override
  State<TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends State<TaskEditSheet> {
  late final ApiService _api = ApiService(widget.settings);
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.task['content']?.toString() ?? '');
  final TextEditingController _addCtrl = TextEditingController();
  late String _priority = widget.task['priority']?.toString() ?? 'medium';
  DateTime? _dueDate;
  String? _projectId;

  List<Map<String, dynamic>> _projects = [];
  bool _saving = false;

  String get _taskId => widget.task['id'].toString();

  List<Map<String, dynamic>> get _subtasks {
    final raw = widget.task['subtasks'];
    return raw is List ? List<Map<String, dynamic>>.from(raw) : [];
  }

  @override
  void initState() {
    super.initState();
    final due = widget.task['due_date']?.toString();
    if (due != null && due.isNotEmpty) {
      _dueDate = DateTime.tryParse(due)?.toLocal();
    }
    _projectId = widget.task['project_id']?.toString();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final list = await _api.getProjects();
      if (mounted) setState(() => _projects = list);
    } catch (_) {/* dropdown just shows "ללא" */}
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    final iso = _dueDate == null
        ? null
        : '${_dueDate!.toIso8601String().substring(0, 10)}T00:00:00.000Z';
    final hadDue = widget.task['due_date']?.toString().isNotEmpty ?? false;
    final clearDueDate = _dueDate == null && hadDue;
    final clearProject = _projectId == null &&
        (widget.task['project_id']?.toString().isNotEmpty ?? false);
    try {
      await _api.updateTask(
        _taskId,
        content: text,
        priority: _priority,
        dueDate: iso,
        clearDueDate: clearDueDate,
        projectId: _projectId,
        clearProject: clearProject,
      );
      widget.task['content'] = text;
      widget.task['priority'] = _priority;
      widget.task['due_date'] = iso;
      widget.task['project_id'] = _projectId;
      widget.onChanged?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ApiService.friendlyError(e),
              style: const TextStyle(fontFamily: 'Heebo')),
        ));
      }
    }
  }

  Future<void> _addSubtask(String content) async {
    final text = content.trim();
    if (text.isEmpty) return;
    try {
      final r = await _api.addSubtask(_taskId, text);
      final sub = r['subtask'] as Map<String, dynamic>?;
      if (sub != null) {
        setState(() {
          final list = _subtasks..add(sub);
          widget.task['subtasks'] = list;
        });
        widget.onChanged?.call();
      }
    } catch (_) {}
  }

  Future<void> _toggleSubtask(Map<String, dynamic> sub) async {
    final newDone = sub['done'] != true;
    setState(() => sub['done'] = newDone);
    try {
      await _api.updateSubtask(_taskId, sub['id'].toString(), done: newDone);
      widget.onChanged?.call();
    } catch (_) {
      setState(() => sub['done'] = !newDone);
    }
  }

  Future<void> _deleteSubtask(Map<String, dynamic> sub) async {
    setState(() {
      final list = _subtasks..removeWhere((s) => s['id'] == sub['id']);
      widget.task['subtasks'] = list;
    });
    widget.onChanged?.call();
    try {
      await _api.deleteSubtask(_taskId, sub['id'].toString());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('עריכת משימה',
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo')),
              const SizedBox(height: 12),
              TextField(
                controller: _ctrl,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: _decoration('תיאור המשימה...'),
              ),
              const SizedBox(height: 10),
              _priorityRow(),
              const SizedBox(height: 10),
              _dueDateRow(),
              const SizedBox(height: 10),
              _projectRow(),
              const SizedBox(height: 14),
              _subtasksSection(),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'שומר...' : 'שמור',
                      style: const TextStyle(
                          fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityRow() {
    return Row(children: [
      for (final entry in const [
        ('high', '🔴 גבוה'),
        ('medium', '🟡 בינוני'),
        ('low', '🟢 נמוך'),
      ])
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: GestureDetector(
            onTap: () => setState(() => _priority = entry.$1),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _priority == entry.$1
                    ? JC.blue500.withValues(alpha: 0.18)
                    : JC.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _priority == entry.$1 ? JC.blue500 : JC.border,
                    width: _priority == entry.$1 ? 1.2 : 0.8),
              ),
              child: Text(entry.$2,
                  style: TextStyle(
                      color: _priority == entry.$1
                          ? JC.textPrimary
                          : JC.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Heebo')),
            ),
          ),
        ),
    ]);
  }

  Widget _dueDateRow() {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 1)),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 730)),
          builder: (c, child) => Theme(
              data: Theme.of(c).copyWith(
                  colorScheme: ColorScheme.dark(
                      primary: JC.blue500, surface: JC.surface)),
              child: child!),
        );
        if (picked != null) setState(() => _dueDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: _dueDate != null ? JC.blue500 : JC.border,
              width: _dueDate != null ? 1.2 : 0.8),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined,
              size: 16, color: _dueDate != null ? JC.blue400 : JC.textMuted),
          const SizedBox(width: 8),
          Text(
            _dueDate == null
                ? 'תאריך יעד (אופציונלי)'
                : '${_dueDate!.day.toString().padLeft(2, '0')}/'
                    '${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}',
            style: TextStyle(
                color: _dueDate != null ? JC.textPrimary : JC.textMuted,
                fontFamily: 'Heebo',
                fontSize: 14),
          ),
          if (_dueDate != null) ...[
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _dueDate = null),
              child: Icon(Icons.close_rounded, size: 16, color: JC.textMuted),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _projectRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _projectId != null ? JC.blue500 : JC.border,
            width: _projectId != null ? 1.2 : 0.8),
      ),
      child: Row(children: [
        Icon(Icons.folder_open_rounded,
            size: 16, color: _projectId != null ? JC.blue400 : JC.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _projectId,
              dropdownColor: JC.surfaceAlt,
              hint: Text('שייך לפרויקט (אופציונלי)',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14)),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('ללא פרויקט',
                      style: TextStyle(
                          color: JC.textSecondary,
                          fontFamily: 'Heebo',
                          fontSize: 14)),
                ),
                ..._projects.map((p) => DropdownMenuItem<String?>(
                      value: p['id'].toString(),
                      child: Text(p['name']?.toString() ?? '—',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: JC.textPrimary,
                              fontFamily: 'Heebo',
                              fontSize: 14)),
                    )),
              ],
              onChanged: (v) => setState(() => _projectId = v),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _subtasksSection() {
    final subs = _subtasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(Icons.checklist_rounded, size: 16, color: JC.textSecondary),
          const SizedBox(width: 6),
          Text('תתי-משימות (${subs.length})',
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo')),
          const Spacer(),
          GestureDetector(
            onTap: () => showTaskSuggestionsSheet(
              context,
              settings: widget.settings,
              taskId: _taskId,
              onAddSubtask: _addSubtask,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: JC.indigo500.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome_rounded, size: 13, color: JC.indigo300),
                const SizedBox(width: 4),
                Text('הצעות חכמות',
                    style: TextStyle(
                        color: JC.indigo300,
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        ...subs.map((s) => _subtaskRow(s)),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _addCtrl,
              style: TextStyle(
                  color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
              decoration: _decoration('הוסף תת-משימה...'),
              onSubmitted: (v) {
                _addSubtask(v);
                _addCtrl.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              _addSubtask(_addCtrl.text);
              _addCtrl.clear();
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JC.blue500,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _subtaskRow(Map<String, dynamic> s) {
    final done = s['done'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        GestureDetector(
          onTap: () => _toggleSubtask(s),
          child: Icon(
            done ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 20,
            color: done ? JC.green500 : JC.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(s['content']?.toString() ?? '',
              style: TextStyle(
                color: done ? JC.textMuted : JC.textPrimary,
                fontSize: 13,
                fontFamily: 'Heebo',
                decoration: done ? TextDecoration.lineThrough : null,
              )),
        ),
        GestureDetector(
          onTap: () => _deleteSubtask(s),
          child: Icon(Icons.delete_outline_rounded,
              size: 16, color: JC.textMuted),
        ),
      ]),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: JC.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: JC.blue500),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
}

/// AI suggestions sheet. Each suggestion can be added as a subtask (via
/// [onAddSubtask]) and/or as a standalone task (via [onAddStandalone]). At least
/// one callback should be provided.
Future<void> showTaskSuggestionsSheet(
  BuildContext context, {
  required AppSettings settings,
  required String taskId,
  Future<void> Function(String text)? onAddSubtask,
  Future<void> Function(String text)? onAddStandalone,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: JC.surfaceAlt,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _SuggestionsSheet(
      settings: settings,
      taskId: taskId,
      onAddSubtask: onAddSubtask,
      onAddStandalone: onAddStandalone,
    ),
  );
}

class _SuggestionsSheet extends StatefulWidget {
  final AppSettings settings;
  final String taskId;
  final Future<void> Function(String text)? onAddSubtask;
  final Future<void> Function(String text)? onAddStandalone;

  const _SuggestionsSheet({
    required this.settings,
    required this.taskId,
    this.onAddSubtask,
    this.onAddStandalone,
  });

  @override
  State<_SuggestionsSheet> createState() => _SuggestionsSheetState();
}

class _SuggestionsSheetState extends State<_SuggestionsSheet> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = true;
  String? _error;
  final Set<int> _added = {};

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await ApiService(widget.settings).getTaskSuggestions(widget.taskId);
      if (mounted) {
        setState(() {
          _suggestions = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _add(int idx, {required bool asSubtask}) async {
    final text = _suggestions[idx]['text']?.toString() ?? '';
    if (text.isEmpty) return;
    setState(() => _added.add(idx));
    if (asSubtask) {
      await widget.onAddSubtask?.call(text);
    } else {
      await widget.onAddStandalone?.call(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSub = widget.onAddSubtask != null;
    final canStandalone = widget.onAddStandalone != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.auto_awesome_rounded, color: JC.indigo300, size: 16),
                const SizedBox(width: 8),
                Text('הצעות ג׳ארביס',
                    style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Heebo')),
              ]),
              const SizedBox(height: 4),
              Text(
                  canSub && canStandalone
                      ? 'הוסף כל הצעה כתת-משימה או כמשימה עצמאית'
                      : canSub
                          ? 'הוסף הצעה כתת-משימה'
                          : 'הוסף הצעה כמשימה',
                  style: TextStyle(
                      color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
              const SizedBox(height: 14),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(children: [
                      CircularProgressIndicator(
                          strokeWidth: 2, color: JC.indigo300),
                      const SizedBox(height: 12),
                      Text('ג׳ארביס מנתח את המשימה...',
                          style: TextStyle(
                              color: JC.textMuted,
                              fontFamily: 'Heebo',
                              fontSize: 13)),
                    ]),
                  ),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: Text(_error!,
                          style: TextStyle(
                              color: JC.cancelRed,
                              fontFamily: 'Heebo',
                              fontSize: 13))),
                )
              else if (_suggestions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: Text('אין הצעות זמינות',
                          style: TextStyle(
                              color: JC.textMuted,
                              fontFamily: 'Heebo',
                              fontSize: 13))),
                )
              else
                ..._suggestions.asMap().entries.map((e) {
                  final idx = e.key;
                  final sugg = e.value;
                  final done = _added.contains(idx);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: done
                          ? JC.blue500.withValues(alpha: 0.1)
                          : JC.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: done
                              ? JC.blue400.withValues(alpha: 0.4)
                              : JC.border,
                          width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(sugg['text']?.toString() ?? '',
                            style: TextStyle(
                                color: done ? JC.textSecondary : JC.textPrimary,
                                fontSize: 14,
                                fontFamily: 'Heebo')),
                        if ((sugg['reason']?.toString() ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(sugg['reason'].toString(),
                                style: TextStyle(
                                    color: JC.textMuted,
                                    fontSize: 11,
                                    fontFamily: 'Heebo')),
                          ),
                        const SizedBox(height: 8),
                        if (done)
                          Text('נוסף ✓',
                              style: TextStyle(
                                  color: JC.blue400,
                                  fontSize: 12,
                                  fontFamily: 'Heebo',
                                  fontWeight: FontWeight.w600))
                        else
                          Row(children: [
                            if (canSub)
                              _addBtn('תת-משימה', JC.indigo500,
                                  () => _add(idx, asSubtask: true)),
                            if (canSub && canStandalone)
                              const SizedBox(width: 8),
                            if (canStandalone)
                              _addBtn('משימה', JC.blue500,
                                  () => _add(idx, asSubtask: false)),
                          ]),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}
