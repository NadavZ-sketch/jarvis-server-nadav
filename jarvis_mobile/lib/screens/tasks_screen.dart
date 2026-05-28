import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/task_edit_sheet.dart';
import 'home/home_helpers.dart' show guardComplete, openSubtaskCount;

// ─── Encouragement messages shown after milestone completions ────────────────
const _kEncouragements = [
  '🎉 כל הכבוד! המשימה הושלמה!',
  '✨ עוד אחת בשקית — מעולה!',
  '💪 ג׳ארביס גאה בך!',
  '🔥 אתה מכה אותם אחד אחד!',
  '🌟 שלושה ברצף — ממש יפה!',
  '🚀 חמישה השלמות — מדהים!',
  '🏆 עשר משימות — אלוף!',
];

const _kMilestones = {3, 5, 10, 15, 20};

// ─── TasksScreen ─────────────────────────────────────────────────────────────

class TasksScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const TasksScreen({super.key, required this.settings, this.onCountUpdate});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _showDone     = false;
  String _sortMode         = 'priority'; // 'priority' | 'due_date' | 'created'
  String _filterPriority   = 'all';     // 'all' | 'high' | 'medium' | 'low'
  int _doneThisSession = 0;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _projects = [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    _loadCache();
    _fetch();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final list = await ApiService(widget.settings).getProjects();
      if (mounted) setState(() => _projects = list);
    } catch (_) {/* project selector just won't show options */}
  }

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('tasks');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
      _updateCount();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateCount() {
    final active = _items.where((i) => i['done'] != true).length;
    widget.onCountUpdate?.call(active);
  }

  int _priorityOrder(String? p) => switch (p) {
    'high'   => 0,
    'medium' => 1,
    'low'    => 2,
    _        => 1,
  };

  List<Map<String, dynamic>> get _sorted {
    var src = List<Map<String, dynamic>>.from(_items);

    // Priority filter
    if (_filterPriority != 'all') {
      src = src.where((i) => i['priority'] == _filterPriority).toList();
    }

    final active = src.where((i) => i['done'] != true).toList();
    final done   = src.where((i) => i['done'] == true).toList();

    active.sort((a, b) {
      if (_sortMode == 'priority') {
        final pc = _priorityOrder(a['priority']?.toString())
            .compareTo(_priorityOrder(b['priority']?.toString()));
        if (pc != 0) return pc;
      }
      if (_sortMode == 'due_date' || _sortMode == 'priority') {
        final aDate = a['due_date'] as String?;
        final bDate = b['due_date'] as String?;
        if (aDate != null && bDate != null) return aDate.compareTo(bDate);
        if (aDate != null) return -1;
        if (bDate != null) return 1;
      }
      return (b['created_at'] as String? ?? '')
          .compareTo(a['created_at'] as String? ?? '');
    });

    return _showDone ? [...active, ...done] : active;
  }

  List<Map<String, dynamic>> get _filtered {
    final src = _sorted;
    if (_searchQuery.isEmpty) return src;
    return src
        .where((i) => (i['content']?.toString() ?? '')
            .toLowerCase()
            .contains(_searchQuery))
        .toList();
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService(widget.settings).getTasks();
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        _updateCount();
        CacheService.saveList('tasks', items);
      }
    } catch (e) {
      if (mounted && _items.isEmpty) {
        setState(() { _error = ApiService.friendlyError(e); _loading = false; });
      }
    }
  }

  Future<void> _toggleDone(Map<String, dynamic> item) async {
    final id      = item['id'].toString();
    final newDone = item['done'] != true;
    // Completion guard: open subtasks require explicit confirmation.
    if (newDone && openSubtaskCount(item) > 0) {
      final ok = await guardComplete(context, item);
      if (!ok) return;
    }
    HapticFeedback.selectionClick();
    setState(() => item['done'] = newDone);
    _updateCount();

    if (newDone) {
      _doneThisSession++;
      if (_kMilestones.contains(_doneThisSession)) {
        final msg = _doneThisSession >= 10
            ? '🏆 ${_doneThisSession} משימות הושלמו — מדהים!'
            : _doneThisSession >= 5
                ? '🚀 ${_doneThisSession} משימות ברצף — מעולה!'
                : '🎉 ${_doneThisSession} משימות הושלמו — כל הכבוד!';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFF0F1929),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text(msg,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13)),
            duration: const Duration(seconds: 3),
          ));
        }
      }
    }

    try {
      await ApiService(widget.settings).updateTask(id, done: newDone);
      CacheService.saveList('tasks', _items);
    } catch (_) {
      setState(() => item['done'] = !newDone);
      _updateCount();
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id         = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));
    _updateCount();

    showDeleteSnackbar(
      context,
      message: 'המשימה הוסרה',
      onUndo: () {
        setState(() => _items.insert(savedIndex.clamp(0, _items.length), item));
        _updateCount();
      },
      onClosed: (wasUndone) {
        if (!wasUndone) {
          ApiService(widget.settings).deleteTask(id).catchError((_) {});
        }
      },
    );
  }

  Future<void> _showAddSheet() async {
    final ctrl    = TextEditingController();
    DateTime? dueDate;
    String selectedPriority = 'medium';
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
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('משימה חדשה',
                  style: TextStyle(color: JC.textPrimary, fontSize: 16,
                      fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textDirection: TextDirection.rtl,
                autofocus: true,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: _fieldDecoration('תיאור המשימה...'),
                onSubmitted: (_) => _submitAdd(
                    ctrl.text, dueDate, selectedPriority, ctx,
                    projectId: selectedProjectId),
              ),
              const SizedBox(height: 10),
              // Priority picker
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  for (final entry in [
                    ('high',   '🔴 גבוה',   JC.cancelRed),
                    ('medium', '🟡 בינוני', JC.amber400),
                    ('low',    '🟢 נמוך',   JC.green500),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: GestureDetector(
                        onTap: () => setSheet(() => selectedPriority = entry.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: selectedPriority == entry.$1
                                ? entry.$3.withValues(alpha: 0.18)
                                : JC.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedPriority == entry.$1 ? entry.$3 : JC.border,
                              width: selectedPriority == entry.$1 ? 1.2 : 0.8,
                            ),
                          ),
                          child: Text(entry.$2,
                              style: TextStyle(
                                color: selectedPriority == entry.$1
                                    ? entry.$3
                                    : JC.textSecondary,
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                fontWeight: selectedPriority == entry.$1
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              )),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // Due date row
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (c, child) => Theme(
                        data: Theme.of(c).copyWith(
                          colorScheme: ColorScheme.dark(
                              primary: JC.blue500, surface: JC.surface)),
                        child: child!),
                  );
                  if (picked != null) setSheet(() => dueDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          color: dueDate != null ? JC.blue400 : JC.textMuted),
                      const SizedBox(width: 8),
                      Text(
                        dueDate == null
                            ? 'תאריך יעד (אופציונלי)'
                            : '${dueDate!.day.toString().padLeft(2,'0')}/'
                              '${dueDate!.month.toString().padLeft(2,'0')}/'
                              '${dueDate!.year}',
                        style: TextStyle(
                            color: dueDate != null ? JC.textPrimary : JC.textMuted,
                            fontFamily: 'Heebo', fontSize: 14),
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
              if (_projects.isNotEmpty) ...[
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
                  onPressed: () => _submitAdd(
                      ctrl.text, dueDate, selectedPriority, ctx,
                      projectId: selectedProjectId),
                  child: const Text('הוסף',
                      style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAdd(String text, DateTime? dueDate, String priority,
      BuildContext sheetCtx, {String? projectId}) async {
    final val = text.trim();
    if (val.isEmpty) return;
    Navigator.pop(sheetCtx);
    try {
      final res = await ApiService(widget.settings)
          .addTask(val, priority: priority, projectId: projectId);
      Map<String, dynamic> newItem =
          res['task'] as Map<String, dynamic>? ?? {
            'id': DateTime.now().toString(),
            'content': val,
            'done': false,
            'priority': priority,
            'created_at': DateTime.now().toIso8601String(),
          };
      if (dueDate != null) {
        final isoDate =
            '${dueDate.toIso8601String().substring(0, 10)}T00:00:00.000Z';
        newItem = Map.from(newItem)..['due_date'] = isoDate;
        ApiService(widget.settings)
            .updateTask(newItem['id'].toString(), dueDate: isoDate)
            .catchError((_) {});
      }
      setState(() => _items.insert(0, newItem));
      _updateCount();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('שגיאה בהוספה',
                style: TextStyle(fontFamily: 'Heebo'))));
      }
    }
  }

  String _formatDue(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt    = DateTime.parse(iso.toString()).toLocal();
      final now   = DateTime.now();
      final day   = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day == today) return 'היום';
      if (day == today.add(const Duration(days: 1))) return 'מחר';
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}';
    } catch (_) { return ''; }
  }

  bool _isOverdue(Map<String, dynamic> item) {
    if (item['done'] == true) return false;
    final iso = item['due_date'];
    if (iso == null) return false;
    try {
      return DateTime.parse(iso.toString()).toLocal().isBefore(DateTime.now());
    } catch (_) { return false; }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _items.where((i) => i['done'] == true).length;

    return Scaffold(
      backgroundColor: JC.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const LoadingSkeleton(itemCount: 6)
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'שגיאת טעינה',
                  subtitle: _error!)
              : Column(
                  children: [
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: JarvisSearchBar(
                            controller: _searchCtrl, hint: 'חיפוש במשימות...'),
                      ),
                    // Filter chips + sort menu
                    if (_items.isNotEmpty)
                      _FilterBar(
                        filterPriority: _filterPriority,
                        sortMode: _sortMode,
                        onFilterChange: (v) =>
                            setState(() => _filterPriority = v),
                        onSortChange: (v) => setState(() => _sortMode = v),
                      ),
                    if (doneCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _showDone = !_showDone),
                            child: Text(
                              _showDone
                                  ? 'הסתר בוצעו'
                                  : 'הצג בוצעו ($doneCount)',
                              style: TextStyle(
                                  color: JC.blue400, fontFamily: 'Heebo',
                                  fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.check_circle_outline_rounded,
                              title: _searchQuery.isEmpty
                                  ? 'אין משימות פתוחות'
                                  : 'לא נמצאו תוצאות',
                              subtitle: _searchQuery.isEmpty
                                  ? 'לחץ + להוספת משימה'
                                  : '')
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surfaceAlt,
                              onRefresh: _fetch,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final item     = _filtered[i];
                                  final isDone   = item['done'] == true;
                                  final overdue  = _isOverdue(item);
                                  final dueLabel = _formatDue(item['due_date']);
                                  return AnimatedListItem(
                                    index: i,
                                    child: Dismissible(
                                      key: ValueKey(item['id']),
                                      direction: DismissDirection.endToStart,
                                      background: _dismissBg(),
                                      onDismissed: (_) => _onDismissed(item),
                                      child: _TaskItem(
                                        item: item,
                                        isDone: isDone,
                                        overdue: overdue,
                                        dueLabel: dueLabel,
                                        settings: widget.settings,
                                        onToggle: () => _toggleDone(item),
                                        onUpdated: () => setState(() {}),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

// ─── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String filterPriority;
  final String sortMode;
  final ValueChanged<String> onFilterChange;
  final ValueChanged<String> onSortChange;

  const _FilterBar({
    required this.filterPriority,
    required this.sortMode,
    required this.onFilterChange,
    required this.onSortChange,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          _PriorityChip(
              label: 'הכל',
              active: filterPriority == 'all',
              color: JC.blue400,
              onTap: () => onFilterChange('all')),
          const SizedBox(width: 6),
          _PriorityChip(
              label: '🔴 גבוה',
              active: filterPriority == 'high',
              color: JC.cancelRed,
              onTap: () => onFilterChange('high')),
          const SizedBox(width: 6),
          _PriorityChip(
              label: '🟡 בינוני',
              active: filterPriority == 'medium',
              color: JC.amber400,
              onTap: () => onFilterChange('medium')),
          const SizedBox(width: 6),
          _PriorityChip(
              label: '🟢 נמוך',
              active: filterPriority == 'low',
              color: JC.green500,
              onTap: () => onFilterChange('low')),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: onSortChange,
            color: JC.surfaceAlt,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JC.border, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 14, color: JC.textSecondary),
                  const SizedBox(width: 4),
                  Text(_sortLabel(sortMode),
                      style: TextStyle(
                          color: JC.textSecondary, fontSize: 12,
                          fontFamily: 'Heebo')),
                ],
              ),
            ),
            itemBuilder: (_) => [
              _menuItem('priority', 'לפי עדיפות', sortMode),
              _menuItem('due_date', 'לפי תאריך',  sortMode),
              _menuItem('created',  'לפי יצירה',  sortMode),
            ],
          ),
        ],
      ),
    );
  }

  String _sortLabel(String mode) => switch (mode) {
    'due_date' => 'תאריך',
    'created'  => 'יצירה',
    _          => 'עדיפות',
  };

  PopupMenuItem<String> _menuItem(String value, String label, String current) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            if (current == value)
              Icon(Icons.check_rounded, size: 14, color: JC.blue400),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13)),
          ],
        ),
      );
}

