import 'dart:math' show Random;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _priorityColor(String? priority) {
  switch ((priority ?? '').toLowerCase()) {
    case 'high':
      return const Color(0xFFEF4444);
    case 'medium':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF475569);
  }
}

String _priorityLabel(String? priority) {
  switch ((priority ?? '').toLowerCase()) {
    case 'high':
      return 'גבוה';
    case 'medium':
      return 'בינוני';
    default:
      return 'רגיל';
  }
}

String _formatRemTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) return 'פג תוקף';
    if (diff.inHours < 1) return 'בעוד ${diff.inMinutes} דק׳';
    if (diff.inHours < 24) return 'בעוד ${diff.inHours} שעות';
    return 'בעוד ${diff.inDays} ימים';
  } catch (_) {
    return '';
  }
}

String _timeOfDay(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '';
  }
}

String _dynamicGreeting(String userName) {
  final hour = DateTime.now().hour;
  final name = userName.isEmpty ? 'Jarvis' : userName;
  if (hour < 5) return 'לילה טוב, $name';
  if (hour < 12) return 'בוקר טוב, $name';
  if (hour < 17) return 'צהריים טובים, $name';
  if (hour < 21) return 'ערב טוב, $name';
  return 'לילה טוב, $name';
}

String _greetingEmoji() {
  final hour = DateTime.now().hour;
  if (hour < 5) return '✨';
  if (hour < 12) return '☀️';
  if (hour < 17) return '🌤';
  if (hour < 21) return '🌙';
  return '✨';
}

String _buildDayRecommendation(
    List<Map<String, dynamic>> tasks, String userName) {
  final open = tasks.where((t) => t['done'] != true).toList();
  final highPriority = open
      .where((t) => (t['priority'] ?? '').toString().toLowerCase() == 'high')
      .length;
  final total = open.length;

  if (total == 0) return 'כל המשימות הושלמו! היום נקי ✅ קחו הפסקה.';
  if (highPriority > 2) {
    return 'יש $highPriority משימות בעדיפות גבוהה. '
        'Jarvis ממליץ להתחיל בהן לפני הצהריים.';
  }
  if (total > 6) {
    return 'יש לך $total משימות פתוחות. '
        'Jarvis ממליץ לדחות 2-3 למחר ולהתמקד ב-4 עיקריות.';
  }
  return 'יש לך $total משימות פתוחות. התחל מהחשובות ביותר.';
}

const _hebrewDays = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];
const _hebrewMonths = [
  'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
  'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר',
];

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class SmartProductivityPreviewScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback? onNavigateToChat;

  const SmartProductivityPreviewScreen({
    super.key,
    required this.settings,
    this.onNavigateToChat,
  });

  @override
  State<SmartProductivityPreviewScreen> createState() =>
      _SmartProductivityPreviewScreenState();
}

