import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/empty_state.dart';
import '../widgets/kanban_board.dart';
import '../widgets/scrum_view.dart';
import '../widgets/eisenhower_matrix.dart';
import '../widgets/gantt_chart.dart';
import '../widgets/task_edit_sheet.dart';
import 'home/home_helpers.dart' show guardComplete, openSubtaskCount;

// ─── ProjectDetailScreen ──────────────────────────────────────────────────────

class ProjectDetailScreen extends StatefulWidget {
  final Map<String, dynamic> project;
  final AppSettings settings;
  final VoidCallback? onRefresh;

  const ProjectDetailScreen({
    super.key,
    required this.project,
    required this.settings,
    this.onRefresh,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic> _project = {};
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _milestones = [];
  List<Map<String, dynamic>> _sprints = [];
  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;
  List<Map<String, dynamic>> _insights = [];
  bool _insightsLoading = false;

  late TabController _tabController;

  String get _projectId => _project['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _project = Map<String, dynamic>.from(widget.project);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
        _saveTabIndex(_tabController.index);
      }
    });
    _loadTabIndex();
    _loadDetailCache();
    _fetch();
  }

  // Populate from the last cached detail so the screen renders instantly /
  // offline, before the network _fetch resolves. Mirrors the hub's _loadCache.
  Future<void> _loadDetailCache() async {
    try {
      final cached = await CacheService.loadList('project_$_projectId');
      if (cached == null || cached.isEmpty) return;
      final detail = cached.first;
      if (!mounted || _tasks.isNotEmpty || _milestones.isNotEmpty) return;
      final proj = (detail['project'] is Map)
          ? Map<String, dynamic>.from(detail['project'] as Map)
          : null;
      setState(() {
        if (proj != null) _project = proj;
        _tasks = _parseList(detail['tasks']);
        _milestones = _parseList(detail['milestones']);
        _sprints = _parseList(detail['sprints']);
        _reminders = _parseList(detail['reminders']);
        _notes = _parseList(detail['notes']);
        _loading = false;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  Future<void> _loadTabIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('project_tab_${_project['id']}');
      if (saved != null && saved >= 0 && saved < 4 && mounted) {
        setState(() => _tabIndex = saved);
        _tabController.index = saved;
      }
    } catch (_) {}
  }

  Future<void> _saveTabIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('project_tab_${_project['id']}', index);
    } catch (_) {}
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    if (!mounted) return;
    if (_tasks.isEmpty && _milestones.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final detail = await ApiService(widget.settings).getProjectDetail(_projectId);
      final proj = (detail['project'] is Map<String, dynamic>)
          ? detail['project'] as Map<String, dynamic>
          : detail;

      if (mounted) {
        setState(() {
          _project = Map<String, dynamic>.from(proj as Map<String, dynamic>);
          _tasks = _parseList(detail['tasks']);
          _milestones = _parseList(detail['milestones']);
          _sprints = _parseList(detail['sprints']);
          _reminders = _parseList(detail['reminders']);
          _notes = _parseList(detail['notes']);
          _loading = false;
          _error = null;
        });
        CacheService.saveList('project_$_projectId', [detail]);
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

  List<Map<String, dynamic>> _parseList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ─── Progress ─────────────────────────────────────────────────────────────

  double _progress() {
    final total = _tasks.length + _milestones.length;
    if (total == 0) return 0.0;
    final done = _tasks.where((t) => t['done'] == true).length +
        _milestones.where((m) => m['completed'] == true).length;
    return done / total;
  }

  // ─── Methodology helpers ──────────────────────────────────────────────────

  String get _methodology => _project['methodology']?.toString() ?? 'kanban';

  (IconData, String) _methodTabMeta() {
    switch (_methodology) {
      case 'scrum':
        return (Icons.rotate_right_rounded, 'Scrum');
      case 'eisenhower':
        return (Icons.grid_view_rounded, 'מטריצה');
      case 'gantt':
        return (Icons.timeline_rounded, 'Gantt');
      case 'kanban':
      default:
        return (Icons.view_kanban_rounded, 'Kanban');
    }
  }

  // ─── Color ────────────────────────────────────────────────────────────────

  Color _projectColor() {
    final raw = _project['color']?.toString() ?? '';
    if (raw.isEmpty) return JC.indigo500;
    try {
      return Color(int.parse(raw.replaceFirst('#', '0xFF')));
    } catch (_) {
      return JC.indigo500;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final (methodIcon, methodLabel) = _methodTabMeta();
    final headerColor = _projectColor();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: headerColor,
          foregroundColor: Colors.white,
          title: Text(
            _project['name']?.toString() ?? 'פרויקט',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              fontFamily: 'Heebo',
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'ערוך',
              onPressed: _showEditSheet,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              tooltip: 'מחק',
              onPressed: _confirmDelete,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(
                fontFamily: 'Heebo',
                fontSize: 12,
                fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(
                fontFamily: 'Heebo',
                fontSize: 12,
                fontWeight: FontWeight.w400),
            tabs: [
              Tab(icon: Icon(methodIcon, size: 18), text: methodLabel),
              const Tab(
                  icon: Icon(Icons.task_alt_rounded, size: 18),
                  text: 'משימות'),
              const Tab(
                  icon: Icon(Icons.flag_rounded, size: 18),
                  text: 'אבני דרך'),
              const Tab(
                  icon: Icon(Icons.info_outline_rounded, size: 18),
                  text: 'פרטים'),
            ],
          ),
        ),
        body: _loading
            ? const LoadingSkeleton(itemCount: 5, itemHeight: 72)
            : _error != null
                ? _buildError()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMethodView(),
                      _buildTasksTab(),
                      _buildMilestonesTab(),
                      _buildInfoTab(),
                    ],
                  ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: JC.cancelRed, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Heebo', color: JC.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetch,
              child:
                  const Text('נסה שוב', style: TextStyle(fontFamily: 'Heebo')),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tab: methodology view ────────────────────────────────────────────────

  Widget _buildMethodView() {
    switch (_methodology) {
      case 'scrum':
        return ScrumView(
          tasks: _tasks,
          sprints: _sprints,
          projectId: _projectId,
          settings: widget.settings,
          onDataChanged: _fetch,
        );
      case 'eisenhower':
        return EisenhowerMatrix(
          tasks: _tasks,
          projectId: _projectId,
          settings: widget.settings,
          onTaskUpdated: (t) => setState(() {}),
        );
      case 'gantt':
        return GanttChart(
          tasks: _tasks,
          milestones: _milestones,
          project: _project,
        );
      case 'kanban':
      default:
        return KanbanBoard(
          tasks: _tasks,
          projectId: _projectId,
          settings: widget.settings,
          onTaskUpdated: (t) {
            setState(() {
              final idx = _tasks.indexWhere((task) => task['id'] == t['id']);
              if (idx != -1) _tasks[idx] = t;
            });
          },
        );
    }
  }

  // ─── Tab: tasks list ──────────────────────────────────────────────────────

  Widget _buildTasksTab() {
    final active = _tasks.where((t) => t['done'] != true).toList();
    final done = _tasks.where((t) => t['done'] == true).toList();
    final all = [...active, ...done];

    if (all.isEmpty) {
      return EmptyState(
        icon: Icons.task_alt_rounded,
        title: 'אין משימות עדיין',
        subtitle: 'לחץ + כדי להוסיף משימה ראשונה',
      );
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      color: _projectColor(),
      child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: all.length,
      itemBuilder: (ctx, i) {
        final task = all[i];
        final isDone = task['done'] == true;
        final priority = task['priority']?.toString() ?? 'medium';
        return Dismissible(
          key: ValueKey('task_${task['id']}'),
          direction: DismissDirection.endToStart,
          background: _dismissBackground(),
          onDismissed: (_) => _deleteTask(task),
          child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              right: BorderSide(color: _priorityColor(priority), width: 3),
            ),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: () => showTaskEditSheet(
              context,
              settings: widget.settings,
              task: task,
              onChanged: () => setState(() {}),
            ),
            leading: Checkbox(
              value: isDone,
              activeColor: JC.green500,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (v) => _toggleTask(task, v ?? false),
            ),
            title: Text(
              task['content']?.toString() ?? '',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Heebo',
                color: isDone ? JC.textMuted : JC.textPrimary,
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: () {
              final due = task['due_date'];
              final openSubs = openSubtaskCount(task);
              final parts = <String>[
                if (due != null) _shortDate(due.toString()),
                if (openSubs > 0) '☑ $openSubs תתי-משימות פתוחות',
              ];
              if (parts.isEmpty) return null;
              return Text(parts.join('  ·  '),
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 11, fontFamily: 'Heebo', color: JC.textMuted));
            }(),
            trailing: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _priorityColor(priority),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ));
      },
    ));
  }

  // ─── Tab: milestones ──────────────────────────────────────────────────────

  Widget _buildMilestonesTab() {
    if (_milestones.isEmpty) {
      return EmptyState(
        icon: Icons.flag_rounded,
        title: 'אין אבני דרך',
        subtitle: 'לחץ + כדי להוסיף אבן דרך ראשונה',
      );
    }

    return RefreshIndicator(
      onRefresh: _fetch,
      color: _projectColor(),
      child: ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _milestones.length,
      itemBuilder: (ctx, i) {
        final m = _milestones[i];
        final completed = m['completed'] == true;
        return Dismissible(
          key: ValueKey('milestone_${m['id']}'),
          direction: DismissDirection.endToStart,
          background: _dismissBackground(),
          onDismissed: (_) => _deleteMilestone(m),
          child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: () => _showEditMilestoneDialog(m),
            leading: Checkbox(
              value: completed,
              activeColor: JC.green500,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (v) => _toggleMilestone(m, v ?? false),
            ),
            title: Text(
              m['title']?.toString() ?? m['name']?.toString() ?? '',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Heebo',
                color: completed ? JC.textMuted : JC.textPrimary,
                decoration: completed ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: m['due_date'] != null
                ? Text(
                    _shortDate(m['due_date']?.toString()),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        color: JC.textMuted),
                  )
                : null,
            trailing: Icon(
              completed ? Icons.flag_rounded : Icons.flag_outlined,
              color: completed ? JC.green500 : JC.textMuted,
              size: 20,
            ),
          ),
        ));
      },
    ));
  }

  // ─── Tab: info ────────────────────────────────────────────────────────────

  Widget _buildInfoTab() {
    final tasksDone = _tasks.where((t) => t['done'] == true).length;
    final milestonesDone = _milestones.where((m) => m['completed'] == true).length;
    final progress = _progress();

    return RefreshIndicator(
      onRefresh: _fetch,
      color: _projectColor(),
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'סטטיסטיקות',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                    color: JC.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    _statChip(Icons.task_alt_rounded,
                        '$tasksDone/${_tasks.length}', 'משימות', JC.blue500),
                    const SizedBox(width: 10),
                    _statChip(Icons.flag_rounded,
                        '$milestonesDone/${_milestones.length}', 'אבני דרך',
                        JC.indigo500),
                    const SizedBox(width: 10),
                    _statChip(Icons.percent_rounded,
                        '${(progress * 100).toInt()}%', 'התקדמות', JC.green500),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: JC.bg,
                    valueColor: AlwaysStoppedAnimation<Color>(JC.green500),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${(progress * 100).toInt()}% הושלם',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 11, fontFamily: 'Heebo', color: JC.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Description
          if ((_project['description']?.toString() ?? '').isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'תיאור',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                      color: JC.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _project['description']!.toString(),
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: 'Heebo',
                      color: JC.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // AI Insights
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Text(
                      '🤖 תובנות AI',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        color: JC.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if (!_insightsLoading)
                      TextButton(
                        onPressed: _loadInsights,
                        child: Text(
                          'נתח פרויקט',
                          style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              color: JC.blue400),
                        ),
                      ),
                  ],
                ),
                if (_insightsLoading) ...[
                  const SizedBox(height: 12),
                  Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: JC.blue400)),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'מנתח את הפרויקט...',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'Heebo',
                          color: JC.textMuted),
                    ),
                  ),
                ],
                if (!_insightsLoading && _insights.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._insights.map((insight) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: JC.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: JC.blue500.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ',
                              style: TextStyle(
                                  color: JC.blue500,
                                  fontFamily: 'Heebo',
                                  fontWeight: FontWeight.w700)),
                          Expanded(
                            child: Text(
                              insight['text']?.toString() ?? '',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                fontSize: 13,
                                fontFamily: 'Heebo',
                                color: JC.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
                if (!_insightsLoading && _insights.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'לחץ "נתח פרויקט" לקבלת תובנות מותאמות',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Heebo',
                          color: JC.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Reminders (always shown so a deadline reminder can be created)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Text(
                      'תזכורות',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                        color: JC.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    if ((_project['due_date']?.toString() ?? '').isNotEmpty)
                      TextButton.icon(
                        onPressed: _addDeadlineReminder,
                        icon: Icon(Icons.add_alarm_rounded,
                            size: 16, color: JC.amber400),
                        label: Text('תזכורת לדדליין',
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                color: JC.amber400)),
                      ),
                  ],
                ),
                if (_reminders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      (_project['due_date']?.toString() ?? '').isNotEmpty
                          ? 'אין תזכורות. צור תזכורת לדדליין הפרויקט.'
                          : 'אין תזכורות. הוסף דדליין לפרויקט כדי לקבל תזכורת.',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Heebo',
                          color: JC.textMuted),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  ..._reminders.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Icon(Icons.alarm_rounded,
                                size: 15, color: JC.amber400),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                r['text']?.toString() ?? '',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'Heebo',
                                    color: JC.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Notes
          if (_notes.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'הערות',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                      color: JC.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._notes.map((n) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: [
                            Icon(Icons.note_outlined,
                                size: 15, color: JC.indigo300),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                n['title']?.toString() ??
                                    n['content']?.toString() ??
                                    '',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'Heebo',
                                    color: JC.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ],
      ),
    ));
  }

  // ─── FAB ──────────────────────────────────────────────────────────────────

  Widget? _buildFAB() {
    switch (_tabIndex) {
      case 0:
      case 1:
        return FloatingActionButton(
          backgroundColor: _projectColor(),
          foregroundColor: Colors.white,
          tooltip: 'הוסף משימה',
          onPressed: _showAddTaskSheet,
          child: const Icon(Icons.add_rounded),
        );
      case 2:
        return FloatingActionButton(
          backgroundColor: JC.indigo500,
          foregroundColor: Colors.white,
          tooltip: 'הוסף אבן דרך',
          onPressed: _showAddMilestoneDialog,
          child: const Icon(Icons.flag_rounded),
        );
      default:
        return null;
    }
  }

  // ─── Add task sheet ───────────────────────────────────────────────────────

  void _showAddTaskSheet() {
    final contentCtrl = TextEditingController();
    String selectedPriority = 'medium';

    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  const SizedBox(height: 16),
                  Text('משימה חדשה',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                          color: JC.textPrimary)),
                  const SizedBox(height: 14),
                  _sheetTextField(contentCtrl, 'תאר את המשימה...',
                      maxLines: 3, autofocus: true),
                  const SizedBox(height: 14),
                  _sheetLabel('עדיפות'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ('low', 'נמוך', JC.green500),
                      ('medium', 'בינוני', JC.amber400),
                      ('high', 'גבוה', JC.cancelRed),
                    ].map((p) {
                      final (pKey, pLabel, pColor) = p;
                      return ChoiceChip(
                        label: Text(pLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                color: selectedPriority == pKey
                                    ? Colors.white
                                    : JC.textSecondary)),
                        selected: selectedPriority == pKey,
                        selectedColor: pColor,
                        backgroundColor: JC.surface,
                        side: BorderSide(
                            color: selectedPriority == pKey
                                ? pColor
                                : JC.textMuted.withValues(alpha: 0.3)),
                        onSelected: (v) {
                          if (v) setSheetState(() => selectedPriority = pKey);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _projectColor(),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final content = contentCtrl.text.trim();
                        if (content.isEmpty) return;
                        Navigator.pop(ctx);
                        try {
                          final result = await ApiService(widget.settings)
                              .addTask(content,
                                  priority: selectedPriority,
                                  projectId: _projectId);
                          Map<String, dynamic> newTask;
                          if (result['task'] is Map) {
                            newTask = Map<String, dynamic>.from(
                                result['task'] as Map<String, dynamic>);
                          } else {
                            newTask = Map<String, dynamic>.from(result);
                          }
                          newTask['kanban_column'] ??= 'todo';
                          if (mounted) setState(() => _tasks.add(newTask));
                        } catch (_) {}
                      },
                      child: const Text('הוסף משימה',
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // ─── Add milestone dialog ─────────────────────────────────────────────────

  void _showAddMilestoneDialog() {
    final titleCtrl = TextEditingController();
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: JC.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('אבן דרך חדשה',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700,
                      color: JC.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetTextField(titleCtrl, 'שם אבן הדרך'),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: JC.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 16, color: JC.textMuted),
                          const SizedBox(width: 8),
                          Text(
                            selectedDate != null
                                ? '${selectedDate!.day}.${selectedDate!.month}.${selectedDate!.year}'
                                : 'בחר תאריך יעד',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              color: selectedDate != null
                                  ? JC.textPrimary
                                  : JC.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('ביטול',
                      style: TextStyle(
                          fontFamily: 'Heebo', color: JC.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.indigo500,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) return;
                    Navigator.pop(ctx);
                    await _addMilestone(title, selectedDate);
                  },
                  child: const Text('הוסף',
                      style: TextStyle(fontFamily: 'Heebo')),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ─── Edit project sheet ───────────────────────────────────────────────────

  void _showEditSheet() {
    final nameCtrl =
        TextEditingController(text: _project['name']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: _project['description']?.toString() ?? '');
    String selStatus = _project['status']?.toString() ?? 'active';
    String selPriority = _project['priority']?.toString() ?? 'medium';
    String selMethodology = _methodology;
    String selColor = _project['color']?.toString() ?? '#6366f1';

    final methodologies = [
      ('kanban', 'Kanban'),
      ('scrum', 'Scrum'),
      ('eisenhower', 'אייזנהאואר'),
      ('gantt', 'Gantt'),
    ];
    final statuses = [
      ('active', 'פעיל'),
      ('planning', 'בתכנון'),
      ('paused', 'מושהה'),
      ('completed', 'הושלם'),
      ('archived', 'ארכיון'),
    ];
    final priorities = [
      ('low', 'נמוך'),
      ('medium', 'בינוני'),
      ('high', 'גבוה'),
      ('critical', 'קריטי'),
    ];
    final colorHexes = [
      '#6366f1',
      '#3b82f6',
      '#10b981',
      '#f59e0b',
      '#ef4444',
      '#8b5cf6',
      '#ec4899',
      '#14b8a6',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHandle(),
                  const SizedBox(height: 16),
                  Text('ערוך פרויקט',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                          color: JC.textPrimary)),
                  const SizedBox(height: 16),

                  _sheetLabel('שם'),
                  const SizedBox(height: 6),
                  _sheetTextField(nameCtrl, 'שם הפרויקט'),
                  const SizedBox(height: 14),

                  _sheetLabel('תיאור'),
                  const SizedBox(height: 6),
                  _sheetTextField(descCtrl, 'תיאור קצר...', maxLines: 3),
                  const SizedBox(height: 14),

                  _sheetLabel('מתודולוגיה'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: methodologies.map((m) {
                      final (mKey, mLabel) = m;
                      final sel = selMethodology == mKey;
                      return ChoiceChip(
                        label: Text(mLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                color:
                                    sel ? Colors.white : JC.textSecondary)),
                        selected: sel,
                        selectedColor: JC.indigo500,
                        backgroundColor: JC.surface,
                        side: BorderSide(
                            color: sel
                                ? JC.indigo500
                                : JC.textMuted.withValues(alpha: 0.3)),
                        onSelected: (v) {
                          if (v) setSheetState(() => selMethodology = mKey);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  _sheetLabel('עדיפות'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: priorities.map((p) {
                      final (pKey, pLabel) = p;
                      final sel = selPriority == pKey;
                      final pColor = _priorityColor(pKey);
                      return ChoiceChip(
                        label: Text(pLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                color:
                                    sel ? Colors.white : JC.textSecondary)),
                        selected: sel,
                        selectedColor: pColor,
                        backgroundColor: JC.surface,
                        side: BorderSide(
                            color: sel
                                ? pColor
                                : JC.textMuted.withValues(alpha: 0.3)),
                        onSelected: (v) {
                          if (v) setSheetState(() => selPriority = pKey);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  _sheetLabel('סטטוס'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: statuses.map((s) {
                      final (sKey, sLabel) = s;
                      final sel = selStatus == sKey;
                      return ChoiceChip(
                        label: Text(sLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Heebo',
                                color:
                                    sel ? Colors.white : JC.textSecondary)),
                        selected: sel,
                        selectedColor: JC.blue500,
                        backgroundColor: JC.surface,
                        side: BorderSide(
                            color: sel
                                ? JC.blue500
                                : JC.textMuted.withValues(alpha: 0.3)),
                        onSelected: (v) {
                          if (v) setSheetState(() => selStatus = sKey);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  _sheetLabel('צבע'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: colorHexes.map((c) {
                      Color col;
                      try {
                        col = Color(int.parse(c.replaceFirst('#', '0xFF')));
                      } catch (_) {
                        col = JC.indigo500;
                      }
                      final sel = selColor == c;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selColor = c),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: sel
                                ? [
                                    BoxShadow(
                                        color: col.withValues(alpha: 0.5),
                                        blurRadius: 6)
                                  ]
                                : null,
                          ),
                          child: sel
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JC.blue500,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(ctx);
                        try {
                          final updated =
                              await ApiService(widget.settings).updateProject(
                            _projectId,
                            {
                              'name': name,
                              'description': descCtrl.text.trim(),
                              'priority': selPriority,
                              'status': selStatus,
                              'methodology': selMethodology,
                              'color': selColor,
                            },
                          );
                          if (mounted) {
                            setState(() => _project = updated);
                            widget.onRefresh?.call();
                          }
                        } catch (_) {}
                      },
                      child: const Text('שמור שינויים',
                          style: TextStyle(
                              fontSize: 15,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  // ─── Delete confirmation ──────────────────────────────────────────────────

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: JC.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('מחק פרויקט',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700,
                    color: JC.textPrimary)),
            content: Text(
              'האם למחוק את "${_project['name']?.toString() ?? 'הפרויקט'}"?\nפעולה זו אינה הפיכה.',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Heebo',
                  color: JC.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ביטול',
                    style:
                        TextStyle(fontFamily: 'Heebo', color: JC.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: JC.cancelRed,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ApiService(widget.settings).deleteProject(_projectId);
                    if (mounted) {
                      Navigator.of(context).pop();
                      widget.onRefresh?.call();
                    }
                  } catch (_) {}
                },
                child: const Text('מחק',
                    style: TextStyle(fontFamily: 'Heebo')),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Task CRUD ────────────────────────────────────────────────────────────

  Future<void> _toggleTask(Map<String, dynamic> task, bool done) async {
    final taskId = task['id']?.toString() ?? '';
    if (done && openSubtaskCount(task) > 0) {
      final ok = await guardComplete(context, task);
      if (!ok) return;
    }
    // Keep the Kanban column in sync with completion so the board and the list
    // never disagree: completing moves the card to 'done', un-completing to 'todo'.
    final newColumn = done ? 'done' : 'todo';
    final prevColumn = task['kanban_column']?.toString();
    setState(() {
      final idx = _tasks.indexWhere((t) => t['id'] == task['id']);
      if (idx != -1) {
        _tasks[idx]['done'] = done;
        _tasks[idx]['kanban_column'] = newColumn;
      }
    });
    try {
      if (taskId.isNotEmpty) {
        await ApiService(widget.settings)
            .updateTask(taskId, done: done, kanbanColumn: newColumn);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final idx = _tasks.indexWhere((t) => t['id'] == task['id']);
          if (idx != -1) {
            _tasks[idx]['done'] = !done;
            _tasks[idx]['kanban_column'] = prevColumn;
          }
        });
      }
    }
  }

  // ─── Milestone CRUD ───────────────────────────────────────────────────────

  Future<void> _addMilestone(String title, DateTime? dueDate) async {
    // Optimistically add locally; the server endpoint for milestones may vary
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    final optimistic = <String, dynamic>{
      'id': tempId,
      'title': title,
      'completed': false,
      if (dueDate != null) 'due_date': dueDate.toIso8601String(),
    };
    setState(() => _milestones.add(optimistic));
    try {
      final created = await ApiService(widget.settings).createMilestone(
        _projectId,
        title,
        dueDate: dueDate?.toIso8601String().substring(0, 10),
      );
      if (mounted) {
        setState(() {
          final idx = _milestones.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) _milestones[idx] = created;
        });
      }
    } catch (_) {
      // Rollback on failure
      if (mounted) {
        setState(() => _milestones.removeWhere((m) => m['id'] == tempId));
      }
    }
  }

  Future<void> _toggleMilestone(
      Map<String, dynamic> milestone, bool completed) async {
    final milestoneId = milestone['id']?.toString() ?? '';
    setState(() {
      final idx = _milestones.indexWhere((m) => m['id'] == milestone['id']);
      if (idx != -1) _milestones[idx]['completed'] = completed;
    });
    try {
      if (milestoneId.isNotEmpty) {
        await ApiService(widget.settings)
            .updateMilestone(_projectId, milestoneId, {'completed': completed});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final idx = _milestones.indexWhere((m) => m['id'] == milestone['id']);
          if (idx != -1) _milestones[idx]['completed'] = !completed;
        });
      }
    }
  }

  Future<void> _deleteMilestone(Map<String, dynamic> milestone) async {
    final id = milestone['id']?.toString() ?? '';
    final idx = _milestones.indexWhere((m) => m['id'] == milestone['id']);
    final removed = idx != -1 ? _milestones[idx] : milestone;
    setState(() => _milestones.removeWhere((m) => m['id'] == milestone['id']));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('אבן הדרך נמחקה', style: TextStyle(fontFamily: 'Heebo')),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () {
              if (mounted && idx != -1) {
                setState(() => _milestones.insert(
                    idx.clamp(0, _milestones.length), removed));
              }
            },
          ),
        ),
      );
    }
    try {
      if (id.isNotEmpty) {
        await ApiService(widget.settings).deleteMilestone(_projectId, id);
      }
    } catch (_) {
      if (mounted && idx != -1) {
        setState(() =>
            _milestones.insert(idx.clamp(0, _milestones.length), removed));
      }
    }
  }

  void _showEditMilestoneDialog(Map<String, dynamic> milestone) {
    final id = milestone['id']?.toString() ?? '';
    final titleCtrl = TextEditingController(
        text: milestone['title']?.toString() ??
            milestone['name']?.toString() ??
            '');
    DateTime? selectedDate =
        DateTime.tryParse(milestone['due_date']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: JC.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('ערוך אבן דרך',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700,
                      color: JC.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sheetTextField(titleCtrl, 'שם אבן הדרך'),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1460)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: JC.bg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 16, color: JC.textMuted),
                          const SizedBox(width: 8),
                          Text(
                            selectedDate != null
                                ? '${selectedDate!.day}.${selectedDate!.month}.${selectedDate!.year}'
                                : 'בחר תאריך יעד',
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Heebo',
                              color: selectedDate != null
                                  ? JC.textPrimary
                                  : JC.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('ביטול',
                      style:
                          TextStyle(fontFamily: 'Heebo', color: JC.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.indigo500,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty || id.isEmpty) return;
                    Navigator.pop(ctx);
                    final body = <String, dynamic>{
                      'title': title,
                      'due_date':
                          selectedDate?.toIso8601String().substring(0, 10),
                    };
                    setState(() {
                      final idx =
                          _milestones.indexWhere((m) => m['id'] == milestone['id']);
                      if (idx != -1) {
                        _milestones[idx]['title'] = title;
                        if (selectedDate != null) {
                          _milestones[idx]['due_date'] =
                              selectedDate!.toIso8601String();
                        }
                      }
                    });
                    try {
                      await ApiService(widget.settings)
                          .updateMilestone(_projectId, id, body);
                    } catch (_) {
                      if (mounted) _fetch();
                    }
                  },
                  child: const Text('שמור',
                      style: TextStyle(fontFamily: 'Heebo')),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final id = task['id']?.toString() ?? '';
    final idx = _tasks.indexWhere((t) => t['id'] == task['id']);
    final removed = idx != -1 ? _tasks[idx] : task;
    setState(() => _tasks.removeWhere((t) => t['id'] == task['id']));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('המשימה נמחקה', style: TextStyle(fontFamily: 'Heebo')),
          action: SnackBarAction(
            label: 'ביטול',
            onPressed: () {
              if (mounted && idx != -1) {
                setState(
                    () => _tasks.insert(idx.clamp(0, _tasks.length), removed));
              }
            },
          ),
        ),
      );
    }
    try {
      if (id.isNotEmpty) {
        await ApiService(widget.settings).deleteTask(id);
      }
    } catch (_) {
      if (mounted && idx != -1) {
        setState(() => _tasks.insert(idx.clamp(0, _tasks.length), removed));
      }
    }
  }

  Future<void> _addDeadlineReminder() async {
    final dueStr = _project['due_date']?.toString() ?? '';
    final due = DateTime.tryParse(dueStr);
    if (due == null) return;
    final name = _project['name']?.toString() ?? 'הפרויקט';
    // Fire at 09:00 Israel time on the deadline day (mirrors projectAgent).
    final dateOnly = due.toIso8601String().substring(0, 10);
    final scheduledTime = '${dateOnly}T09:00:00+03:00';
    final text = 'פרויקט "$name" — בדוק התקדמות';
    try {
      await ApiService(widget.settings)
          .addReminder(text, scheduledTime, projectId: _projectId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏰ נקבעה תזכורת ל-${due.day}.${due.month} בשעה 09:00',
                style: const TextStyle(fontFamily: 'Heebo')),
          ),
        );
        _fetch();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('שגיאה ביצירת תזכורת',
                  style: TextStyle(fontFamily: 'Heebo'))),
        );
      }
    }
  }

  Widget _dismissBackground() {
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 24),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JC.cancelRed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );
  }

  // ─── AI Insights ──────────────────────────────────────────────────────────

  Future<void> _loadInsights() async {
    if (_insightsLoading) return;
    setState(() => _insightsLoading = true);
    try {
      final insights = await ApiService(widget.settings)
          .getProjectInsights(_projectId, _methodology);
      if (mounted) setState(() { _insights = insights; _insightsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _insightsLoading = false);
    }
  }

  // ─── Reusable helpers ─────────────────────────────────────────────────────

  Widget _sheetHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: JC.textMuted.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _sheetLabel(String text) => Text(
        text,
        textDirection: TextDirection.rtl,
        style: TextStyle(
            fontSize: 13,
            fontFamily: 'Heebo',
            color: JC.textSecondary,
            fontWeight: FontWeight.w500),
      );

  Widget _sheetTextField(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    bool autofocus = false,
  }) {
    return TextField(
      controller: ctrl,
      textDirection: TextDirection.rtl,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: 1,
      style: TextStyle(
          fontSize: 14, fontFamily: 'Heebo', color: JC.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
        filled: true,
        fillColor: JC.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Color _priorityColor(String? p) {
    switch (p) {
      case 'critical':
      case 'high':
        return JC.cancelRed;
      case 'medium':
        return JC.amber400;
      default:
        return JC.green500;
    }
  }

  String _shortDate(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return '';
    return '${d.day}.${d.month}';
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'Heebo',
                color: color,
              ),
            ),
            Text(
              label,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  fontSize: 10, fontFamily: 'Heebo', color: JC.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