class _PriorityChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _PriorityChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : JC.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? color : JC.border,
              width: active ? 1.2 : 0.8),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? color : JC.textMuted,
              fontSize: 12,
              fontFamily: 'Heebo',
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
    );
  }
}

// ─── Task item widget ─────────────────────────────────────────────────────────

const _kPromptSep = '<<<AI_PROMPT>>>';

class _TaskItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isDone;
  final bool overdue;
  final String dueLabel;
  final AppSettings settings;
  final VoidCallback onToggle;
  final VoidCallback onUpdated;

  const _TaskItem({
    required this.item,
    required this.isDone,
    required this.overdue,
    required this.dueLabel,
    required this.settings,
    required this.onToggle,
    required this.onUpdated,
  });

  @override
  State<_TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<_TaskItem> {
  bool _promptExpanded = false;

  Color get _priorityColor => switch (widget.item['priority']?.toString()) {
    'high'   => JC.cancelRed,
    'low'    => JC.green500,
    _        => JC.amber400,
  };

  void _showEditSheet() {
    showTaskEditSheet(
      context,
      settings: widget.settings,
      task: widget.item,
      onChanged: widget.onUpdated,
    );
  }

  void _showAiSuggestions() {
    final taskId = widget.item['id'].toString();
    showTaskSuggestionsSheet(
      context,
      settings: widget.settings,
      taskId: taskId,
      onAddSubtask: (text) async {
        try {
          final r = await ApiService(widget.settings).addSubtask(taskId, text);
          final sub = r['subtask'] as Map<String, dynamic>?;
          if (sub != null) {
            final raw = widget.item['subtasks'];
            final list = raw is List
                ? List<Map<String, dynamic>>.from(raw)
                : <Map<String, dynamic>>[];
            list.add(sub);
            widget.item['subtasks'] = list;
            widget.onUpdated();
          }
        } catch (_) {}
      },
      onAddStandalone: (text) async {
        try {
          await ApiService(widget.settings).addTask(text);
          widget.onUpdated();
        } catch (_) {}
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final raw      = widget.item['content']?.toString() ?? '';
    final sepIdx   = raw.indexOf('\n$_kPromptSep\n');
    final hasPrompt = sepIdx != -1;
    final title    = hasPrompt ? raw.substring(0, sepIdx) : raw;
    final prompt   = hasPrompt ? raw.substring(sepIdx + '\n$_kPromptSep\n'.length) : '';

    return GestureDetector(
      onLongPress: _showEditSheet,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: widget.isDone ? JC.surface.withValues(alpha: 0.6) : JC.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasPrompt
                ? JC.indigo500.withValues(alpha: 0.5)
                : widget.overdue
                    ? JC.cancelRed.withValues(alpha: 0.4)
                    : JC.border,
            width: hasPrompt ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          children: [
            // ── Main row ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  GestureDetector(
                    onTap: widget.onToggle,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        widget.isDone
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(widget.isDone),
                        color: widget.isDone
                            ? JC.blue400.withValues(alpha: 0.6)
                            : JC.blue500,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          title,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: widget.isDone ? JC.textMuted : JC.textPrimary,
                            fontSize: 15,
                            fontFamily: 'Heebo',
                            decoration: widget.isDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (widget.dueLabel.isNotEmpty)
                          Text(
                            widget.dueLabel,
                            style: TextStyle(
                              color: widget.overdue ? JC.cancelRed : JC.textMuted,
                              fontSize: 11,
                              fontFamily: 'Heebo',
                              fontWeight: widget.overdue
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // AI suggest button (only on active tasks)
                  if (!widget.isDone) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _showAiSuggestions,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: JC.indigo500.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.auto_awesome_rounded,
                            size: 14, color: JC.indigo300),
                      ),
                    ),
                  ],
                  if (hasPrompt) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _promptExpanded = !_promptExpanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: JC.indigo500.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: JC.indigo500.withValues(alpha: 0.4),
                              width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🤖', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 3),
                            Text(
                              _promptExpanded ? 'סגור' : 'פרומפט',
                              style: TextStyle(
                                color: JC.indigo300, fontSize: 11,
                                fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              _promptExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: JC.indigo300, size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // Priority dot
                  const SizedBox(width: 8),
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: _priorityColor),
                  ),
                ],
              ),
            ),

            // ── Expanded prompt section ────────────────────────────────────
            if (hasPrompt && _promptExpanded)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF080F1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: JC.indigo500.withValues(alpha: 0.25), width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Text('פרומפט AI לפיתוח',
                              style: TextStyle(color: JC.indigo300,
                                  fontFamily: 'Heebo', fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: prompt));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF0F1929),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  content: const Text('הפרומפט הועתק ✓',
                                      style: TextStyle(
                                          color: Color(0xFFF1F5F9),
                                          fontFamily: 'Heebo', fontSize: 13)),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2E4A),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy_rounded,
                                      color: JC.textMuted, size: 12),
                                  SizedBox(width: 4),
                                  Text('העתק',
                                      style: TextStyle(color: JC.textMuted,
                                          fontFamily: 'Heebo', fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 0.5, color: const Color(0xFF1A2E4A)),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(prompt,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontFamily: 'Heebo', fontSize: 13, height: 1.7)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _fieldDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
      filled: true,
      fillColor: JC.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: JC.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: JC.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: JC.blue500)),
    );

Widget _dismissBg() => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );
