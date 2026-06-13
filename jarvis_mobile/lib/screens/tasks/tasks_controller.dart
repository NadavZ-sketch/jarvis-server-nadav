import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';
import '../../widgets/tasks/task_category.dart';

/// A labelled group of tasks rendered as one collapsible section.
typedef TaskSection = ({String key, String label, List<Map<String, dynamic>> tasks});

/// State + actions for the redesigned tasks screen.
///
/// Loads tasks plus the Smart Day Engine context (`/day-plan`) and exposes
/// optimistic mutations plus [groupedSections] so the single smart list can
/// regroup by time / priority / category while staying live.
class TasksController extends ChangeNotifier with WidgetsBindingObserver {
  TasksController({required this.settings}) : api = ApiService(settings);

  final AppSettings settings;
  final ApiService api;

  static const _autoRefreshInterval = Duration(seconds: 60);
  Timer? _refreshTimer;

  // ── Core data ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> projects = [];
  bool loading = true;
  String? error;

  // ── Smart Day Engine ──────────────────────────────────────────────────────
  Map<String, dynamic>? dayPlan;
  bool dayPlanLoading = false;
  String? dayPlanError;
  DateTime? _lastDayPlanAt;

  static const _dayPlanMinInterval = Duration(minutes: 15);
  bool get _dayPlanRefreshDue =>
      _lastDayPlanAt == null ||
      DateTime.now().difference(_lastDayPlanAt!) > _dayPlanMinInterval;

  // ── Per-task AI suggestions cache ─────────────────────────────────────────
  final Map<String, List<Map<String, dynamic>>> suggestions = {};
  final Set<String> suggestionLoading = {};

  // ── Transient UI state ────────────────────────────────────────────────────
  int doneThisSession = 0;
  String? snack;
  Timer? _snackTimer;

  // ── Filter state — survives tab switches ──────────────────────────────────
  String filterPriority = 'all';
  String filterCategory = 'all';
  String filterSort     = 'priority';
  String searchQuery    = '';
  bool   showDone       = false;

  void setFilterPriority(String v) { filterPriority = v; notifyListeners(); }
  void setFilterCategory(String v) { filterCategory = v; notifyListeners(); }
  void setFilterSort(String v)     { filterSort     = v; notifyListeners(); }
  void setSearchQuery(String v)    { searchQuery    = v; notifyListeners(); }
  void toggleShowDone()            { showDone = !showDone; notifyListeners(); }

  static int _po(String? p) =>
      switch (p) { 'high' => 0, 'medium' => 1, 'low' => 2, _ => 1 };

  List<Map<String, dynamic>> get filteredTasks {
    var src = List<Map<String, dynamic>>.from(tasks);
    if (filterPriority != 'all') {
      src = src.where((t) => t['priority'] == filterPriority).toList();
    }
    if (filterCategory != 'all') {
      src = src.where((t) {
        final c = t['category']?.toString();
        if (filterCategory == 'general') {
          return c == null || c.isEmpty || c == 'general';
        }
        return c == filterCategory;
      }).toList();
    }
    final active = src.where((t) => t['done'] != true).toList();
    final done   = src.where((t) => t['done'] == true).toList();
    active.sort((a, b) {
      if (filterSort == 'priority') {
        final pc = _po(a['priority']?.toString())
            .compareTo(_po(b['priority']?.toString()));
        if (pc != 0) return pc;
      }
      if (filterSort == 'due_date' || filterSort == 'priority') {
        final ad = a['due_date'] as String?;
        final bd = b['due_date'] as String?;
        if (ad != null && bd != null) return ad.compareTo(bd);
        if (ad != null) return -1;
        if (bd != null) return 1;
      }
      return (b['created_at'] as String? ?? '')
          .compareTo(a['created_at'] as String? ?? '');
    });
    final all = showDone ? [...active, ...done] : active;
    if (searchQuery.isEmpty) return all;
    final q = searchQuery.toLowerCase();
    return all
        .where((t) =>
            (t['content']?.toString() ?? '').toLowerCase().contains(q))
        .toList();
  }

