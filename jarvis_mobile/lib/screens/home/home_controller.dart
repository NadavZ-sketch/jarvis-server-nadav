import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';

/// Owns every piece of state the home screen renders and exposes optimistic
/// mutations. Cards listen to this via [AnimatedBuilder]/[ListenableBuilder] so
/// the screen itself stays a thin shell. Auto-refreshes on a timer and when the
/// app returns to the foreground, giving the home screen live data.
class HomeController extends ChangeNotifier with WidgetsBindingObserver {
  HomeController({required this.settings, required this.onNavigateToChat})
      : api = ApiService(settings);

  final AppSettings settings;
  // Switches to the chat tab; pass [command] to pre-fill/send a message.
  final void Function({String? command})? onNavigateToChat;
  final ApiService api;

  // ── Core data ──
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> reminders = [];
  String todayMessage = '';
  bool loading = true;
  String? error;

  // ── Secondary data (each loads independently; a failure never breaks core) ──
  Map<String, dynamic>? dashboardContext;
  bool dashboardLoading = true;
  // Gates the resume-refresh of the (network-backed) dashboard so a quick
  // app switch doesn't re-hit the server on every foreground.
  DateTime? _lastDashboardAt;

  // ── Transient UI state ──
  final Set<String> postponed = {};
  final Set<String> markedImportant = {};
  final Set<String> completing = {};
  int selectedDayOffset = 0;
  String? snack;
  Timer? _snackTimer;

  // ───────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────────────────

  void start() {
    WidgetsBinding.instance.addObserver(this);
    load();
    // No periodic timer: the Focus card is computed locally and the dashboard
    // is gated. Data refreshes on initial load, pull-to-refresh, and app resume.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snackTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _silentRefresh();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Loading
  // ───────────────────────────────────────────────────────────────────────────

  /// Full load: blocks the initial render on the fast core endpoints, then
  /// fans out to the slower/optional sources without blocking.
  Future<void> load() async {
    try {
      final results = await Future.wait([
        api.getTasks(),
        api.getReminders(),
        api.getTodayMessage().catchError((_) async => <String, dynamic>{}),
      ]);
      tasks = results[0] as List<Map<String, dynamic>>;
      reminders = results[1] as List<Map<String, dynamic>>;
      final msg = results[2] as Map<String, dynamic>;
      todayMessage = (msg['message'] ?? msg['text'] ?? '') as String;
      loading = false;
      error = null;
      notifyListeners();
      _loadSecondary();
    } catch (e) {
      error = ApiService.friendlyError(e);
      loading = false;
      notifyListeners();
    }
  }

  /// Pull-to-refresh: re-runs the full load surfacing errors.
  Future<void> refresh() => load();

  /// App-resume refresh: updates core data quietly, without flipping the screen
  /// back into a loading state. The Focus card is computed locally from this
  /// data, so there are no LLM calls. The dashboard (weather/news/hero) is
  /// network-backed, so it's refreshed only when stale to avoid per-resume hits.
  Future<void> _silentRefresh() async {
    try {
      final results = await Future.wait([api.getTasks(), api.getReminders()]);
      tasks = results[0];
      reminders = results[1];
      notifyListeners();
    } catch (_) {/* keep showing the last good data */}
    if (_dashboardRefreshDue) _loadDashboardContext();
  }

  /// True when the dashboard context is old enough to justify another fetch.
  bool get _dashboardRefreshDue {
    final last = _lastDashboardAt;
    return last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 15);
  }

  void _loadSecondary() {
    _loadDashboardContext();
  }

  Future<void> _loadDashboardContext() async {
    dashboardLoading = true;
    notifyListeners();
    try {
      dashboardContext = await api.getDashboardContext();
      _lastDashboardAt = DateTime.now();
    } catch (_) {
      dashboardContext = null;
    }
    dashboardLoading = false;
    notifyListeners();
  }


