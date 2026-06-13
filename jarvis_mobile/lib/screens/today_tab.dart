import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/markdown_lite.dart';
import '../widgets/productivity/week_strip.dart';
import '../widgets/productivity/unified_item_card.dart';

class TodayTab extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback? onGoToTasks;
  final VoidCallback? onGoToReminders;
  final VoidCallback? onGoToCalendar;

  const TodayTab({
    super.key,
    required this.settings,
    this.onGoToTasks,
    this.onGoToReminders,
    this.onGoToCalendar,
  });

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final Set<String> _completing = {};

  String? _briefing;
  bool _briefingLoading = false;
  bool _briefingExpanded = true;

  // Week strip state
  Map<DateTime, DayMeta> _weekData = {};
  DateTime _selectedWeekDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCache();
    _fetch();
    _loadWeekData();
  }

  // ─── Week strip data ───────────────────────────────────────────────────────

  Future<void> _loadWeekData() async {
    try {
      final events = await ApiService(widget.settings).getCalendarEvents();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));

      final Map<DateTime, _DayAccum> accum = {};

      for (final e in events) {
        DateTime? dt;
        final type = e['type']?.toString();
        try {
          if (type == 'task') {
            dt = DateTime.tryParse(e['due_date']?.toString() ?? '')?.toLocal();
          } else if (type == 'reminder') {
            dt =
                DateTime.tryParse(e['scheduled_time']?.toString() ?? '')?.toLocal();
          } else {
            final dateStr = e['start']?['dateTime']?.toString() ??
                e['start']?['date']?.toString() ??
                e['date']?.toString();
            if (dateStr != null) dt = DateTime.tryParse(dateStr)?.toLocal();
          }
        } catch (_) {}

        if (dt == null) continue;
        final key = DateTime(dt.year, dt.month, dt.day);
        if (key.isBefore(startOfWeek) || key.isAfter(endOfWeek)) continue;

        final a = accum[key] ??= _DayAccum();
        if (type == 'task') {
          final isOver = dt.isBefore(now) && e['done'] != true;
          if (isOver) {
            a.overdue++;
          } else {
            a.tasks++;
          }
        } else if (type == 'reminder') {
          a.reminders++;
        }
      }

      if (mounted) {
        setState(() {
          _weekData = accum.map(
            (k, v) => MapEntry(
              k,
              DayMeta(
                  tasks: v.tasks,
                  reminders: v.reminders,
                  overdue: v.overdue),
            ),
          );
        });
      }
    } catch (_) {
      // Non-critical: week strip just stays empty on failure
    }
  }

  // ─── Briefing ──────────────────────────────────────────────────────────────

  String get _briefingCacheKey =>
      'today_briefing_v2::${widget.settings.todayBriefingFocus.trim()}';

  Future<void> _loadBriefingCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_briefingCacheKey);
      final tsStr = prefs.getString('${_briefingCacheKey}_ts');
      if (text != null && tsStr != null) {
        final ts = DateTime.tryParse(tsStr);
        if (ts != null && DateTime.now().difference(ts).inHours < 20) {
          if (mounted) setState(() => _briefing = text);
          return;
        }
      }
      _fetchBriefing();
    } catch (_) {
      _fetchBriefing();
    }
  }

  Future<void> _fetchBriefing() async {
    if (_briefingLoading) return;
    if (mounted) setState(() => _briefingLoading = true);
    try {
      final titles = _items
          .map((i) => (i['title'] ?? i['text'] ?? i['content'] ?? '').toString())
          .where((t) => t.isNotEmpty)
          .take(20)
          .join(', ');
      final focus = widget.settings.todayBriefingFocus.trim();
      final focusLine = focus.isEmpty ? '' : ' שים דגש על: $focus.';
      final message =
          'בריפינג יומי קצר בעברית. הנושאים להיום: ${titles.isEmpty ? 'לא נמצאו פריטים פתוחים' : titles}. '
          'תן סיכום ממוקד של מה חשוב היום ב-3 נקודות מקסימום.$focusLine';
      final result = await ApiService(widget.settings)
          .askJarvis(message, widget.settings, intent: 'chat');
      final raw = ((result['answer'] as String?) ?? '').trim();
      final looksLikeError = raw.contains('לא הצלחתי') ||
          raw.contains('לא ניתן') ||
          (raw.contains('בעיה') && raw.contains('נסה שוב'));
      final text = (raw.isNotEmpty && !looksLikeError) ? raw : '';
      if (text.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_briefingCacheKey, text);
        await prefs.setString(
            '${_briefingCacheKey}_ts', DateTime.now().toIso8601String());
      }
      if (mounted) {
        setState(() {
          _briefing = text.isNotEmpty ? text : _localBriefing();
          _briefingLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _briefing = _localBriefing();
          _briefingLoading = false;
        });
      }
    }
  }

  String _localBriefing() {
    final overdue = _items.where((i) => i['section'] == 'overdue').length;
    final today = _items.where((i) => i['section'] == 'today').length;
    final lines = <String>[];
    if (overdue > 0) lines.add('• ⚠️ $overdue פריטים עברו את המועד — טפל בהם ראשון');
    if (today > 0) lines.add('• יש לך $today פריטים להיום — בחר 3 עדיפויות ועמוד בהן');
    if (lines.isEmpty) {
      lines.add('• הרשימה נקייה — זמן טוב לתכנן');
      lines.add('• הגדר יעד ברור אחד ליום זה');
    }
    lines.add('• קבע זמן קבוע לכל פריט ועמוד בו');
    return lines.join('\n');
  }

  // ─── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('today_items');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() {
        _items = cached;
        _loading = false;
      });
    }
  }

  Future<void> _completeTask(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null || _completing.contains(id)) return;
    setState(() => _completing.add(id));
    try {
      await ApiService(widget.settings).updateTask(id, done: true);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((i) => i['id']?.toString() == id);
        _completing.remove(id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('משימה הושלמה ✓',
              textDirection: TextDirection.rtl,
              style:
                  TextStyle(fontFamily: 'Heebo', color: JC.textPrimary)),
          backgroundColor: JC.surfaceAlt,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _completing.remove(id));
    }
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ApiService(widget.settings);
      final results = await Future.wait([
        api.getStats(),
        api.getTodayItems(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _items = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
        _error = null;
      });
      CacheService.saveList('today_items', _items);
      if (widget.settings.todayBriefingEnabled) {
        _loadBriefingCache();
      }
    } catch (e) {
      if (mounted && _items.isEmpty) {
        setState(() {
          _error = ApiService.friendlyError(e);
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _section(String s) =>
      _items.where((i) => i['section'] == s).toList();

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingSkeleton(itemCount: 5);
    if (_error != null && _items.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'שגיאת טעינה',
        subtitle: _error!,
      );
    }

    final overdue = _section('overdue');
    final today = _section('today');
    final reminders = _section('reminder');
    final allItems = [...overdue, ...today];
    final focusTasks =
        allItems.where((i) => i['type'] != 'reminder').take(3).toList();
    final remainingTasks =
        allItems.where((i) => i['type'] != 'reminder').skip(3).toList();
    final isEmpty =
        overdue.isEmpty && today.isEmpty && reminders.isEmpty;

    return Column(
      children: [
        // ── Week strip ──────────────────────────────────────────────────────
        WeekStripWidget(
          selected: _selectedWeekDay,
          dayData: _weekData,
          onDayTapped: (day) {
            setState(() => _selectedWeekDay = day);
            final now = DateTime.now();
            final isToday = day.year == now.year &&
                day.month == now.month &&
                day.day == now.day;
            if (!isToday) widget.onGoToCalendar?.call();
          },
        ),
        Divider(
            height: 0.6,
            thickness: 0.6,
            color: JC.border.withOpacity(0.4)),
        // ── Main content ────────────────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            color: JC.blue400,
            backgroundColor: JC.surfaceAlt,
            onRefresh: _fetch,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
              children: [
                _TodayHeroHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Quick stats row ─────────────────────────────────
                      const SizedBox(height: 8),
                      _QuickStatsRow(
                        stats: _stats,
                        onGoToTasks: widget.onGoToTasks,
                        onGoToReminders: widget.onGoToReminders,
                      ),
                      // ── AI Briefing ─────────────────────────────────────
                      if (widget.settings.todayBriefingEnabled) ...[
                        const SizedBox(height: 14),
                        _BriefingCard(
                          text: _briefing,
                          loading: _briefingLoading,
                          expanded: _briefingExpanded,
                          onToggle: () => setState(
                              () => _briefingExpanded = !_briefingExpanded),
                          onRefresh: () {
                            setState(() => _briefing = null);
                            _fetchBriefing();
                          },
                        ),
                      ],
                      // ── Focus tasks ─────────────────────────────────────
                      if (focusTasks.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _SectionLabel(
                          label: 'פוקוס',
                          count: focusTasks.length,
                          icon: Icons.bolt_rounded,
                          color: JC.amber400,
                        ),
                        const SizedBox(height: 8),
                        ...focusTasks.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _FocusTaskCard(
                                item: item,
                                isCompleting: _completing
                                    .contains(item['id']?.toString() ?? ''),
                                onComplete: () => _completeTask(item),
                              ),
                            )),
                      ],
                      // ── Remaining tasks ─────────────────────────────────
                      if (remainingTasks.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _SectionLabel(
                          label: 'יתר המשימות',
                          count: remainingTasks.length,
                          icon: Icons.list_alt_rounded,
                          color: JC.blue400,
                          onTap: widget.onGoToTasks,
                        ),
                        const SizedBox(height: 8),
                        ...remainingTasks.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TodayItemTile(
                                item: item,
                                isCompleting: _completing
                                    .contains(item['id']?.toString() ?? ''),
                                onComplete: () => _completeTask(item),
                              ),
                            )),
                      ],
                      // ── Reminders (UnifiedItemCard) ─────────────────────
                      if (reminders.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _SectionLabel(
                          label: 'תזכורות',
                          count: reminders.length,
                          icon: Icons.notifications_outlined,
                          color: JC.amber400,
                          onTap: widget.onGoToReminders,
                        ),
                        const SizedBox(height: 8),
                        ...reminders.map((item) => UnifiedItemCard(
                              item: item,
                              itemType: 'reminder',
                            )),
                      ],
                      if (isEmpty) ...[
                        const SizedBox(height: 32),
                        EmptyState(
                          icon: Icons.check_circle_outline_rounded,
                          title: 'הכל נקי להיום! 🌟',
                          subtitle: 'אין משימות פתוחות — כל הכבוד!',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Mutable day accumulator (private, for _loadWeekData) ────────────────────

class _DayAccum {
  int tasks = 0;
  int reminders = 0;
  int overdue = 0;
}

// ─── Hero header (greeting + date only, no stats) ────────────────────────────

class _TodayHeroHeader extends StatelessWidget {
  const _TodayHeroHeader();

  static const _days = [
    'ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'
  ];
  static const _months = [
    '', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
    'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
  ];

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'בוקר טוב ☀️';
    if (hour < 17) return 'צהריים טובים 🌤️';
    return 'ערב טוב 🌙';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            JC.blue500.withOpacity(0.14),
            JC.indigo500.withOpacity(0.08),
            JC.bg,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _greeting,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: JC.textSecondary,
              fontSize: 13,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'יום ${_days[now.weekday % 7]}, ${now.day} ב${_months[now.month]}',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: JC.textPrimary,
              fontSize: 20,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick stats row (tappable chips replacing the header stats) ──────────────

class _QuickStatsRow extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final VoidCallback? onGoToTasks;
  final VoidCallback? onGoToReminders;

  const _QuickStatsRow({
    required this.stats,
    this.onGoToTasks,
    this.onGoToReminders,
  });

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();

    final tasks = stats!['tasks'] as Map<String, dynamic>? ?? {};
    final pending = (tasks['pending'] as num?)?.toInt() ?? 0;
    final done = (tasks['done'] as num?)?.toInt() ?? 0;
    final remindersData = stats!['reminders'] as Map<String, dynamic>? ?? {};
    final active = (remindersData['active'] as num?)?.toInt() ?? 0;

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        GestureDetector(
          onTap: onGoToTasks,
          child: _StatChip(
            value: '$pending',
            label: 'משימות',
            color: pending > 0 ? JC.blue400 : JC.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        _StatChip(
          value: '$done',
          label: 'הושלמו',
          color: done > 0 ? JC.green500 : JC.textMuted,
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onGoToReminders,
          child: _StatChip(
            value: '$active',
            label: 'תזכורות',
            color: active > 0 ? JC.amber400 : JC.textMuted,
          ),
        ),
      ],
    );
  }
}

// ─── Stat chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatChip(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontFamily: 'Heebo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontFamily: 'Heebo',
                  fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _SectionLabel({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: JC.textSecondary,
                  fontFamily: 'Heebo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700)),
          ),
          if (onTap != null) ...[
            const Spacer(),
            Icon(Icons.chevron_left_rounded,
                size: 16, color: JC.textMuted),
          ],
        ],
      ),
    );
  }
}

// ─── AI briefing card ─────────────────────────────────────────────────────────

class _BriefingCard extends StatelessWidget {
  final String? text;
  final bool loading;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRefresh;

  const _BriefingCard({
    required this.text,
    required this.loading,
    required this.expanded,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          border: Border(
            right: BorderSide(color: JC.blue500, width: 3),
            top: BorderSide(color: JC.border.withOpacity(0.5), width: 0.8),
            left: BorderSide(color: JC.border.withOpacity(0.5), width: 0.8),
            bottom:
                BorderSide(color: JC.border.withOpacity(0.5), width: 0.8),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 16, color: JC.blue400),
                      const SizedBox(width: 7),
                      Text(
                        'סיכום יומי',
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                        ),
                      ),
                      const Spacer(),
                      if (loading)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.8, color: JC.blue400),
                        )
                      else
                        GestureDetector(
                          onTap: onRefresh,
                          child: Icon(Icons.refresh_rounded,
                              size: 16, color: JC.textMuted),
                        ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: expanded ? 0 : 0.5,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_less_rounded,
                            size: 18, color: JC.textMuted),
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 10),
                        if (text != null && text!.trim().isNotEmpty)
                          MarkdownLite(
                            text: text!,
                            textDirection: TextDirection.rtl,
                            baseStyle: TextStyle(
                              color: JC.textSecondary,
                              fontSize: 13,
                              height: 1.65,
                              fontFamily: 'Heebo',
                            ),
                          )
                        else
                          Text(
                            loading
                                ? 'מכין סיכום יומי...'
                                : 'לחץ ריענון לטעינת הסיכום',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: JC.textSecondary,
                              fontSize: 13,
                              fontFamily: 'Heebo',
                            ),
                          ),
                      ],
                    ),
                    crossFadeState: expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Focus task card (prominent top-3) ───────────────────────────────────────