  /// Public alias for [notifyListeners] so child widgets can trigger a rebuild
  /// when they mutate a task map in place (e.g. inline edits, edit sheet).
  void notify() => notifyListeners();

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _loadCache();
    load();
    _refreshTimer =
        Timer.periodic(_autoRefreshInterval, (_) => _silentRefresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _snackTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _silentRefresh(refreshDayPlan: _dayPlanRefreshDue);
    }
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('tasks');
    if (cached != null && tasks.isEmpty) {
      tasks = cached;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (tasks.isEmpty) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final res = await Future.wait([
        api.getTasks(),
        api.getProjects().catchError((_) async => <Map<String, dynamic>>[]),
      ]);
      tasks = res[0];
      projects = res[1];
      loading = false;
      error = null;
      CacheService.saveList('tasks', tasks);
      notifyListeners();
      _loadDayPlan();
    } catch (e) {
      if (tasks.isEmpty) {
        error = ApiService.friendlyError(e);
      }
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  Future<void> _silentRefresh({bool refreshDayPlan = false}) async {
    try {
      tasks = await api.getTasks();
      CacheService.saveList('tasks', tasks);
      notifyListeners();
    } catch (_) {/* keep last good data */}
    if (refreshDayPlan || _dayPlanRefreshDue) _loadDayPlan();
  }

  Future<void> _loadDayPlan() async {
    dayPlanLoading = true;
    dayPlanError = null;
    notifyListeners();
    try {
      dayPlan = await api.getDayPlan();
      _lastDayPlanAt = DateTime.now();
    } catch (e) {
      dayPlanError = ApiService.friendlyError(e);
      dayPlan = null;
    }
    dayPlanLoading = false;
    notifyListeners();
  }

  // ── Mutations (optimistic) ────────────────────────────────────────────────

  Future<void> toggleDone(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    final prev = task['done'] == true;
    task['done'] = !prev;
    if (!prev) doneThisSession++;
    notifyListeners();
    try {
      await api.updateTask(id, done: !prev);
      CacheService.saveList('tasks', tasks);
    } catch (_) {
      task['done'] = prev;
      if (!prev) doneThisSession--;
      notifyListeners();
    }
  }

  Future<void> deleteTask(Map<String, dynamic> task) async {
    final idx = tasks.indexOf(task);
    tasks.remove(task);
    notifyListeners();
    try {
      await api.deleteTask(task['id'].toString());
      CacheService.saveList('tasks', tasks);
    } catch (_) {
      tasks.insert(idx.clamp(0, tasks.length), task);
      notifyListeners();
    }
  }

  /// Local-only remove (no API call). Pair with [restoreTask] / [commitDelete]
  /// to power Dismissible + undo-snackbar flows.
  int removeLocal(Map<String, dynamic> task) {
    final idx = tasks.indexOf(task);
    if (idx != -1) {
      tasks.removeAt(idx);
      notifyListeners();
    }
    return idx;
  }

  void restoreTask(Map<String, dynamic> task, int index) {
    tasks.insert(index.clamp(0, tasks.length), task);
    notifyListeners();
  }

  Future<void> commitDelete(Map<String, dynamic> task) async {
    try {
      await api.deleteTask(task['id'].toString());
      CacheService.saveList('tasks', tasks);
    } catch (_) {/* ignore — best effort */}
  }

  Future<void> setDueDate(Map<String, dynamic> task, DateTime when) async {
    final id = task['id'].toString();
    final prev = task['due_date'];
    final iso = when.toUtc().toIso8601String();
    task['due_date'] = iso;
    notifyListeners();
    try {
      await api.updateTask(id, dueDate: iso);
    } catch (_) {
      task['due_date'] = prev;
      notifyListeners();
    }
  }

  Future<void> postpone(Map<String, dynamic> task, {int days = 1}) async {
    final next = DateTime.now().add(Duration(days: days));
    final at = DateTime(next.year, next.month, next.day, 9);
    await setDueDate(task, at);
    showSnack('המשימה נדחתה ל-${_dayLabel(days)} ✓');
  }

  Future<Map<String, dynamic>?> addTask(
    String content, {
    String priority = 'medium',
    String? projectId,
    DateTime? dueDate,
  }) async {
    try {
      final res = await api.addTask(content,
          priority: priority,
          projectId: projectId,
          dueDate: dueDate?.toUtc().toIso8601String());
      final t = res['task'] as Map<String, dynamic>? ??
          {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'content': content,
            'priority': priority,
            'done': false,
            'created_at': DateTime.now().toIso8601String(),
            if (dueDate != null) 'due_date': dueDate.toUtc().toIso8601String(),
          };
      tasks.insert(0, t);
      CacheService.saveList('tasks', tasks);
      notifyListeners();
      return t;
    } catch (e) {
      showSnack('שגיאה: ${ApiService.friendlyError(e)}');
      return null;
    }
  }

  // ── AI suggestions ────────────────────────────────────────────────────────

  Future<void> fetchSuggestions(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    if (suggestionLoading.contains(id)) return;
    suggestionLoading.add(id);
    notifyListeners();
    try {
      final list = await api.getTaskSuggestions(id);
      suggestions[id] = list;
    } catch (e) {
      suggestions[id] = [];
      showSnack('הצעות AI לא זמינות כרגע');
    }
    suggestionLoading.remove(id);
    notifyListeners();
  }

  Future<void> acceptSuggestionAsSubtask(
      Map<String, dynamic> task, String text) async {
    final id = task['id'].toString();
    try {
      final r = await api.addSubtask(id, text);
      final sub = r['subtask'] as Map<String, dynamic>?;
      if (sub != null) {
        final raw = task['subtasks'];
        final list = raw is List
            ? List<Map<String, dynamic>>.from(raw)
            : <Map<String, dynamic>>[];
        list.add(sub);
        task['subtasks'] = list;
        notifyListeners();
      }
    } catch (_) {
      showSnack('נכשל בהוספת תת-משימה');
    }
  }

  void dismissSuggestion(Map<String, dynamic> task, int index) {
    final id = task['id'].toString();
    final list = suggestions[id];
    if (list != null && index >= 0 && index < list.length) {
      list.removeAt(index);
      notifyListeners();
    }
  }

  // ── Snackbar ──────────────────────────────────────────────────────────────

  void showSnack(String msg) {
    snack = msg;
    notifyListeners();
    _snackTimer?.cancel();
    _snackTimer = Timer(const Duration(seconds: 3), () {
      snack = null;
      notifyListeners();
    });
  }

  // ── Computed views ────────────────────────────────────────────────────────

  int get openCount => tasks.where((t) => t['done'] != true).length;
  int get doneCount => tasks.where((t) => t['done'] == true).length;

  /// Groups [filteredTasks] into ordered, labelled sections for the single
  /// smart list. [mode] is one of 'time' | 'priority' | 'category' | 'flat'.
  /// Empty sections are omitted (except 'flat', which always returns one).
  List<TaskSection> groupedSections(String mode) {
    final src = filteredTasks;
    switch (mode) {
      case 'priority':
        return _sectionsByOrder(src, const [
          ('high', 'גבוה'),
          ('medium', 'בינוני'),
          ('low', 'נמוך'),
        ], (t) {
          final p = (t['priority'] ?? 'medium').toString();
          return p == 'high' || p == 'low' ? p : 'medium';
        });
      case 'category':
        final order = [
          for (final c in kTaskCategories) (c.id, c.label),
        ];
        return _sectionsByOrder(src, order, (t) {
          final c = (t['category'] ?? '').toString();
          return c.isEmpty ? 'general' : c;
        });
      case 'flat':
        return [(key: 'all', label: 'כל המשימות', tasks: src)];
      case 'time':
      default:
        return _sectionsByTime(src);
    }
  }

  /// Builds sections following a fixed key/label order, dropping empties.
  List<TaskSection> _sectionsByOrder(
    List<Map<String, dynamic>> src,
    List<(String, String)> order,
    String Function(Map<String, dynamic>) keyOf,
  ) {
    final buckets = {for (final o in order) o.$1: <Map<String, dynamic>>[]};
    for (final t in src) {
      (buckets[keyOf(t)] ?? buckets[order.last.$1]!).add(t);
    }
    return [
      for (final o in order)
        if (buckets[o.$1]!.isNotEmpty)
          (key: o.$1, label: o.$2, tasks: buckets[o.$1]!),
    ];
  }

  List<TaskSection> _sectionsByTime(List<Map<String, dynamic>> src) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));
    final overdue = <Map<String, dynamic>>[];
    final todayB = <Map<String, dynamic>>[];
    final week = <Map<String, dynamic>>[];
    final later = <Map<String, dynamic>>[];
    final noDate = <Map<String, dynamic>>[];
    for (final t in src) {
      final due = _parseDate(t['due_date']);
      if (due == null) {
        noDate.add(t);
      } else if (due.isBefore(today)) {
        overdue.add(t);
      } else if (due == today) {
        todayB.add(t);
      } else if (!due.isAfter(weekEnd)) {
        week.add(t);
      } else {
        later.add(t);
      }
    }
    return [
      if (overdue.isNotEmpty) (key: 'overdue', label: 'באיחור', tasks: overdue),
      if (todayB.isNotEmpty) (key: 'today', label: 'היום', tasks: todayB),
      if (week.isNotEmpty) (key: 'week', label: 'השבוע', tasks: week),
      if (later.isNotEmpty) (key: 'later', label: 'מאוחר יותר', tasks: later),
      if (noDate.isNotEmpty)
        (key: 'no_date', label: 'ללא תאריך', tasks: noDate),
    ];
  }

  List<Map<String, dynamic>> get conflicts {
    final raw = dayPlan?['conflicts'];
    if (raw is List) return List<Map<String, dynamic>>.from(raw);
    return const [];
  }

  String? get peakWindow {
    final raw = dayPlan?['peak_window'];
    if (raw is Map) {
      final from = raw['from']?.toString();
      final to = raw['to']?.toString();
      if (from != null && to != null) return '$from – $to';
    }
    if (raw is String && raw.isNotEmpty) return raw;
    return null;
  }

  String get narrative => (dayPlan?['narrative'] ?? '').toString();

  /// Load value 0–100 for the gauge.
  double get loadGauge {
    final raw = dayPlan?['load'];
    double v = 0;
    if (raw is num) {
      v = raw.toDouble();
    } else if (raw is Map && raw['value'] is num) {
      v = (raw['value'] as num).toDouble();
    }
    if (v <= 1.0) v *= 100;
    return v.clamp(0, 100).toDouble();
  }

  Map<String, dynamic>? taskById(String id) {
    for (final t in tasks) {
      if (t['id'].toString() == id) return t;
    }
    return null;
  }

  static DateTime? _parseDate(dynamic iso) {
    if (iso == null) return null;
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      return null;
    }
  }

  static String _dayLabel(int days) {
    if (days == 1) return 'מחר';
    if (days == 7) return 'שבוע הבא';
    return '$days ימים';
  }
}
