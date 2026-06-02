import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import 'tasks/tasks_controller.dart';
import 'tasks/views/list_view.dart';
import 'tasks/views/eisenhower_view.dart';
import 'tasks/views/kanban_view.dart';
import 'tasks/views/day_plan_view.dart';

/// Modular tasks screen. Owns a [TasksController] and renders one of four
/// view modes; every view shares the same controller so optimistic mutations
/// (complete, drag, edit-inline, AI suggestion → subtask) stay in sync.
class TasksScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const TasksScreen({super.key, required this.settings, this.onCountUpdate});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final TasksController _c;
  late String _view; // 'list' | 'eisenhower' | 'kanban' | 'day_plan'

  @override
  void initState() {
    super.initState();
    _view = _validView(widget.settings.tasksDefaultView);
    _c = TasksController(settings: widget.settings)..start();
    _c.addListener(_pushCount);
  }

  @override
  void dispose() {
    _c.removeListener(_pushCount);
    _c.dispose();
    super.dispose();
  }

  void _pushCount() => widget.onCountUpdate?.call(_c.openCount);

  String _validView(String v) =>
      const {'list', 'eisenhower', 'kanban', 'day_plan'}.contains(v)
          ? v
          : 'list';

  Future<void> _setView(String v) async {
    setState(() => _view = v);
    widget.settings.tasksDefaultView = v;
    await widget.settings.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _c,
          builder: (_, __) => _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_c.loading && _c.tasks.isEmpty) {
      return const LoadingSkeleton(itemCount: 6);
    }
    if (_c.error != null && _c.tasks.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'שגיאת טעינה',
        subtitle: _c.error!,
      );
    }
    return Column(
      children: [
        _ViewSwitcher(current: _view, onChange: _setView),
        Expanded(
          child: RefreshIndicator(
            color: JC.blue400,
            backgroundColor: JC.surfaceAlt,
            onRefresh: _c.refresh,
            child: _viewBody(),
          ),
        ),
        if (_c.snack != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: JC.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: JC.blue500.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Text(_c.snack!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontFamily: 'Heebo',
                      fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _viewBody() {
    switch (_view) {
      case 'eisenhower':
        return EisenhowerView(controller: _c);
      case 'kanban':
        return KanbanView(controller: _c);
      case 'day_plan':
        return DayPlanView(controller: _c);
      case 'list':
      default:
        return TasksListView(controller: _c);
    }
  }

  // ─── Add task sheet ─────────────────────────────────────────────────────────

  Future<void> _showAddSheet() async {
    final ctrl = TextEditingController();
    DateTime? dueDate;
    String priority = 'medium';
    String? selectedProjectId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('משימה חדשה',
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo')),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textDirection: TextDirection.rtl,
                autofocus: true,
                style: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  hintText: 'תיאור המשימה...',
                  hintStyle:
                      TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                  filled: true,
                  fillColor: JC.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.blue500)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  for (final entry in [
                    ('high', '🔴 גבוה', JC.cancelRed),
                    ('medium', '🟡 בינוני', JC.amber400),
                    ('low', '🟢 נמוך', JC.green500),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => setSheet(() => priority = entry.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: priority == entry.$1
                                ? entry.$3.withValues(alpha: 0.18)
                                : JC.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: priority == entry.$1
                                  ? entry.$3
                                  : JC.border,
                              width: priority == entry.$1 ? 1.2 : 0.8,
                            ),
                          ),
                          child: Text(entry.$2,
                              style: TextStyle(
                                color: priority == entry.$1
                                    ? entry.$3
                                    : JC.textSecondary,
                                fontSize: 12,
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
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                          colorScheme: ColorScheme.dark(
                              primary: JC.blue500, surface: JC.surface)),
                      child: child!,
                    ),
                  );
                  if (picked != null) setSheet(() => dueDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: JC.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: dueDate != null ? JC.blue500 : JC.border,
                        width: dueDate != null ? 1.2 : 0.8),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 16,
                          color: dueDate != null
                              ? JC.blue400
                              : JC.textMuted),
                      const SizedBox(width: 8),
                      Text(
                        dueDate == null
                            ? 'תאריך יעד (אופציונלי)'
                            : '${dueDate!.day.toString().padLeft(2, '0')}/'
                                '${dueDate!.month.toString().padLeft(2, '0')}/'
                                '${dueDate!.year}',
                        style: TextStyle(
                            color: dueDate != null
                                ? JC.textPrimary
                                : JC.textMuted,
                            fontFamily: 'Heebo',
                            fontSize: 14),
                      ),
                      if (dueDate != null) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setSheet(() => dueDate = null),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: JC.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_c.projects.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: JC.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selectedProjectId != null
                            ? JC.blue500
                            : JC.border,
                        width: selectedProjectId != null ? 1.2 : 0.8),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.folder_open_rounded,
                          size: 16,
                          color: selectedProjectId != null
                              ? JC.blue400
                              : JC.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            isExpanded: true,
                            value: selectedProjectId,
                            dropdownColor: JC.surfaceAlt,
                            hint: Text('שייך לפרויקט (אופציונלי)',
                                style: TextStyle(
                                    color: JC.textMuted,
                                    fontFamily: 'Heebo',
                                    fontSize: 14)),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text('ללא פרויקט',
                                    style: TextStyle(
                                        color: JC.textSecondary,
                                        fontFamily: 'Heebo',
                                        fontSize: 14)),
                              ),
                              ..._c.projects.map((p) => DropdownMenuItem<String?>(
                                    value: p['id'].toString(),
                                    child: Text(p['name']?.toString() ?? '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: JC.textPrimary,
                                            fontFamily: 'Heebo',
                                            fontSize: 14)),
                                  )),
                            ],
                            onChanged: (v) =>
                                setSheet(() => selectedProjectId = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final text = ctrl.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx);
                    final r = await _c.addTask(text,
                        priority: priority,
                        projectId: selectedProjectId,
                        dueDate: dueDate);
                    if (r != null) _c.showSnack('משימה נוספה ✓');
                  },
                  child: const Text('הוסף',
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChange;
  const _ViewSwitcher({required this.current, required this.onChange});

  static const _options = [
    ('list', 'רשימה', Icons.list_alt_rounded),
    ('day_plan', 'יום', Icons.today_rounded),
    ('eisenhower', 'מטריצה', Icons.grid_view_rounded),
    ('kanban', 'קנבן', Icons.view_kanban_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _options)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => onChange(o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: current == o.$1
                        ? JC.blue500.withValues(alpha: 0.18)
                        : JC.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: current == o.$1 ? JC.blue500 : JC.border,
                      width: current == o.$1 ? 1.2 : 0.8,
                    ),
                    boxShadow: current == o.$1
                        ? [
                            BoxShadow(
                              color: JC.blue500.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(o.$3,
                          size: 14,
                          color: current == o.$1
                              ? JC.blue400
                              : JC.textSecondary),
                      const SizedBox(width: 6),
                      Text(o.$2,
                          style: TextStyle(
                            color: current == o.$1
                                ? JC.blue400
                                : JC.textSecondary,
                            fontSize: 12.5,
                            fontFamily: 'Heebo',
                            fontWeight: current == o.$1
                                ? FontWeight.w600
                                : FontWeight.normal,
                          )),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

