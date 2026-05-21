import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../widgets/preview_banner.dart';

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
  return 'יש לך $total משימות פתוחות. '
      'התחל מהחשובות ביותר.';
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

  const SmartProductivityPreviewScreen({super.key, required this.settings});

  @override
  State<SmartProductivityPreviewScreen> createState() =>
      _SmartProductivityPreviewScreenState();
}

class _SmartProductivityPreviewScreenState
    extends State<SmartProductivityPreviewScreen> {
  late final ApiService _api;

  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _reminders = [];
  String _todayMessage = '';

  bool _loading = true;
  String? _error;

  Set<String> _postponed = {};
  Set<String> _markedImportant = {};
  String? _snackMessage;

  // Selected calendar day offset (0 = today)
  int _selectedDayOffset = 0;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _api.getTasks(),
        _api.getReminders(),
        _api.getTodayMessage().catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        final msg = results[2] as Map<String, dynamic>;
        setState(() {
          _tasks = results[0] as List<Map<String, dynamic>>;
          _reminders = results[1] as List<Map<String, dynamic>>;
          _todayMessage = (msg['message'] ?? msg['text'] ?? '') as String;
          _loading = false;
        });
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

  void _postponeTask(Map<String, dynamic> task) {
    setState(() => _postponed.add(task['id'].toString()));
    _showSnack('המשימה נדחתה למחר (Preview — לא נשמר בשרת)');
  }

  void _markImportant(Map<String, dynamic> task) {
    setState(() => _markedImportant.add(task['id'].toString()));
    _showSnack('סומנה כחשובה ✓');
  }

  void _showSnack(String msg) {
    setState(() => _snackMessage = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _snackMessage = null);
    });
  }

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

  List<Map<String, dynamic>> get _inProgressTasks => _tasks
      .where((t) =>
          t['done'] != true &&
          _markedImportant.contains(t['id'].toString()))
      .toList();

  List<Map<String, dynamic>> get _toDoTasks => _tasks
      .where((t) =>
          t['done'] != true &&
          !_markedImportant.contains(t['id'].toString()) &&
          (t['priority'] ?? '').toString().toLowerCase() != 'low')
      .toList();

  List<Map<String, dynamic>> get _upcomingTasks => _tasks
      .where((t) =>
          t['done'] != true &&
          !_markedImportant.contains(t['id'].toString()) &&
          (t['priority'] ?? '').toString().toLowerCase() == 'low')
      .toList();

  int get _doneTasks => _tasks.where((t) => t['done'] == true).length;
  int get _totalTasks => _tasks.length;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 16,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: JC.textSecondary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'מנהל היום החכם',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo',
                ),
              ),
              Text(
                'Smart Productivity · Preview',
                style: TextStyle(
                  color: JC.textMuted,
                  fontSize: 11,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon:
                  Icon(Icons.refresh_rounded, color: JC.textSecondary, size: 22),
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadData();
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
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
                                  _GreetingCard(),
                                  const SizedBox(height: 16),
                                  _QuickActionsRow(),
                                  const SizedBox(height: 16),
                                  _CalendarStrip(),
                                  const SizedBox(height: 16),
                                  _ProgressCard(),
                                  const SizedBox(height: 16),
                                  _GroupedTasksSection(),
                                  const SizedBox(height: 16),
                                  _RemindersCard(),
                                  SizedBox(height: bottomPad + 8),
                                ],
                              ),
                            ),
                ),
                const PreviewBanner(),
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
    );
  }

  // ── Greeting Card ──────────────────────────────────────────────────────────

  Widget _GreetingCard() {
    final greeting = _dynamicGreeting(widget.settings.userName);
    final emoji = _greetingEmoji();
    final aiText = _todayMessage.isNotEmpty
        ? _todayMessage
        : _buildDayRecommendation(_tasks, widget.settings.userName);
    final now = DateTime.now();
    final dateStr =
        'יום ${_hebrewDays[now.weekday % 7]}, ${now.day} ב${_hebrewMonths[now.month - 1]}';

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2E4A),
            JC.surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 28),
              ),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1929),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF3B82F6).withOpacity(0.3), width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: JC.blue400, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    aiText,
                    style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                      fontFamily: 'Heebo',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _QuickActionsRow() {
    final actions = [
      {'icon': Icons.build_circle_outlined, 'label': 'בנה את היום', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.task_alt_rounded, 'label': 'עדכן משימות', 'color': const Color(0xFF22C55E)},
      {'icon': Icons.add_circle_outline_rounded, 'label': 'משימה חדשה', 'color': const Color(0xFFA5B4FC)},
      {'icon': Icons.calendar_month_rounded, 'label': 'חבר יומן', 'color': const Color(0xFFF59E0B)},
    ];
    return SizedBox(
      height: 76,
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
            onTap: () => _showSnack('${a['label']} · בקרוב (Preview)'),
          );
        },
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
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded,
                    color: JC.blue400, size: 16),
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
                  // i=0 is today, i>0 is future days
                  final offset = i - 3; // show 3 past, today, 3 future
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
                    onTap: () =>
                        setState(() => _selectedDayOffset = offset),
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
                              color: isSelected
                                  ? Colors.white
                                  : JC.textMuted,
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
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            )
                          else
                            const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Events for selected day
          if (_todayReminders.isNotEmpty) ...[
            Divider(color: JC.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedDayOffset == 0 ? 'אירועים היום' : 'אירועים ביום זה',
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

  // ── Progress Card ──────────────────────────────────────────────────────────

  Widget _ProgressCard() {
    final done = _doneTasks;
    final total = _totalTasks;
    final progress = total == 0 ? 0.0 : done / total;
    final openCount = total - done;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded,
                  color: const Color(0xFF22C55E), size: 16),
              const SizedBox(width: 8),
              Text(
                'התקדמות משימות',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo',
                ),
              ),
              const Spacer(),
              Text(
                '$done / $total',
                style: TextStyle(
                  color: JC.textMuted,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFF1A2E4A),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.7
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF3B82F6),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniStat(
                label: 'הושלמו',
                value: '$done',
                color: const Color(0xFF22C55E),
              ),
              const SizedBox(width: 12),
              _MiniStat(
                label: 'בביצוע',
                value: '${_inProgressTasks.length}',
                color: const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 12),
              _MiniStat(
                label: 'פתוחות',
                value: '$openCount',
                color: const Color(0xFF475569),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Grouped Tasks ──────────────────────────────────────────────────────────

  Widget _GroupedTasksSection() {
    return Column(
      children: [
        if (_inProgressTasks.isNotEmpty)
          _TaskGroup(
            label: 'בביצוע',
            count: _inProgressTasks.length,
            dotColor: const Color(0xFF3B82F6),
            tasks: _inProgressTasks,
            postponed: _postponed,
            important: _markedImportant,
            onPostpone: _postponeTask,
            onMarkImportant: _markImportant,
          ),
        if (_inProgressTasks.isNotEmpty) const SizedBox(height: 12),
        if (_toDoTasks.isNotEmpty)
          _TaskGroup(
            label: 'לביצוע',
            count: _toDoTasks.length,
            dotColor: const Color(0xFFF59E0B),
            tasks: _toDoTasks,
            postponed: _postponed,
            important: _markedImportant,
            onPostpone: _postponeTask,
            onMarkImportant: _markImportant,
          ),
        if (_toDoTasks.isNotEmpty) const SizedBox(height: 12),
        if (_upcomingTasks.isNotEmpty)
          _TaskGroup(
            label: 'הבא בתור',
            count: _upcomingTasks.length,
            dotColor: const Color(0xFF475569),
            tasks: _upcomingTasks,
            postponed: _postponed,
            important: _markedImportant,
            onPostpone: _postponeTask,
            onMarkImportant: _markImportant,
          ),
        if (_inProgressTasks.isEmpty &&
            _toDoTasks.isEmpty &&
            _upcomingTasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JC.border, width: 0.8),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.task_alt_rounded,
                      color: const Color(0xFF22C55E), size: 40),
                  const SizedBox(height: 10),
                  Text(
                    'כל המשימות הושלמו! 🎉',
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'הגענו למטרה היום',
                    style: TextStyle(
                      color: JC.textMuted,
                      fontSize: 13,
                      fontFamily: 'Heebo',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Reminders Card ─────────────────────────────────────────────────────────

  Widget _RemindersCard() {
    final today = _todayReminders;
    return _SectionCard(
      title: 'תזכורות (${today.length})',
      icon: Icons.notifications_outlined,
      iconColor: const Color(0xFFF59E0B),
      child: today.isEmpty
          ? _EmptyState(
              message: _selectedDayOffset == 0
                  ? 'אין תזכורות להיום'
                  : 'אין תזכורות ליום זה')
          : Column(
              children: today.map((r) => _ReminderRow(r)).toList(),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        children: [
          // Group header
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
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
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
        border: Border.all(color: JC.border, width: 0.8),
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
        border: Border.all(
          color: important
              ? const Color(0xFFF59E0B).withOpacity(0.5)
              : const Color(0xFF1A2E4A),
          width: 0.8,
        ),
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
        border: Border.all(color: JC.blue500, width: 0.8),
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