class _SmartProductivityPreviewScreenState
    extends State<SmartProductivityPreviewScreen> {
  late final ApiService _api;

  // Core data
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _reminders = [];
  String _todayMessage = '';
  bool _loading = true;
  String? _error;

  // Jarvis insight
  String _jarvisInsight = '';
  bool _jarvisInsightLoading = true;
  String? _jarvisInsightError;

  // UI state
  Set<String> _postponed = {};
  Set<String> _markedImportant = {};
  Set<String> _completing = {};
  String? _snackMessage;
  int _selectedDayOffset = 0;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final tasksFuture = _api.getTasks();
      final remindersFuture = _api.getReminders();
      final msgFuture = _api.getTodayMessage().catchError(
          (_) async => <String, dynamic>{});
      final tasks = await tasksFuture;
      final reminders = await remindersFuture;
      final msg = await msgFuture;
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _reminders = reminders;
          _todayMessage = (msg['message'] ?? msg['text'] ?? '') as String;
          _loading = false;
        });
        _loadJarvisInsight();
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

  Future<void> _loadJarvisInsight() async {
    setState(() { _jarvisInsightLoading = true; _jarvisInsightError = null; });
    try {
      final basePrompt = _insightPrompts[Random().nextInt(_insightPrompts.length)];
      final prompt = '$basePrompt\n$_dayContextLine'.trim();
      final r = await _api.askJarvis(prompt, widget.settings);
      if (mounted) setState(() {
        _jarvisInsight = r['answer'] as String? ?? '';
        _jarvisInsightLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _jarvisInsightError = ApiService.friendlyError(e);
        _jarvisInsightLoading = false;
      });
    }
  }

  Future<void> _postponeTask(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    setState(() => _postponed.add(id));
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    try {
      await _api.updateTask(id, dueDate: tomorrow.toUtc().toIso8601String());
      _showSnack('המשימה נדחתה למחר ✓');
    } catch (e) {
      setState(() => _postponed.remove(id));
      _showSnack(ApiService.friendlyError(e));
    }
  }

  void _markImportant(Map<String, dynamic> task) {
    setState(() => _markedImportant.add(task['id'].toString()));
    _showSnack('סומנה כחשובה ✓');
  }

  Future<void> _completeTask(Map<String, dynamic> task) async {
    final id = task['id'].toString();
    if (_completing.contains(id)) return;
    setState(() => _completing.add(id));
    try {
      await _api.updateTask(id, done: true);
      await Future.delayed(const Duration(milliseconds: 600));
      _loadData();
      _showSnack('משימה הושלמה ✓');
    } catch (e) {
      setState(() => _completing.remove(id));
      _showSnack(ApiService.friendlyError(e));
    }
  }

  void _showSnack(String msg) {
    setState(() => _snackMessage = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _snackMessage = null);
    });
  }

  void _showAddTaskDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0B1422),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'משימה חדשה',
            style: TextStyle(
              color: JC.textPrimary,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
            decoration: InputDecoration(
              hintText: 'תאר את המשימה...',
              hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.blue500),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('ביטול',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(context);
                try {
                  await _api.addTask(text, priority: 'medium');
                  _loadData();
                  _showSnack('משימה נוספה ✓');
                } catch (e) {
                  _showSnack('שגיאה: ${ApiService.friendlyError(e)}');
                }
              },
              child: const Text('הוסף',
                  style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddReminderDialog() {
    final textController = TextEditingController();
    DateTime reminderTime =
        DateTime.now().add(const Duration(hours: 1)).copyWith(second: 0, microsecond: 0);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0B1422),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'תזכורת חדשה',
              style: TextStyle(
                  color: JC.textPrimary,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textController,
                  autofocus: true,
                  style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                  decoration: InputDecoration(
                    hintText: 'תאר את התזכורת...',
                    hintStyle:
                        TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: JC.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: JC.blue500),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: reminderTime,
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null || !ctx.mounted) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(reminderTime),
                    );
                    if (time == null) return;
                    setDState(() {
                      reminderTime = DateTime(date.year, date.month, date.day,
                          time.hour, time.minute);
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1929),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: JC.border),
                    ),
                    child: Row(children: [
                      Icon(Icons.schedule_rounded,
                          color: JC.blue400, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${reminderTime.day}/${reminderTime.month}  '
                        '${reminderTime.hour.toString().padLeft(2, '0')}:'
                        '${reminderTime.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            color: JC.textSecondary, fontFamily: 'Heebo'),
                      ),
                      const Spacer(),
                      Text('שנה',
                          style: TextStyle(
                              color: JC.blue400,
                              fontSize: 12,
                              fontFamily: 'Heebo')),
                    ]),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ביטול',
                    style:
                        TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final text = textController.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    await _api.addReminder(
                        text, reminderTime.toUtc().toIso8601String());
                    _loadData();
                    _showSnack('תזכורת נוספה ✓');
                  } catch (e) {
                    _showSnack('שגיאה: ${ApiService.friendlyError(e)}');
                  }
                },
                child: const Text('הוסף',
                    style: TextStyle(
                        fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Computed Getters ────────────────────────────────────────────────────────

  // One-line snapshot of the user's day, injected into the insight prompt so the
  // tip is grounded in their actual load instead of being generic.
  String get _dayContextLine {
    final open = _tasks.where((t) => t['done'] != true).length;
    final urgent = _highPriorityCount;
    final reminders = _reminders.length;
    if (open == 0 && reminders == 0) return '';
    return 'הקשר: למשתמש $open משימות פתוחות ($urgent דחופות) ו-$reminders תזכורות. '
        'התאם את התובנה למצב הזה בעדינות, בלי לחזור על המספרים.';
  }

  int get _doneTasks => _tasks.where((t) => t['done'] == true).length;
  int get _totalTasks => _tasks.length;
  int get _highPriorityCount => _tasks.where((t) => (t['priority'] ?? '').toString().toLowerCase() == 'high').length;
  int get _medPriorityCount => _tasks.where((t) => (t['priority'] ?? '').toString().toLowerCase() == 'medium').length;
  int get _lowPriorityCount => _tasks.where((t) => !['high', 'medium'].contains((t['priority'] ?? '').toString().toLowerCase())).length;

  List<Map<String, dynamic>> get _todayReminders {
    final target = DateTime.now().add(Duration(days: _selectedDayOffset));
    return _reminders.where((r) {
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
      ..sort((a, b) {
        final ta = a['scheduled_time'] as String? ?? '';
        final tb = b['scheduled_time'] as String? ?? '';
        return ta.compareTo(tb);
      });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        body: SafeArea(
          top: true,
          child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _loading
                      ? Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: JC.blue400))
                      : _error != null
                          ? _ErrorView(_error!, _loadData)
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surface,
                              onRefresh: _loadData,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                children: [
                                  _ScrollHeader('מנהל היום החכם', () { setState(() { _loading = true; _error = null; }); _loadData(); }),
                                  _GreetingCard(),
                                  const SizedBox(height: 16),
                                  _QuickActionsRow(),
                                  const SizedBox(height: 16),
                                  _JarvisAdvisorCard(),
                                  const SizedBox(height: 16),
                                  _TasksCard(),
                                  const SizedBox(height: 16),
                                  _CalendarStrip(),
                                  const SizedBox(height: 16),
                                  _RemindersCard(),
                                  SizedBox(height: bottomPad + 8),
                                ],
                              ),
                            ),
                ),
              ],
            ),
            if (_snackMessage != null)
              Positioned(
                bottom: 60,
                left: 16,
                right: 16,
                child: _SnackOverlay(_snackMessage!),
              ),
          ],
        ),
        ),
      ),
    );
  }

  // ── Scroll Header ─────────────────────────────────────────────────────────

  Widget _ScrollHeader(String screenTitle, VoidCallback onRefresh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Scaffold.of(context).openEndDrawer(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1422),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )],
              ),
              child: Icon(Icons.menu_rounded,
                  color: JC.textSecondary, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1422),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )],
              ),
              child: Icon(Icons.refresh_rounded,
                  color: JC.textSecondary, size: 18),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'שלום, ${widget.settings.userName}',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Heebo',
                ),
              ),
              Text(
                screenTitle,
                style: TextStyle(
                  color: JC.textMuted,
                  fontSize: 12,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Greeting Card ──────────────────────────────────────────────────────────

  Widget _GreetingCard() {
    final greeting = _dynamicGreeting(widget.settings.userName);
    final emoji = _greetingEmoji();
    final now = DateTime.now();
    final dateStr =
        'יום ${_hebrewDays[now.weekday % 7]}, ${now.day} ב${_hebrewMonths[now.month - 1]}';

    final openCount = _totalTasks - _doneTasks;
    final urgentCount = _highPriorityCount;
    final todayRemCount = _todayReminders.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A2E4A), JC.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Heebo',
                      ),
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 12,
                        fontFamily: 'Heebo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Open tasks chip (always shown)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: JC.blue400.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: JC.blue400.withOpacity(0.35), width: 0.8),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(color: JC.blue400, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$openCount משימות פתוחות',
                    style: TextStyle(
                      color: JC.blue400,
                      fontSize: 11,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
              // Urgent chip (only if > 0)
              if (urgentCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.35), width: 0.8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$urgentCount דחופות',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              // Today reminders chip (only if > 0)
              if (todayRemCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35), width: 0.8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '$todayRemCount תזכורות היום',
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _QuickActionsRow() {
    final actions = [
      {
        'icon': Icons.build_circle_outlined,
        'label': 'בנה את היום',
        'color': const Color(0xFF3B82F6),
        'onTap': () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xFF0B1422),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _BuildDayBottomSheet(
            api: _api,
            settings: widget.settings,
          ),
        ),
      },
      {
        'icon': Icons.add_circle_outline_rounded,
        'label': 'משימה חדשה',
        'color': const Color(0xFFA5B4FC),
        'onTap': () => _showAddTaskDialog(),
      },
      {
        'icon': Icons.alarm_add_rounded,
        'label': 'תזכורת חדשה',
        'color': const Color(0xFF22C55E),
        'onTap': () => _showAddReminderDialog(),
      },
      {
        'icon': Icons.chat_bubble_outline_rounded,
        'label': 'שיחה עם ג׳רוויס',
        'color': const Color(0xFFF59E0B),
        'onTap': () => widget.onNavigateToChat?.call(),
      },
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final a = actions[i];
          return _QuickActionChip(
            icon: a['icon'] as IconData,
            label: a['label'] as String,
            color: a['color'] as Color,
            onTap: a['onTap'] as VoidCallback,
          );
        },
      ),
    );
  }

  // ── Jarvis Advisor Card ────────────────────────────────────────────────────

  Widget _JarvisAdvisorCard() {
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text('✨', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'תובנה מג׳רוויס',
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                        ),
                      ),
                      Text(
                        'טיפ יומי לפרודוקטיביות',
                        style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo',
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _loadJarvisInsight,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        color: Color(0xFF6366F1), size: 14),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _jarvisInsightLoading
                ? const _CardSkeleton(lines: 2)
                : _jarvisInsightError != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Color(0xFFEF4444), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_jarvisInsightError!,
                                  style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 12,
                                      fontFamily: 'Heebo')),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _loadJarvisInsight,
                            child: Text('נסה שוב',
                                style: TextStyle(
                                    color: JC.blue400, fontFamily: 'Heebo')),
                          ),
                        ],
                      )
                    : Text(
                        _jarvisInsight.isNotEmpty
                            ? _jarvisInsight
                            : 'לא ניתן לטעון תובנה כרגע',
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 13.5,
                          height: 1.55,
                          fontFamily: 'Heebo',
                          fontStyle: FontStyle.italic,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Tasks Card (unified) ──────────────────────────────────────────────────

  Widget _TasksCard() {
    final done = _doneTasks;
    final total = _totalTasks;
    final progress = total == 0 ? 0.0 : done / total;

    // Important = high priority OR manually starred
    final highTasks = _tasks
        .where((t) =>
            t['done'] != true &&
            (t['priority'] ?? '').toString().toLowerCase() == 'high')
        .toList();
    final starredTasks = _tasks
        .where((t) =>
            t['done'] != true &&
            (t['priority'] ?? '').toString().toLowerCase() != 'high' &&
            _markedImportant.contains(t['id'].toString()))
        .toList();
    final otherCount = _tasks
        .where((t) =>
            t['done'] != true &&
            (t['priority'] ?? '').toString().toLowerCase() != 'high' &&
            !_markedImportant.contains(t['id'].toString()))
        .length;

    final importantCount = highTasks.length + starredTasks.length;

    return _SectionCard(
      title: 'משימות חשובות ($importantCount)',
      icon: Icons.priority_high_rounded,
      iconColor: const Color(0xFFEF4444),
      headerTrailing: GestureDetector(
        onTap: _showAddTaskDialog,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.3), width: 0.8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.add_rounded, color: Color(0xFFEF4444), size: 14),
            SizedBox(width: 3),
            Text('חדשה',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 11,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(children: [
                Container(height: 5, color: const Color(0xFF1A2E4A)),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(height: 5, color: const Color(0xFF22C55E)),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Text('$done/$total הושלמו',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ]),
        if (importantCount == 0) ...[
          const SizedBox(height: 12),
          _EmptyState(
              message: total == done
                  ? 'כל המשימות הושלמו! 🎉'
                  : 'אין משימות דחופות כרגע'),
        ] else ...[
          const SizedBox(height: 12),
          if (highTasks.isNotEmpty)
            _buildTaskPriorityGroup(
                'דחוף', const Color(0xFFEF4444), highTasks),
          if (starredTasks.isNotEmpty)
            _buildTaskPriorityGroup(
                'מסומן חשוב ⭐', const Color(0xFFF59E0B), starredTasks),
        ],
        if (otherCount > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.inbox_outlined, color: JC.textMuted, size: 12),
            const SizedBox(width: 5),
            Text('+ $otherCount משימות נוספות בתור',
                style: TextStyle(
                    color: JC.textMuted,
                    fontSize: 11,
                    fontFamily: 'Heebo')),
          ]),
        ],
      ]),
    );
  }

  Widget _buildTaskPriorityGroup(
      String label, Color color, List<Map<String, dynamic>> tasks) {
    const maxShown = 4;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo')),
          const SizedBox(width: 6),
          Text('${tasks.length}',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
        ]),
        const SizedBox(height: 6),
        ...tasks.take(maxShown).map((task) => _ImportantTaskRow(
              task: task,
              isImportant: _markedImportant.contains(task['id'].toString()),
            )),
        if (tasks.length > maxShown)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('+${tasks.length - maxShown} נוספות',
                style: TextStyle(
                    color: JC.textMuted,
                    fontSize: 11,
                    fontFamily: 'Heebo')),
          ),
      ]),
    );
  }

  Widget _ImportantTaskRow(
      {required Map<String, dynamic> task, required bool isImportant}) {
    final content = task['content'] as String? ?? '—';
    final priority = task['priority'] as String?;
    final isHigh =
        (priority ?? '').toString().toLowerCase() == 'high';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1929),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          right: BorderSide(
            color: isHigh
                ? const Color(0xFFEF4444)
                : const Color(0xFFF59E0B),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _completeTask(task),
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _completing.contains(task['id'].toString())
                      ? const Color(0xFF22C55E)
                      : (isHigh ? const Color(0xFFEF4444) : const Color(0xFFF59E0B)),
                  width: 1.5,
                ),
                color: _completing.contains(task['id'].toString())
                    ? const Color(0xFF22C55E).withOpacity(0.15)
                    : Colors.transparent,
              ),
              child: _completing.contains(task['id'].toString())
                  ? const Icon(Icons.check_rounded, size: 13, color: Color(0xFF22C55E))
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              content,
              style: TextStyle(
                color: JC.textPrimary,
                fontSize: 13,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PriorityBadge(priority),
          if (isImportant)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.star_rounded,
                  color: Color(0xFFF59E0B), size: 14),
            ),
        ],
      ),
    );
  }

  // ── Calendar Strip ─────────────────────────────────────────────────────────

  Widget _CalendarStrip() {
    final today = DateTime.now();
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, color: JC.blue400, size: 16),
                const SizedBox(width: 8),
                Text(
                  'לוח שנה',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  ),
                ),
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: 7,
                itemBuilder: (_, i) {
                  final offset = i - 3;
                  final day = today.add(Duration(days: offset));
                  final isToday = offset == 0;
                  final isSelected = offset == _selectedDayOffset;
                  final remCount = _reminders.where((r) {
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

                  return GestureDetector(
                    onTap: () => setState(() => _selectedDayOffset = offset),
                    child: Container(
                      width: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? JC.blue500
                            : isToday
                                ? JC.blue500.withOpacity(0.15)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: JC.blue500.withOpacity(0.5), width: 1)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _hebrewDays[day.weekday % 7],
                            style: TextStyle(
                              color: isSelected ? Colors.white : JC.textMuted,
                              fontSize: 10,
                              fontFamily: 'Heebo',
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: isSelected ? Colors.white : JC.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Heebo',
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (remCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.3)
                                    : const Color(0xFFF59E0B).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '$remCount',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : const Color(0xFFF59E0B),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Heebo',
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_todayReminders.isNotEmpty) ...[
            Divider(color: JC.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDayOffset == 0
                        ? 'אירועים היום'
                        : 'אירועים ביום זה',
                    style: TextStyle(
                      color: JC.textMuted,
                      fontSize: 11,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._todayReminders.take(3).map((r) {
                    final text = r['text'] as String? ?? '—';
                    final time = _timeOfDay(r['scheduled_time'] as String?);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              time.isEmpty ? '--:--' : time,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Heebo',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: JC.textSecondary,
                                fontSize: 12,
                                fontFamily: 'Heebo',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (_todayReminders.length > 3)
                    Text(
                      '+${_todayReminders.length - 3} נוספות',
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Reminders Card ─────────────────────────────────────────────────────────

  Widget _RemindersCard() {
    final now = DateTime.now();

    final sorted = _reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null || iso.isEmpty) return false;
      try {
        final dt = DateTime.parse(iso).toLocal();
        return !dt.isBefore(now.subtract(const Duration(minutes: 1)));
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) =>
          (a['scheduled_time'] as String? ?? '')
              .compareTo(b['scheduled_time'] as String? ?? ''));

    final urgent = sorted.where((r) {
      try {
        final diff = DateTime.parse(r['scheduled_time'] as String)
            .toLocal()
            .difference(now);
        return diff.inMinutes >= 0 && diff.inMinutes <= 120;
      } catch (_) {
        return false;
      }
    }).toList();

    final todayLater = sorted.where((r) {
      try {
        final dt =
            DateTime.parse(r['scheduled_time'] as String).toLocal();
        final diff = dt.difference(now);
        return diff.inMinutes > 120 &&
            dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year;
      } catch (_) {
        return false;
      }
    }).toList();

    final upcoming = sorted.where((r) {
      try {
        final dt =
            DateTime.parse(r['scheduled_time'] as String).toLocal();
        return !(dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year);
      } catch (_) {
        return false;
      }
    }).toList();

    return _SectionCard(
      title: 'תזכורות (${sorted.length})',
      icon: Icons.notifications_active_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: sorted.isEmpty
          ? const _EmptyState(message: 'אין תזכורות קרובות')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Urgent alert banner
              if (urgent.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.3),
                        width: 0.8),
                  ),
                  child: Row(children: [
                    const Text('🔔', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        urgent.length == 1
                            ? 'תזכורת דחופה בתוך שעתיים'
                            : '${urgent.length} תזכורות דחופות בתוך שעתיים',
                        style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 12,
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                _reminderGroupHeader('בקרוב', const Color(0xFFEF4444)),
                const SizedBox(height: 6),
                ...urgent.map((r) =>
                    _ReminderRowHighlighted(r, const Color(0xFFEF4444))),
                if (todayLater.isNotEmpty || upcoming.isNotEmpty)
                  const SizedBox(height: 10),
              ],
              if (todayLater.isNotEmpty) ...[
                _reminderGroupHeader('היום', const Color(0xFFF59E0B)),
                const SizedBox(height: 6),
                ...todayLater.map((r) =>
                    _ReminderRowHighlighted(r, const Color(0xFFF59E0B))),
                if (upcoming.isNotEmpty) const SizedBox(height: 10),
              ],
              if (upcoming.isNotEmpty) ...[
                _reminderGroupHeader('הבא', const Color(0xFF3B82F6)),
                const SizedBox(height: 6),
                ...upcoming
                    .take(3)
                    .map((r) =>
                        _ReminderRowHighlighted(r, const Color(0xFF3B82F6))),
                if (upcoming.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+${upcoming.length - 3} נוספות',
                        style: TextStyle(
                            color: JC.textMuted,
                            fontSize: 11,
                            fontFamily: 'Heebo')),
                  ),
              ],
            ]),
    );
  }

  Widget _reminderGroupHeader(String label, Color color) {
    return Row(children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _ReminderRowHighlighted(
      Map<String, dynamic> reminder, Color accentColor) {
    final text = reminder['text'] as String? ?? '—';
    final iso = reminder['scheduled_time'] as String?;
    final timeStr = _timeOfDay(iso);
    final remaining = _formatRemTime(iso);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border(right: BorderSide(color: accentColor, width: 2)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              timeStr.isEmpty ? '—' : timeStr,
              style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo'),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (remaining.isNotEmpty)
              Text(remaining,
                  style: TextStyle(
                      color: accentColor,
                      fontSize: 11,
                      fontFamily: 'Heebo')),
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standalone Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CardSkeleton extends StatelessWidget {
  final int lines;
  const _CardSkeleton({this.lines = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(lines, (i) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 14,
        width: i == lines - 1 ? 120 : double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2E4A),
          borderRadius: BorderRadius.circular(6),
        ),
      )),
    );
  }
}

class _BuildDayBottomSheet extends StatefulWidget {
  final ApiService api;
  final AppSettings settings;

  const _BuildDayBottomSheet({required this.api, required this.settings});

  @override
  State<_BuildDayBottomSheet> createState() => _BuildDayBottomSheetState();
}

class _BuildDayBottomSheetState extends State<_BuildDayBottomSheet> {
  bool _loading = true;
  String _result = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await widget.api.askJarvis(
        'בנה לי תוכנית יום מהמשימות הפתוחות שלי, בעברית, עם סדר עדיפויות ברור',
        widget.settings,
      );
      if (mounted) setState(() {
        _result = r['answer'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = ApiService.friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B1422),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2E4A),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(
                  children: [
                    const Text('🗓', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'תוכנית היום',
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: JC.textMuted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(color: JC.border),
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                color: JC.blue400, strokeWidth: 2),
                            const SizedBox(height: 14),
                            Text(
                              'ג׳רוויס בונה את היום שלך...',
                              style: TextStyle(
                                  color: JC.textMuted,
                                  fontFamily: 'Heebo',
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!,
                                      style: const TextStyle(
                                          color: Color(0xFFEF4444),
                                          fontFamily: 'Heebo')),
                                  const SizedBox(height: 12),
                                  TextButton(
                                    onPressed: _fetch,
                                    child: Text('נסה שוב',
                                        style: TextStyle(
                                            color: JC.blue400,
                                            fontFamily: 'Heebo')),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            child: Text(
                              _result,
                              style: TextStyle(
                                color: JC.textSecondary,
                                fontSize: 14,
                                height: 1.65,
                                fontFamily: 'Heebo',
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$value $label',
          style: TextStyle(
            color: JC.textMuted,
            fontSize: 12,
            fontFamily: 'Heebo',
          ),
        ),
      ],
    );
  }
}

class _TaskGroup extends StatefulWidget {
  final String label;
  final int count;
  final Color dotColor;
  final List<Map<String, dynamic>> tasks;
  final Set<String> postponed;
  final Set<String> important;
  final void Function(Map<String, dynamic>) onPostpone;
  final void Function(Map<String, dynamic>) onMarkImportant;

  const _TaskGroup({
    required this.label,
    required this.count,
    required this.dotColor,
    required this.tasks,
    required this.postponed,
    required this.important,
    required this.onPostpone,
    required this.onMarkImportant,
  });

  @override
  State<_TaskGroup> createState() => _TaskGroupState();
}

class _TaskGroupState extends State<_TaskGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: widget.dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.dotColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.count} משימות',
                      style: TextStyle(
                        color: widget.dotColor,
                        fontSize: 10,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: JC.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: JC.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: widget.tasks
                    .map((task) => _SmartTaskCard(
                          task: task,
                          postponed: widget.postponed
                              .contains(task['id'].toString()),
                          important: widget.important
                              .contains(task['id'].toString()),
                          onPostpone: () => widget.onPostpone(task),
                          onMarkImportant: () =>
                              widget.onMarkImportant(task),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? headerTrailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                      )),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

class _SmartTaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final bool postponed;
  final bool important;
  final VoidCallback onPostpone;
  final VoidCallback onMarkImportant;

  const _SmartTaskCard({
    required this.task,
    required this.postponed,
    required this.important,
    required this.onPostpone,
    required this.onMarkImportant,
  });

  @override
  Widget build(BuildContext context) {
    final content = task['content'] as String? ?? '—';
    final priority = task['priority'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1929),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  content,
                  style: TextStyle(
                    color: postponed ? JC.textMuted : JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                    decoration:
                        postponed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PriorityBadge(priority),
              if (important)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.star_rounded,
                      color: Color(0xFFF59E0B), size: 16),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ActionButton(
                label: 'דחה למחר',
                icon: Icons.schedule_rounded,
                onTap: postponed ? null : onPostpone,
                active: postponed,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                label: 'סמן חשוב',
                icon: Icons.star_outline_rounded,
                onTap: important ? null : onMarkImportant,
                active: important,
                activeColor: const Color(0xFFF59E0B),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final Color activeColor;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.activeColor = const Color(0xFF60A5FA),
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : JC.textMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              active ? activeColor.withOpacity(0.12) : const Color(0xFF0F1929),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? activeColor.withOpacity(0.5) : JC.border,
              width: 0.6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  final Map<String, dynamic> reminder;

  const _ReminderRow(this.reminder);

  @override
  Widget build(BuildContext context) {
    final text = reminder['text'] as String? ?? '—';
    final iso = reminder['scheduled_time'] as String?;
    final timeStr = _timeOfDay(iso);
    final remaining = _formatRemTime(iso);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                timeStr.isEmpty ? '—' : timeStr,
                style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 13,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600)),
                if (remaining.isNotEmpty)
                  Text(remaining,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String? priority;

  const _PriorityBadge(this.priority);

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(priority);
    final label = _priorityLabel(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo')),
      ),
    );
  }
}

class _SnackOverlay extends StatelessWidget {
  final String message;

  const _SnackOverlay(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E4A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
  }
}

// ── Donut Progress Chart ──────────────────────────────────────────────────────

class _DonutProgressPainter extends CustomPainter {
  final double progress;

  const _DonutProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 7;
    const strokeW = 9.0;
    const startAngle = -1.5708; // -π/2 (top)
    const fullCircle = 6.2832;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      fullCircle,
      false,
      Paint()
        ..color = const Color(0xFF1A2E4A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW,
    );

    if (progress > 0) {
      final sweep = progress.clamp(0.0, 1.0) * fullCircle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        Paint()
          ..color = progress > 0.7
              ? const Color(0xFF22C55E)
              : const Color(0xFF3B82F6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round,
      );
    }

    final pct = (progress * 100).round();
    final pctTp = TextPainter(
      text: TextSpan(
        text: '$pct',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          fontFamily: 'Heebo',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final symbolTp = TextPainter(
      text: const TextSpan(
        text: '%',
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontFamily: 'Heebo'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final totalW = pctTp.width + symbolTp.width;
    pctTp.paint(canvas, center.translate(-totalW / 2, -pctTp.height / 2));
    symbolTp.paint(canvas,
        center.translate(-totalW / 2 + pctTp.width, -pctTp.height / 2 + 4));
  }

  @override
  bool shouldRepaint(covariant _DonutProgressPainter old) =>
      old.progress != progress;
}

// ── Priority Bar Row ──────────────────────────────────────────────────────────

class _PriorityBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _PriorityBar(this.label, this.count, this.total, this.color);

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo'),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 6, color: const Color(0xFF1A2E4A)),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(height: 6, color: color),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 18,
          child: Text(
            '$count',
            style: TextStyle(
              color: count > 0 ? color : JC.textMuted,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.left,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

Widget _ErrorView(String msg, VoidCallback onRetry) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: JC.textMuted, size: 48),
          const SizedBox(height: 16),
          Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: JC.textSecondary, fontSize: 14, fontFamily: 'Heebo')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('נסה שוב',
                style: TextStyle(fontFamily: 'Heebo')),
          ),
        ],
      ),
    ),
  );
}
