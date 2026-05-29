import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Depth/style options for the insight.
const List<String> kInsightDepths = ['קצר', 'עמוק', 'מעשי'];

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
  String insightDepth = kInsightDepths[0];
  List<Map<String, String>> insightThread = []; // [{role, text}]
  bool insightReplyLoading = false;
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
    _loadInsightCache().then((_) => loadJarvisInsight());
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

  String _buildInsightPrompt() {
    final topTasks = tasks
        .where((t) => t['done'] != true)
        .take(5)
        .map((t) => '- ${t['content']} (${t['priority'] ?? 'רגיל'})')
        .join('\n');
    // Use neutral wording ("פריטים") instead of task/reminder keywords, which
    // the server's Hebrew keyword router (/משימ.../, /תזכור.../) would otherwise
    // catch and route to the wrong agent on builds without forced-intent.
    final taskSection =
        topTasks.isNotEmpty ? 'הפריטים הפתוחים של המשתמש כרגע:\n$topTasks\n' : '';
    final topicLine =
        insightTopic != null ? 'התמקד בנושא: $insightTopic.\n' : '';
    final depthLine = insightDepth == 'עמוק'
        ? 'פרט יותר, כ-4-5 משפטים.'
        : insightDepth == 'מעשי'
            ? 'תן צעד אחד קונקרטי לביצוע היום.'
            : 'היה תמציתי, 2-3 משפטים.';
    final name = settings.userName.isNotEmpty ? settings.userName : 'המשתמש';
    return 'אתה ג׳רוויס, עוזר אישי של $name.\n'
        '$taskSection'
        '$topicLine'
        '$depthLine\n'
        'תן תובנה אישית ורלוונטית למה שאתה רואה. '
        'סיים תמיד בשאלה אחת ישירה למשתמש.\n'
        'כתוב בעברית בלבד.';
  }

  Future<void> loadJarvisInsight() async {
    final seq = ++_insightSeq;
    insightLoading = true;
    insightError = null;
    notifyListeners();
    try {
      final r = await api.askJarvis(_buildInsightPrompt(), settings, intent: 'chat');
      if (seq != _insightSeq) return;
      final answer = (r['answer'] as String? ?? '').trim();
      final looksLikeError = (answer.contains('בעיה') && answer.contains('נסה שוב')) ||
          answer.contains('לא הצלחתי') ||
          answer.contains('לא ניתן');
      if (answer.isNotEmpty && !looksLikeError) {
        jarvisInsight = answer;
        insightThread = [{'role': 'assistant', 'text': answer}];
        _saveInsightCache();
      } else {
        // Don't leave the card on a dead error — show a graceful local insight
        // (still ending with a question to keep it interactive).
        final fb = _localFallbackInsight();
        jarvisInsight = fb;
        insightThread = [{'role': 'assistant', 'text': fb}];
        _saveInsightCache();
      }
      insightLoading = false;
    } catch (e) {
      if (seq != _insightSeq) return;
      // Only surface a hard error if we have nothing cached to show.
      if (insightThread.isEmpty) {
        insightError = ApiService.friendlyError(e);
      }
      insightLoading = false;
    }
    notifyListeners();
  }

  static const _fallbackInsights = [
    'התחל מהמטלה הקשה ביותר בבוקר — שם האנרגיה הכי גבוהה. מה הדבר האחד שהכי מפחיד אותך לפתוח היום?',
    'הפסקה קצרה כל 90 דקות משפרת ריכוז יותר מעבודה רצופה. מתי לקחת הפסקה אמיתית בפעם האחרונה?',
    'רשימת "לא לעשות" שומרת על מיקוד לא פחות מרשימת מטלות. מה אפשר להוריד מהצלחת השבוע?',
    'דבר שלוקח פחות משתי דקות — עשה אותו עכשיו במקום לתזמן. מה מחכה אצלך כבר יותר מדי זמן?',
    'סיום היום בתכנון מחר חוסך זמן יקר בבוקר. מה הדבר הראשון שתרצה לעשות מחר?',
  ];

  String _localFallbackInsight() =>
      _fallbackInsights[DateTime.now().millisecondsSinceEpoch % _fallbackInsights.length];

  Future<void> replyToInsight(String userMsg) async {
    if (userMsg.trim().isEmpty) return;
    insightThread = [...insightThread, {'role': 'user', 'text': userMsg.trim()}];
    insightReplyLoading = true;
    notifyListeners();
    try {
      // Build a conversation context for Jarvis
      final history = insightThread
          .map((m) => '${m['role'] == 'assistant' ? 'ג׳רוויס' : 'משתמש'}: ${m['text']}')
          .join('\n');
      final prompt = 'המשך את השיחה הבאה בעברית. ענה בקצרה ובאמפתיה, וסיים בשאלה.\n\n$history\nג׳רוויס:';
      final r = await api.askJarvis(prompt, settings, intent: 'chat');
      final answer = (r['answer'] as String? ?? '').trim();
      if (answer.isNotEmpty) {
        insightThread = [...insightThread, {'role': 'assistant', 'text': answer}];
        _saveInsightCache();
      }
    } catch (_) {/* keep thread as-is */}
    insightReplyLoading = false;
    notifyListeners();
  }

  Future<void> _saveInsightCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('insight_thread_v2', jsonEncode(insightThread));
    } catch (_) {}
  }

  Future<void> _loadInsightCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('insight_thread_v2');
      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final thread = decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => {'role': m['role']?.toString() ?? '', 'text': m['text']?.toString() ?? ''})
            .where((m) => m['role']!.isNotEmpty && m['text']!.isNotEmpty)
            .toList();
        if (thread.isNotEmpty) {
          insightThread = thread;
          jarvisInsight = thread.firstWhere(
            (m) => m['role'] == 'assistant',
            orElse: () => {'role': 'assistant', 'text': ''},
          )['text']!;
          // Show cached content immediately; loading stays true until fetch completes.
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  void setInsightTopic(String? topic) {
    insightTopic = topic;
    insightThread = [];
    loadJarvisInsight();
  }

  void setInsightDepth(String depth) {
    insightDepth = depth;
    insightThread = [];
    loadJarvisInsight();
  }

  Future<void> insightToTask() async {
    final firstAssistant = insightThread
        .where((m) => m['role'] == 'assistant')
        .map((m) => m['text'] ?? '')
        .firstWhere((t) => t.isNotEmpty, orElse: () => jarvisInsight);
    if (firstAssistant.trim().isEmpty) return;
    await addTask(firstAssistant.trim());
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
    // Avoid Hebrew task/reminder keywords ("משימ", "תזכור") which trigger
    // the keyword router on old server builds before forced-intent was deployed.
    return 'הקשר: למשתמש $open פריטים פתוחים ($urgent דחופים) ו-$rem אירועים קרובים. '
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