  // ───────────────────────────────────────────────────────────────────────────
  // Mutations (optimistic)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> completeTask(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    if (completing.contains(id)) return;
    completing.add(id);
    notifyListeners();
    try {
      await api.updateTask(id, done: true);
      await Future.delayed(const Duration(milliseconds: 350));
      tasks.removeWhere((t) => t['id'].toString() == id);
      completing.remove(id);
      showSnack('משימה הושלמה ✓');
      notifyListeners();
    } catch (e) {
      completing.remove(id);
      showSnack(ApiService.friendlyError(e));
      notifyListeners();
    }
  }

  Future<void> postponeTask(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    postponed.add(id);
    notifyListeners();
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    try {
      await api.updateTask(id, dueDate: tomorrow.toUtc().toIso8601String());
      showSnack('המשימה נדחתה למחר ✓');
    } catch (e) {
      postponed.remove(id);
      showSnack(ApiService.friendlyError(e));
    }
    notifyListeners();
  }

  void markImportant(Map<String, dynamic> task) {
    markedImportant.add(task['id'].toString());
    showSnack('סומנה כחשובה ✓');
    notifyListeners();
  }

  Future<void> addTask(String content) async {
    try {
      await api.addTask(content, priority: 'medium');
      showSnack('משימה נוספה ✓');
      await _silentRefresh();
    } catch (e) {
      showSnack('שגיאה: ${ApiService.friendlyError(e)}');
    }
  }

  Future<void> addReminder(String text, DateTime when) async {
    try {
      await api.addReminder(text, when.toUtc().toIso8601String());
      showSnack('תזכורת נוספה ✓');
      await _silentRefresh();
    } catch (e) {
      showSnack('שגיאה: ${ApiService.friendlyError(e)}');
    }
  }

  void selectDay(int offset) {
    selectedDayOffset = offset;
    notifyListeners();
  }

  void showSnack(String msg) {
    snack = msg;
    notifyListeners();
    _snackTimer?.cancel();
    _snackTimer = Timer(const Duration(seconds: 3), () {
      snack = null;
      notifyListeners();
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Computed views
  // ───────────────────────────────────────────────────────────────────────────

  int get doneTasks => tasks.where((t) => t['done'] == true).length;
  int get totalTasks => tasks.length;
  int get openTasks => totalTasks - doneTasks;
  int get highPriorityCount => tasks
      .where((t) =>
          t['done'] != true &&
          (t['priority'] ?? '').toString().toLowerCase() == 'high')
      .length;

  /// Day-load "units": everything still on the plate for today. Used to drive the
  /// load gauge locally instead of an LLM `/day-plan` round-trip.
  int get _loadUnits => openTasks + remindersForOffset(0).length;

  /// Load gauge status, derived locally. High-priority pressure escalates a level.
  String dayLoadStatus() {
    final u = _loadUnits;
    String status;
    if (u == 0) {
      status = 'empty';
    } else if (u <= 2) {
      status = 'light';
    } else if (u <= 5) {
      status = 'moderate';
    } else if (u <= 8) {
      status = 'heavy';
    } else {
      status = 'overloaded';
    }
    // Several urgent items make even a short list feel heavy.
    if (highPriorityCount >= 3 && (status == 'light' || status == 'moderate')) {
      status = status == 'light' ? 'moderate' : 'heavy';
    }
    return status;
  }

  /// 0..1 fill for the load gauge bar.
  double dayLoadRatio() => (_loadUnits / 10).clamp(0.0, 1.0);

  /// The single most pressing open task (high priority first), or null.
  Map<String, dynamic>? get topOpenTask {
    final open = tasks.where((t) => t['done'] != true).toList();
    if (open.isEmpty) return null;
    open.sort((a, b) {
      int rank(Map t) =>
          (t['priority'] ?? '').toString().toLowerCase() == 'high' ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    return open.first;
  }

  /// The soonest reminder that hasn't passed yet (today or later), or null.
  Map<String, dynamic>? get nextUpcomingReminder {
    final now = DateTime.now();
    final upcoming = reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null) return false;
      try {
        return DateTime.parse(iso).toLocal().isAfter(now);
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['scheduled_time'] as String? ?? '')
          .compareTo(b['scheduled_time'] as String? ?? ''));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  /// The single thing to focus on right now. An imminent reminder (within 2h)
  /// outranks tasks; otherwise the most pressing open task; otherwise the next
  /// reminder of any time. Returns (kind: 'task'|'reminder', data) or null when
  /// there's nothing pending. Computed locally — no server/LLM.
  ({String kind, Map<String, dynamic> data})? get focusItem {
    final rem = nextUpcomingReminder;
    if (rem != null) {
      final iso = rem['scheduled_time'] as String?;
      try {
        final dt = DateTime.parse(iso!).toLocal();
        if (dt.difference(DateTime.now()) <= const Duration(hours: 2)) {
          return (kind: 'reminder', data: rem);
        }
      } catch (_) {}
    }
    final task = topOpenTask;
    if (task != null) return (kind: 'task', data: task);
    if (rem != null) return (kind: 'reminder', data: rem);
    return null;
  }

  List<Map<String, dynamic>> remindersForOffset(int offset) {
    final target = DateTime.now().add(Duration(days: offset));
    return reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null) return false;
      try {
        final dt = DateTime.parse(iso).toLocal();
        return dt.year == target.year &&
            dt.month == target.month &&
            dt.day == target.day;
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['scheduled_time'] as String? ?? '')
          .compareTo(b['scheduled_time'] as String? ?? ''));
  }

  int reminderCountForDay(DateTime day) => reminders.where((r) {
        final iso = r['scheduled_time'] as String?;
        if (iso == null) return false;
        try {
          final dt = DateTime.parse(iso).toLocal();
          return dt.year == day.year &&
              dt.month == day.month &&
              dt.day == day.day;
        } catch (_) {
          return false;
        }
      }).length;
}
