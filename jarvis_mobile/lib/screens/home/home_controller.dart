import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';

/// Topics the user can steer the Jarvis insight toward.
const List<String> kInsightTopics = [
  'מיקוד',
  'אנרגיה',
  'הרגלים',
  'החלטות',
  'איזון',
  'השראה',
];

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

  static const _autoRefreshInterval = Duration(seconds: 60);
  Timer? _refreshTimer;

  // ── Core data ──
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> reminders = [];
  String todayMessage = '';
  bool loading = true;
  String? error;

  // ── Secondary data (each loads independently; a failure never breaks core) ──
  Map<String, dynamic>? dashboardContext;
  bool dashboardLoading = true;

  Map<String, dynamic>? dayPlan;
  bool dayPlanLoading = true;

  Map<String, dynamic>? stats;
  bool statsLoading = true;

  String jarvisInsight = '';
  bool insightLoading = true;
  String? insightError;
  String? insightTopic; // null = general; otherwise one of kInsightTopics
  int _insightSeq = 0; // stale-response guard

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

  /// Timer / app-resume refresh: updates core + secondary data quietly without
  /// flipping the screen back into a loading state.
  Future<void> _silentRefresh() async {
    try {
      final results = await Future.wait([api.getTasks(), api.getReminders()]);
      tasks = results[0];
      reminders = results[1];
      notifyListeners();
    } catch (_) {/* keep showing the last good data */}
    _loadSecondary();
  }

  void _loadSecondary() {
    _loadDashboardContext();
    _loadDayPlan();
    _loadStats();
    loadJarvisInsight();
  }

  Future<void> _loadDashboardContext() async {
    dashboardLoading = true;
    notifyListeners();
    try {
      dashboardContext = await api.getDashboardContext();
    } catch (_) {
      dashboardContext = null;
    }
    dashboardLoading = false;
    notifyListeners();
  }

  Future<void> _loadDayPlan() async {
    dayPlanLoading = true;
    notifyListeners();
    try {
      dayPlan = await api.getDayPlan();
    } catch (_) {
      dayPlan = null;
    }
    dayPlanLoading = false;
    notifyListeners();
  }

  Future<void> _loadStats() async {
    statsLoading = true;
    notifyListeners();
    try {
      stats = await api.getStats();
    } catch (_) {
      stats = null;
    }
    statsLoading = false;
    notifyListeners();
  }

  static const _insightPrompts = [
    'תן לי תובנה קצרה ומפתיעה על פרודוקטיביות שאנשים בדרך כלל לא יודעים, בעברית, 2 שורות',
    'שתף אותי בטיפ חכם אחד לניהול אנרגיה נפשית לאורך יום עבודה, בעברית, 2 שורות',
    'תן לי משפט השראה מקורי שקשור להשגת מטרות, בעברית, 2 שורות',
    'מה הדבר הכי חשוב שאפשר לעשות כדי לשפר מיקוד? תובנה קצרה בעברית, 2 שורות',
    'שתף אותי בחכמה קצרה על קבלת החלטות טובות, בעברית, 2 שורות',
    'תן לי טיפ פרקטי לאיך להתחיל את היום בצורה חזקה, בעברית, 2 שורות',
    'מה הסוד של אנשים שמצליחים לסיים את כל המשימות שלהם? תובנה בעברית, 2 שורות',
    'שתף אותי במחשבה מעניינת על איזון בין עבודה וחיים, בעברית, 2 שורות',
  ];

  Future<void> loadJarvisInsight() async {
    final seq = ++_insightSeq;
    insightLoading = true;
    insightError = null;
    notifyListeners();
    try {
      final String base;
      if (insightTopic != null) {
        base = 'תן לי תובנה קצרה ומעשית בנושא "${insightTopic!}", בעברית, 2 שורות';
      } else {
        base = _insightPrompts[Random().nextInt(_insightPrompts.length)];
      }
      final prompt = '$base\n$_dayContextLine'.trim();
      // Force the 'chat' intent so the open-ended question is answered by the
      // conversational agent, never re-routed to the analytics insight agent
      // (which can return empty for users with little usage history).
      final r = await api.askJarvis(prompt, settings, intent: 'chat');
      if (seq != _insightSeq) return; // superseded by a newer request
      final answer = (r['answer'] as String? ?? '').trim();
      jarvisInsight = answer.isNotEmpty ? answer : _localFallbackInsight();
      insightLoading = false;
    } catch (e) {
      if (seq != _insightSeq) return;
      insightError = ApiService.friendlyError(e);
      insightLoading = false;
    }
    notifyListeners();
  }

  static const _fallbackInsights = [
    'התחל מהמשימה הקשה ביותר בבוקר — שם האנרגיה שלך הכי גבוהה.',
    'הפסקה קצרה כל 90 דקות משפרת ריכוז יותר מאשר עבודה רצופה.',
    'רשימת "לא לעשות" יעילה לא פחות מרשימת מטלות — היא שומרת על מיקוד.',
    'משימה שלוקחת פחות משתי דקות — עשה אותה עכשיו במקום לתזמן.',
    'סיום היום בתכנון מחר חוסך זמן יקר בבוקר.',
  ];

  String _localFallbackInsight() =>
      _fallbackInsights[Random().nextInt(_fallbackInsights.length)];

  void setInsightTopic(String? topic) {
    insightTopic = topic;
    loadJarvisInsight();
  }

  Future<void> insightToTask() async {
    final text = jarvisInsight.trim();
    if (text.isEmpty) return;
    await addTask(text);
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
      _loadStats();
      _loadDayPlan();
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

  String get _dayContextLine {
    final open = openTasks;
    final urgent = highPriorityCount;
    final rem = reminders.length;
    if (open == 0 && rem == 0) return '';
    return 'הקשר: למשתמש $open משימות פתוחות ($urgent דחופות) ו-$rem תזכורות. '
        'התאם את התובנה למצב הזה בעדינות, בלי לחזור על המספרים.';
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
