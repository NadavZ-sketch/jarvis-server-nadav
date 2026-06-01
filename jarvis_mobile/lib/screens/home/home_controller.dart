import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';

/// A contextual "role" the proactive Jarvis card takes on depending on the time
/// of day. The card auto-picks one (see [HomeController._autoInsightMode]) but
/// the user can override it from the chip row.
class InsightMode {
  final String key; // internal id used to branch the prompt
  final String label; // chip text
  final String emoji; // header icon
  final String subtitle; // header sub-line
  const InsightMode(this.key, this.label, this.emoji, this.subtitle);
}

/// Order matters: the chip row renders these left-to-right and the auto-picker
/// maps time windows onto them by index.
const List<InsightMode> kInsightModes = [
  InsightMode('briefing', 'תדריך בוקר', '☀️', 'מה הכי חשוב היום'),
  InsightMode('checkin', 'צ׳ק-אין', '⚡', 'איפה אתה עומד עכשיו'),
  InsightMode('recap', 'סיכום ערב', '🌙', 'מה הספקת ומה למחר'),
  InsightMode('winddown', 'רגיעה', '🌌', 'לסגור את היום בנחת'),
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
  // Proactive mode shown by the card. Auto-derived from the clock unless the
  // user taps a chip, in which case [_insightModeManual] pins their choice.
  InsightMode insightMode = _autoInsightMode();
  bool _insightModeManual = false;
  List<Map<String, String>> insightThread = []; // [{role, text}]
  bool insightReplyLoading = false;
  int _insightSeq = 0; // stale-response guard

  /// Picks the mode that fits the current local hour.
  static InsightMode _autoInsightMode() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 11) return kInsightModes[0]; // morning briefing
    if (h >= 11 && h < 17) return kInsightModes[1]; // midday check-in
    if (h >= 17 && h < 22) return kInsightModes[2]; // evening recap
    return kInsightModes[3]; // late-night wind-down
  }

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
    // No periodic timer: the insight + day-plan are LLM-backed and expensive.
    // Data refreshes on initial load, pull-to-refresh, and app resume instead.
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

  /// App-resume refresh: updates core + cheap/cached secondary data quietly,
  /// without flipping the screen back into a loading state. Deliberately skips
  /// the day-plan LLM (it re-runs on the full load and after task mutations); the
  /// insight is served from the server cache unless it has gone stale.
  Future<void> _silentRefresh() async {
    try {
      final results = await Future.wait([api.getTasks(), api.getReminders()]);
      tasks = results[0];
      reminders = results[1];
      notifyListeners();
    } catch (_) {/* keep showing the last good data */}
    _loadDashboardContext();
    _loadStats();
    loadJarvisInsight(); // fresh:false → returns the server-cached insight cheaply
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

  /// Builds a proactive, time-of-day-aware prompt for the insight card. Feeds
  /// Jarvis the real current state (open/urgent tasks, today's reminders, day
  /// load) so the message is grounded rather than generic.
  String _buildInsightPrompt() {
    final name = settings.userName.isNotEmpty ? settings.userName : 'המשתמש';

    final topTasks = tasks
        .where((t) => t['done'] != true)
        .take(5)
        .map((t) => '- ${t['content']} (${t['priority'] ?? 'רגיל'})')
        .join('\n');

    final todayRems = remindersForOffset(0).take(5).map((r) {
      final iso = r['scheduled_time'] as String?;
      var time = '';
      if (iso != null) {
        try {
          final dt = DateTime.parse(iso).toLocal();
          final hh = dt.hour.toString().padLeft(2, '0');
          final mm = dt.minute.toString().padLeft(2, '0');
          time = '$hh:$mm ';
        } catch (_) {}
      }
      return '- $time${r['text'] ?? ''}';
    }).join('\n');

    final ctx = StringBuffer();
    ctx.writeln('הקשר נוכחי של $name:');
    ctx.writeln('• משימות פתוחות: $openTasks (מתוכן $highPriorityCount דחופות).');
    if (topTasks.isNotEmpty) ctx.writeln('המשימות:\n$topTasks');
    if (todayRems.isNotEmpty) ctx.writeln('תזכורות להיום:\n$todayRems');
    final load = (dayPlan?['load'] as Map<String, dynamic>?)?['status']?.toString();
    if (load != null && load.isNotEmpty) ctx.writeln('• עומס היום: $load.');

    String modeLine;
    switch (insightMode.key) {
      case 'briefing':
        modeLine =
            'זה תדריך בוקר. פתח ב"בוקר טוב $name", ואז ב-2-3 משפטים הצג את 1-2 הדברים '
            'הכי חשובים להיום ומאיפה הכי כדאי להתחיל.';
        break;
      case 'checkin':
        modeLine =
            'זה צ׳ק-אין באמצע היום. ב-2-3 משפטים: איפה $name עומד, מה עוד נשאר, '
            'ודחיפה קטנה ומעודדת להמשיך.';
        break;
      case 'recap':
        modeLine =
            'זה סיכום ערב. ב-2-3 משפטים ובטון מרגיע: מה כדאי לסגור עוד היום, '
            'ומה שווה להכין כבר עכשיו למחר.';
        break;
      case 'winddown':
        modeLine =
            'זה רגע רגיעה בלילה. משפט-שניים מרגיעים בלי שום לחץ, '
            'ותזכורת עדינה לדבר הראשון שמחכה מחר.';
        break;
      default:
        modeLine = 'תן תובנה אישית קצרה ורלוונטית למצב.';
    }

    return 'אתה ג׳רוויס, עוזר אישי יזום של $name.\n'
        '${ctx.toString()}\n'
        '$modeLine\n'
        'דבר ישירות אל $name בגוף שני, חם ואנושי. אל תקריא את המספרים יבש — '
        'תרגם אותם לתובנה. סיים תמיד בשאלה אחת ישירה שמזמינה תגובה.\n'
        'כתוב בעברית בלבד.';
  }

  /// Loads the proactive insight from the server-cached `/insight-card` endpoint.
  /// Pass [fresh] to force a brand-new LLM generation (manual refresh / new
  /// suggestion); otherwise the server serves a cached insight for free.
  Future<void> loadJarvisInsight({bool fresh = false}) async {
    // Keep the role in sync with the clock unless the user pinned one.
    if (!_insightModeManual) insightMode = _autoInsightMode();
    final seq = ++_insightSeq;
    insightLoading = true;
    insightError = null;
    notifyListeners();
    try {
      final r = await api.getInsightCard(_buildInsightPrompt(),
          mode: insightMode.key, fresh: fresh);
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
        insightError = 'לא ניתן לטעון תובנה כרגע';
      }
      insightLoading = false;
    } catch (e) {
      if (seq != _insightSeq) return;
      insightError = ApiService.friendlyError(e);
      insightLoading = false;
    }
    notifyListeners();
  }

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

  /// Reports explicit feedback on the current insight to the server's feedback
  /// loop. Gated on telemetry consent; fire-and-forget.
  void recordInsightFeedback(String signal) {
    if (!settings.telemetryConsent) return;
    final text = jarvisInsight.trim();
    if (text.isEmpty) return;
    api.sendFeedback(
      chatId: 'insight-${insightMode.key}',
      messageText: text,
      signal: signal,
      source: 'insight_card',
    );
  }

  void setInsightMode(InsightMode mode) {
    if (mode.key == insightMode.key && _insightModeManual) return;
    insightMode = mode;
    _insightModeManual = true;
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
