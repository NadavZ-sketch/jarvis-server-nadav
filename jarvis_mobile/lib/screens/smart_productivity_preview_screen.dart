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

// Demo: AI recommendations — generated client-side from real task data
String _buildDayRecommendation(
    List<Map<String, dynamic>> tasks, String userName) {
  final open = tasks.where((t) => t['done'] != true).toList();
  final highPriority = open.where((t) =>
      (t['priority'] ?? '').toString().toLowerCase() == 'high').length;
  final total = open.length;

  if (total == 0) return 'כל המשימות הושלמו! היום נקי ✅ קחו הפסקה.';
  if (highPriority > 2) {
    return 'יש $highPriority משימות בעדיפות גבוהה. '
        'Jarvis ממליץ להתחיל בהן לפני הצהריים כדי לפנות את אחר הצהריים.';
  }
  if (total > 6) {
    return 'יש לך $total משימות פתוחות — זה הרבה ליום אחד. '
        'Jarvis ממליץ לדחות 2-3 למחר ולהתמקד ב-${total > 4 ? 4 : total} עיקריות.';
  }
  return 'יש לך $total משימות פתוחות. '
      'נראה שהיום ניהולי — סדר עדיפויות ותתחיל מהחשובות ביותר.';
}

// Demo load distribution
List<Map<String, dynamic>> _buildLoadMap(
    List<Map<String, dynamic>> tasks, List<Map<String, dynamic>> reminders) {
  final slots = <Map<String, dynamic>>[
    {'label': 'בוקר (8-12)', 'load': 0},
    {'label': 'צהריים (12-15)', 'load': 0},
    {'label': 'אחר הצהריים (15-18)', 'load': 0},
    {'label': 'ערב (18+)', 'load': 0},
  ];

  for (final r in reminders) {
    final iso = r['scheduled_time'] as String?;
    if (iso == null) continue;
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour;
      final idx = h < 12 ? 0 : h < 15 ? 1 : h < 18 ? 2 : 3;
      slots[idx]['load'] = (slots[idx]['load'] as int) + 1;
    } catch (_) {}
  }

  // Distribute open tasks evenly for demo
  final open = tasks.where((t) => t['done'] != true).length;
  for (int i = 0; i < open && i < 4; i++) {
    slots[i % 4]['load'] = (slots[i % 4]['load'] as int) + 1;
  }
  return slots;
}

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

  // UI state
  bool _dayPlanBuilt = false;
  List<Map<String, dynamic>> _dayPlan = [];
  Set<String> _postponed = {};
  Set<String> _markedImportant = {};
  String? _snackMessage;

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

  void _buildDayPlan() {
    final open = _tasks.where((t) => t['done'] != true).toList();
    // Sort: high priority first
    open.sort((a, b) {
      const order = {'high': 0, 'medium': 1, 'low': 2};
      final pa = order[(a['priority'] ?? '').toString().toLowerCase()] ?? 2;
      final pb = order[(b['priority'] ?? '').toString().toLowerCase()] ?? 2;
      return pa.compareTo(pb);
    });
    setState(() {
      _dayPlan = open.take(6).toList();
      _dayPlanBuilt = true;
    });
    _showSnack('תוכנית היום נבנתה מ-${_dayPlan.length} משימות עדיפות');
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
    final now = DateTime.now();
    return _reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null) return false;
      try {
        final dt = DateTime.parse(iso).toLocal();
        return dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
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

  List<Map<String, dynamic>> get _openTasks =>
      _tasks.where((t) => t['done'] != true).toList();

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
          title: const Column(
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
              icon: Icon(Icons.refresh_rounded,
                  color: JC.textSecondary, size: 22),
              onPressed: () {
                setState(() { _loading = true; _error = null; _dayPlanBuilt = false; });
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
                      ? const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: JC.blue400))
                      : _error != null
                          ? _ErrorView(_error!, _loadData)
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surface,
                              onRefresh: _loadData,
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                children: [
                                  _RecommendationCard(),
                                  const SizedBox(height: 20),
                                  _LoadMapCard(),
                                  const SizedBox(height: 20),
                                  _DayPlanCard(),
                                  const SizedBox(height: 20),
                                  _TasksCard(),
                                  const SizedBox(height: 20),
                                  _RemindersCard(),
                                  SizedBox(height: bottomPad + 8),
                                ],
                              ),
                            ),
                ),
                const PreviewBanner(),
              ],
            ),
            // Snack overlay
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

  // ── Section: Recommendation ─────────────────────────────────────────────────

  Widget _RecommendationCard() {
    final userName = widget.settings.userName;
    final aiText = _todayMessage.isNotEmpty
        ? _todayMessage
        : _buildDayRecommendation(_tasks, userName);

    return _SectionCard(
      title: 'Jarvis ממליץ עכשיו',
      icon: Icons.auto_awesome_rounded,
      iconColor: JC.blue400,
      headerTrailing: const DemoChip(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(aiText,
              style: TextStyle(
                color: JC.textSecondary,
                fontSize: 14,
                height: 1.5,
                fontFamily: 'Heebo',
              )),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _buildDayPlan,
              icon: const Icon(Icons.calendar_today_rounded, size: 16),
              label: const Text('בנה לי את היום',
                  style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: Load Map ──────────────────────────────────────────────────────

  Widget _LoadMapCard() {
    final slots = _buildLoadMap(_tasks, _reminders);
    final maxLoad =
        slots.map((s) => s['load'] as int).reduce((a, b) => a > b ? a : b);

    return _SectionCard(
      title: 'עומס היום',
      icon: Icons.bar_chart_rounded,
      iconColor: const Color(0xFFA5B4FC),
      headerTrailing: const DemoChip(),
      child: Column(
        children: slots.map((slot) {
          final load = slot['load'] as int;
          final ratio = maxLoad == 0 ? 0.0 : load / maxLoad;
          final isHeavy = ratio > 0.7;
          final barColor = isHeavy ? const Color(0xFFF59E0B) : JC.blue500;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(slot['label'] as String,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo')),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2E4A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: ratio.clamp(0.05, 1.0),
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 24,
                  child: Text('$load',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: isHeavy ? const Color(0xFFF59E0B) : JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo',
                          fontWeight: isHeavy ? FontWeight.w700 : FontWeight.normal)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section: Day Plan ──────────────────────────────────────────────────────

  Widget _DayPlanCard() {
    if (!_dayPlanBuilt) return const SizedBox.shrink();
    return _SectionCard(
      title: 'תוכנית היום שלי',
      icon: Icons.format_list_numbered_rounded,
      iconColor: const Color(0xFF22C55E),
      child: Column(
        children: _dayPlan.asMap().entries.map((entry) {
          final i = entry.key;
          final task = entry.value;
          final content = task['content'] as String? ?? '—';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: JC.blue500.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: JC.blue400,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Heebo')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(content,
                      style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 13,
                          fontFamily: 'Heebo')),
                ),
                _PriorityBadge(task['priority'] as String?),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Section: Tasks ─────────────────────────────────────────────────────────

  Widget _TasksCard() {
    final open = _openTasks;
    return _SectionCard(
      title: 'משימות חכמות (${open.length})',
      icon: Icons.task_alt_rounded,
      iconColor: JC.blue400,
      child: open.isEmpty
          ? const _EmptyState(message: 'אין משימות פתוחות 🎉')
          : Column(
              children: open.map((task) => _SmartTaskCard(
                    task: task,
                    postponed: _postponed.contains(task['id'].toString()),
                    important: _markedImportant.contains(task['id'].toString()),
                    onPostpone: () => _postponeTask(task),
                    onMarkImportant: () => _markImportant(task),
                  )).toList(),
            ),
    );
  }

  // ── Section: Reminders ─────────────────────────────────────────────────────

  Widget _RemindersCard() {
    final today = _todayReminders;
    return _SectionCard(
      title: 'תזכורות היום (${today.length})',
      icon: Icons.notifications_outlined,
      iconColor: const Color(0xFFF59E0B),
      child: today.isEmpty
          ? const _EmptyState(message: 'אין תזכורות להיום')
          : Column(
              children: today.map((r) => _ReminderRow(r)).toList(),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

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
              : JC.border,
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
                    decoration: postponed ? TextDecoration.lineThrough : null,
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
          color: active
              ? activeColor.withOpacity(0.12)
              : const Color(0xFF0F1929),
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
