import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';
import 'tasks/tasks_controller.dart';
import 'tasks/views/list_view.dart';
import 'tasks/views/eisenhower_view.dart';
import 'tasks/views/kanban_view.dart';
import 'tasks/views/day_plan_view.dart';

// View order must match _ViewSwitcher._options index order.
const _kViewOrder = ['list', 'day_plan', 'eisenhower', 'kanban'];

int _viewIndex(String v) => _kViewOrder.indexOf(v).clamp(0, 3);
String _viewFromIndex(int i) => _kViewOrder[i.clamp(0, 3)];

/// Modular tasks screen with swipe-between-views (PageView) and persistent
/// filter state. All mutations stay in sync via the shared [TasksController].
class TasksScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;
  // Incremented by ProductivityScreen to trigger the add-task sheet
  final ValueListenable<int>? addTrigger;

  const TasksScreen({
    super.key,
    required this.settings,
    this.onCountUpdate,
    this.addTrigger,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late final TasksController _c;
  late final PageController _pageCtrl;
  late final TextEditingController _searchCtrl;
  late String _view;

  @override
  void initState() {
    super.initState();
    _view = _validView(widget.settings.tasksDefaultView);
    _pageCtrl = PageController(initialPage: _viewIndex(_view));
    _c = TasksController(settings: widget.settings)..start();
    _c.addListener(_pushCount);
    _searchCtrl = TextEditingController(text: _c.searchQuery);
    _searchCtrl.addListener(() => _c.setSearchQuery(_searchCtrl.text));
    widget.addTrigger?.addListener(_onAddTrigger);
  }

  @override
  void dispose() {
    widget.addTrigger?.removeListener(_onAddTrigger);
    _c.removeListener(_pushCount);
    _c.dispose();
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAddTrigger() => _showAddSheet();

  void _pushCount() => widget.onCountUpdate?.call(_c.openCount);

  String _validView(String v) =>
      _kViewOrder.contains(v) ? v : 'list';

  Future<void> _setView(String v) async {
    if (_view == v) return;
    final idx = _viewIndex(v);
    _pageCtrl.animateToPage(idx,
        duration: const Duration(milliseconds: 260), curve: Curves.easeInOut);
    setState(() => _view = v);
    widget.settings.tasksDefaultView = v;
    await widget.settings.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
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
        // ── Global search bar (filters all views via TasksController) ────────
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 2),
          child: JarvisSearchBar(
            controller: _searchCtrl,
            hint: 'חיפוש משימות...',
          ),
        ),
        _ViewSwitcher(current: _view, onChange: _setView, controller: _c),
        Expanded(
          child: RefreshIndicator(
            color: JC.blue400,
            backgroundColor: JC.surfaceAlt,
            onRefresh: _c.refresh,
            child: PageView(
              controller: _pageCtrl,
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              onPageChanged: (i) {
                final v = _viewFromIndex(i);
                if (_view != v) setState(() => _view = v);
              },
              children: [
                TasksListView(controller: _c),
                DayPlanView(controller: _c),
                EisenhowerView(controller: _c),
                KanbanView(controller: _c),
              ],
            ),
          ),
        ),
        if (_c.snack != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: JC.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: JC.blue500.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Text(_c.snack!,
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontFamily: 'Heebo',
                      fontSize: 13)),
            ),
          ),
      ],
    );
  }

  // ─── Smart add-task sheet ────────────────────────────────────────────────

  /// Detects priority from free-text Hebrew/English keywords.
  static String? _detectPriority(String text) {
    if (RegExp(r'דחוף|חשוב|מיידי|!!|urgent|asap', caseSensitive: false)
        .hasMatch(text)) return 'high';
    if (RegExp(r'נמוך|low|אחר כך|אחרי שבוע|אין דחיפות', caseSensitive: false)
        .hasMatch(text)) return 'low';
    return null;
  }

  /// Detects a due-date from common Hebrew time expressions.
  static DateTime? _detectDate(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (text.contains('היום')) return today;
    if (text.contains('מחר')) return today.add(const Duration(days: 1));
    if (text.contains('שישי') || text.contains('יום שישי')) {
      int diff = 5 - now.weekday;
      if (diff <= 0) diff += 7;
      return today.add(Duration(days: diff));
    }
    if (text.contains('שבת')) {
      int diff = 6 - now.weekday;
      if (diff <= 0) diff += 7;
      return today.add(Duration(days: diff));
    }
    if (text.contains('שבוע הבא') || text.contains('בשבוע הבא')) {
      return today.add(const Duration(days: 7));
    }
    return null;
  }

  Future<void> _showAddSheet() async {
    final ctrl = TextEditingController();
    DateTime? dueDate;
    String priority = 'medium';
    bool autoPriority = false;
    String? selectedProjectId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void onTextChanged(String text) {
            final dp = _detectPriority(text);
            if (dp != null && !autoPriority) {
              setSheet(() { priority = dp; autoPriority = true; });
            } else if (dp == null && autoPriority) {
              setSheet(() { priority = 'medium'; autoPriority = false; });
            }
            if (dueDate == null) {
              final dd = _detectDate(text);
              if (dd != null) setSheet(() => dueDate = dd);
            }
          }

          return Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
                20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Title
                Row(children: [
                  const Spacer(),
                  Text('משימה חדשה',
                      style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Heebo')),
                ]),
                const SizedBox(height: 12),

                // Text field — smart detection runs on every keystroke
                TextField(
                  controller: ctrl,
                  textDirection: TextDirection.rtl,
                  autofocus: true,
                  onChanged: onTextChanged,
                  style: TextStyle(
                      color: JC.textPrimary, fontFamily: 'Heebo'),
                  decoration: InputDecoration(
                    hintText: 'תיאור... (מזהה עדיפות ותאריך אוטומטית)',
                    hintStyle: TextStyle(
                        color: JC.textMuted,
                        fontFamily: 'Heebo',
                        fontSize: 13),
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

                // Priority chips (auto-badge when detected from text)
                Row(
                  children: [
                    for (final entry in [
                      ('high', '🔴 גבוה', JC.cancelRed),
                      ('medium', '🟡 בינוני', JC.amber400),
                      ('low', '🟢 נמוך', JC.green500),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: GestureDetector(
                          onTap: () => setSheet(() {
                            priority = entry.$1;
                            autoPriority = false;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(entry.$2,
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
                                if (priority == entry.$1 &&
                                    autoPriority) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: entry.$3.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('auto',
                                        style: TextStyle(
                                            color: entry.$3,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Quick date chips + custom date picker
                _QuickDateRow(
                  selected: dueDate,
                  onSelect: (d) => setSheet(() => dueDate = d),
                  pickerContext: ctx,
                ),
                if (_c.projects.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _ProjectDropdown(
                    projects: _c.projects,
                    selected: selectedProjectId,
                    onChanged: (v) =>
                        setSheet(() => selectedProjectId = v),
                  ),
                ],
                const SizedBox(height: 14),

                // Submit
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
          );
        },
      ),
    );
  }
}

// ─── Quick-date chips ────────────────────────────────────────────────────────

class _QuickDateRow extends StatelessWidget {
  final DateTime? selected;
  final ValueChanged<DateTime?> onSelect;
  final BuildContext pickerContext;
  const _QuickDateRow(
      {required this.selected,
      required this.onSelect,
      required this.pickerContext});

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _nextWeekday(int wd) {
    final n = DateTime.now();
    int diff = wd - n.weekday;
    if (diff <= 0) diff += 7;
    return _today().add(Duration(days: diff));
  }

  static bool _isSame(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final today    = _today();
    final tomorrow = today.add(const Duration(days: 1));
    final friday   = _nextWeekday(5);

    final chips = [('היום', today), ('מחר', tomorrow), ('שישי', friday)];

    // Is the selected date something other than the 3 quick chips?
    final isCustom = selected != null &&
        !_isSame(selected, today) &&
        !_isSame(selected, tomorrow) &&
        !_isSame(selected, friday);

    return Row(
      children: [
        for (final (label, date) in chips) ...[
          _DateChip(
            label: label,
            active: _isSame(selected, date),
            onTap: () =>
                onSelect(_isSame(selected, date) ? null : date),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: pickerContext,
                initialDate: selected ?? today.add(const Duration(days: 1)),
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
                builder: (c, child) => Theme(
                  data: Theme.of(c).copyWith(
                      colorScheme: ColorScheme.dark(
                          primary: JC.blue500, surface: JC.surface)),
                  child: child!,
                ),
              );
              if (picked != null) onSelect(picked);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isCustom ? JC.blue500 : JC.border,
                    width: isCustom ? 1.2 : 0.8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 14,
                      color: isCustom ? JC.blue400 : JC.textMuted),
                  const SizedBox(width: 5),
                  Text(
                    isCustom
                        ? '${selected!.day.toString().padLeft(2, '0')}/'
                            '${selected!.month.toString().padLeft(2, '0')}'
                        : 'תאריך אחר',
                    style: TextStyle(
                        color: isCustom ? JC.textPrimary : JC.textMuted,
                        fontFamily: 'Heebo',
                        fontSize: 12),
                  ),
                  if (selected != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onSelect(null),
                      child: Icon(Icons.close_rounded,
                          size: 13, color: JC.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _DateChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? JC.blue500.withValues(alpha: 0.18) : JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? JC.blue500 : JC.border,
              width: active ? 1.2 : 0.8),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? JC.blue400 : JC.textMuted,
                fontSize: 12,
                fontFamily: 'Heebo',
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }
}

// ─── Project dropdown ─────────────────────────────────────────────────────────

class _ProjectDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> projects;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _ProjectDropdown(
      {required this.projects,
      required this.selected,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected != null ? JC.blue500 : JC.border,
            width: selected != null ? 1.2 : 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded,
              size: 16,
              color: selected != null ? JC.blue400 : JC.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: selected,
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
                  ...projects.map((p) => DropdownMenuItem<String?>(
                        value: p['id'].toString(),
                        child: Text(p['name']?.toString() ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: JC.textPrimary,
                                fontFamily: 'Heebo',
                                fontSize: 14)),
                      )),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── View switcher with live counts ──────────────────────────────────────────

class _ViewSwitcher extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChange;
  final TasksController controller;
  const _ViewSwitcher(
      {required this.current,
      required this.onChange,
      required this.controller});

  static const _options = [
    ('list', 'רשימה', Icons.list_alt_rounded),
    ('day_plan', 'יום', Icons.today_rounded),
    ('eisenhower', 'מטריצה', Icons.grid_view_rounded),
    ('kanban', 'קנבן', Icons.view_kanban_outlined),
  ];

  /// Returns a contextual count badge for each view.
  int? _countFor(String viewId) {
    switch (viewId) {
      case 'list':
        final n = controller.openCount;
        return n > 0 ? n : null;
      case 'eisenhower':
        final n = controller.quadrants['none']?.length ?? 0;
        return n > 0 ? n : null;
      case 'kanban':
        final n = controller.kanbanColumns['doing']?.length ?? 0;
        return n > 0 ? n : null;
      case 'day_plan':
        final n = controller.dayPlanBuckets['now']?.length ?? 0;
        return n > 0 ? n : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _options)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: GestureDetector(
                onTap: () => onChange(o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: current == o.$1
                        ? JC.blue500.withValues(alpha: 0.18)
                        : JC.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: current == o.$1 ? JC.blue500 : JC.border,
                      width: current == o.$1 ? 1.2 : 0.8,
                    ),
                    boxShadow: current == o.$1
                        ? [
                            BoxShadow(
                                color: JC.blue500.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
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
                      const SizedBox(width: 5),
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
                      Builder(builder: (_) {
                        final n = _countFor(o.$1);
                        if (n == null) return const SizedBox.shrink();
                        return Padding(
                          padding:
                              const EdgeInsetsDirectional.only(start: 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: current == o.$1
                                  ? JC.blue500.withValues(alpha: 0.3)
                                  : JC.border.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              n > 99 ? '99+' : n.toString(),
                              style: TextStyle(
                                color: current == o.$1
                                    ? JC.blue400
                                    : JC.textMuted,
                                fontSize: 10,
                                fontFamily: 'Heebo',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }),
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