class _FocusTaskCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isCompleting;
  final VoidCallback? onComplete;
  const _FocusTaskCard({
    required this.item,
    this.isCompleting = false,
    this.onComplete,
  });

  Color get _priorityColor => switch (item['priority']?.toString()) {
        'high' => JC.cancelRed,
        'low' => JC.green500,
        _ => JC.amber400,
      };

  @override
  Widget build(BuildContext context) {
    final isOverdue = item['section'] == 'overdue';
    final timeLabel = UnifiedItemCard.formatTime(item['time']);
    final pColor = isOverdue ? JC.cancelRed : _priorityColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pColor.withOpacity(0.4), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: pColor.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          GestureDetector(
            onTap: isCompleting ? null : onComplete,
            child: SizedBox(
              width: 26,
              height: 26,
              child: isCompleting
                  ? CircularProgressIndicator(
                      strokeWidth: 2.5, color: JC.green500)
                  : Icon(Icons.radio_button_unchecked_rounded,
                      color: pColor, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item['title']?.toString() ?? '',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (timeLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(timeLabel,
                      style: TextStyle(
                        color: isOverdue ? JC.cancelRed : JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        fontWeight:
                            isOverdue ? FontWeight.w600 : FontWeight.normal,
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Regular today item tile ──────────────────────────────────────────────────

class _TodayItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isCompleting;
  final VoidCallback? onComplete;
  const _TodayItemTile({
    required this.item,
    this.isCompleting = false,
    this.onComplete,
  });

  Color get _priorityColor => switch (item['priority']?.toString()) {
        'high' => JC.cancelRed,
        'low' => JC.green500,
        _ => JC.amber400,
      };

  @override
  Widget build(BuildContext context) {
    final isReminder = item['type'] == 'reminder';
    final canComplete =
        !isReminder && item['id'] != null && onComplete != null;
    final timeLabel = UnifiedItemCard.formatTime(item['time']);
    final isOverdue = item['section'] == 'overdue';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              isOverdue ? JC.cancelRed.withOpacity(0.3) : JC.border,
          width: 0.8,
        ),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          if (canComplete)
            GestureDetector(
              onTap: isCompleting ? null : onComplete,
              child: SizedBox(
                width: 22,
                height: 22,
                child: isCompleting
                    ? CircularProgressIndicator(
                        strokeWidth: 2.2, color: JC.green500)
                    : Icon(Icons.radio_button_unchecked_rounded,
                        color: _priorityColor, size: 20),
              ),
            )
          else
            Icon(Icons.notifications_outlined,
                color: JC.amber400, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item['title']?.toString() ?? '',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 14,
                      fontFamily: 'Heebo'),
                ),
                if (timeLabel.isNotEmpty)
                  Text(timeLabel,
                      style: TextStyle(
                        color: isOverdue ? JC.cancelRed : JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        fontWeight: isOverdue
                            ? FontWeight.w600
                            : FontWeight.normal,
                      )),
              ],
            ),
          ),
          if (canComplete) ...[
            const SizedBox(width: 6),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _priorityColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
