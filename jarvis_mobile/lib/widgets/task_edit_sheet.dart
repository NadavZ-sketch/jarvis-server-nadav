import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import 'tasks/task_category.dart';

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
  final TextEditingController _tagInputCtrl = TextEditingController();
  late String _priority = widget.task['priority']?.toString() ?? 'medium';
  late String _category = widget.task['category']?.toString() ?? 'general';
  // 'none' | 'daily' | 'weekly' | 'monthly'
  late String _recurrence =
      _normalizeRecurrence(widget.task['recurrence']?.toString());
  late List<String> _tags =
      List<String>.from(widget.task['tags'] as List? ?? []);
  DateTime? _dueDate;
  String? _projectId;

  static const _recurrenceOptions = [
    ('none',    'חד-פעמי', Icons.looks_one_rounded),
    ('daily',   'יומי',    Icons.today_rounded),
    ('weekly',  'שבועי',   Icons.date_range_rounded),
    ('monthly', 'חודשי',   Icons.calendar_month_rounded),
  ];

  static String _normalizeRecurrence(String? r) =>
      (r == 'daily' || r == 'weekly' || r == 'monthly') ? r! : 'none';

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
    _tagInputCtrl.dispose();
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
        category: _category,
        recurrence: _recurrence, // 'none' clears it server-side
        tags: _tags,
        dueDate: iso,
        clearDueDate: clearDueDate,
        projectId: _projectId,
        clearProject: clearProject,
      );
      widget.task['content'] = text;
      widget.task['priority'] = _priority;
      widget.task['category'] = _category;
      widget.task['recurrence'] = _recurrence == 'none' ? null : _recurrence;
      widget.task['tags'] = List<String>.from(_tags);
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

  void _addTag(String v) {
    final t = v.trim().toLowerCase();
    if (t.isEmpty || t.length > 30 || _tags.length >= 10 || _tags.contains(t)) return;
    setState(() {
      _tags.add(t);
      _tagInputCtrl.clear();
    });
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
              _categoryRow(),
              const SizedBox(height: 10),
              _dueDateRow(),
              const SizedBox(height: 10),
              _recurrenceRow(),
              const SizedBox(height: 10),
              _tagsRow(),
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
          padding: const EdgeInsetsDirectional.only(end: 6),
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

  Widget _categoryRow() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      textDirection: TextDirection.rtl,
      children: [
        for (final c in kTaskCategories)
          GestureDetector(
            onTap: () => setState(() => _category = c.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _category == c.id
                    ? c.color().withValues(alpha: 0.18)
                    : JC.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _category == c.id ? c.color() : JC.border,
                    width: _category == c.id ? 1.2 : 0.8),
              ),
              child: Text('${c.emoji} ${c.label}',
                  style: TextStyle(
                      color: _category == c.id
                          ? JC.textPrimary
                          : JC.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Heebo')),
            ),
          ),
      ],
    );
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

  Widget _recurrenceRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.repeat_rounded, size: 15, color: JC.textSecondary),
              const SizedBox(width: 6),
              Text('חזרתיות',
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo')),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          textDirection: TextDirection.rtl,
          children: [
            for (final opt in _recurrenceOptions)
              GestureDetector(
                onTap: () => setState(() => _recurrence = opt.$1),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _recurrence == opt.$1
                        ? JC.blue500.withValues(alpha: 0.18)
                        : JC.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: _recurrence == opt.$1 ? JC.blue500 : JC.border,
                        width: _recurrence == opt.$1 ? 1.2 : 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(opt.$3,
                          size: 13,
                          color: _recurrence == opt.$1
                              ? JC.blue400
                              : JC.textMuted),
                      const SizedBox(width: 5),
                      Text(opt.$2,
                          style: TextStyle(
                              color: _recurrence == opt.$1
                                  ? JC.textPrimary
                                  : JC.textSecondary,
                              fontSize: 12,
                              fontFamily: 'Heebo')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _tagsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_offer_outlined, size: 15, color: JC.textSecondary),
              const SizedBox(width: 6),
              Text('תגיות',
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo')),
            ],
          ),
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: [
              for (final tag in _tags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: JC.indigo300.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: JC.indigo300, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('#$tag',
                          style: TextStyle(
                              color: JC.indigo300,
                              fontSize: 12,
                              fontFamily: 'Heebo')),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() => _tags.remove(tag)),
                        child: Icon(Icons.close_rounded,
                            size: 13, color: JC.indigo300),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _tagInputCtrl,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
              decoration: _decoration('הוסף תגית...'),
              onSubmitted: (v) => _addTag(v),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _addTag(_tagInputCtrl.text),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: JC.indigo300.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JC.indigo300, width: 0.8),
              ),
              child: Icon(Icons.add_rounded, color: JC.indigo300, size: 18),
            ),
          ),
        ]),
      ],
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
          // AI suggestions live on the card itself (✨) — single surface.
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
