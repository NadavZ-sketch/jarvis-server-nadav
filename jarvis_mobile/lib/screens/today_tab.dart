import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/markdown_lite.dart';

class TodayTab extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback? onGoToTasks;
  final VoidCallback? onGoToReminders;
  const TodayTab({
    super.key,
    required this.settings,
    this.onGoToTasks,
    this.onGoToReminders,
  });

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _todayMsg;
  bool _loading = true;
  String? _error;
  final Set<String> _completing = {};

  // ── Weekly briefing ──
  String? _briefing;
  bool _briefingLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _fetch();
    // Briefing is started after _fetch() completes so _items is populated
    // when _fetchBriefing() builds the prompt.
  }

  // Cache key includes the focus so changing the focus invalidates the cache.
  String get _briefingCacheKey =>
      'today_briefing::${widget.settings.todayBriefingFocus.trim()}';

  Future<void> _loadBriefingCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_briefingCacheKey);
      final tsStr = prefs.getString('${_briefingCacheKey}_ts');
      if (text != null && tsStr != null) {
        final ts = DateTime.tryParse(tsStr);
        if (ts != null && DateTime.now().difference(ts).inDays < 7) {
          if (mounted) setState(() => _briefing = text);
          return;
        }
      }
      // No fresh cache → generate one.
      _fetchBriefing();
    } catch (_) {}
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
      // Avoid Hebrew task/reminder root words ("משימ", "תזכור") in the prompt
      // prefix — they trigger the keyword router on older server builds.
      final message =
          'בריפינג שבועי קצר בעברית. הנושאים לשבוע: ${titles.isEmpty ? 'לא נמצאו פריטים פתוחים' : titles}. '
          'תן סיכום ממוקד של מה חשוב השבוע ב-3 נקודות מקסימום.$focusLine';
      final result = await ApiService(widget.settings)
          .askJarvis(message, widget.settings, intent: 'chat');
      final raw = ((result['answer'] as String?) ?? '').trim();
      final looksLikeError = (raw.contains('בעיה') && raw.contains('נסה שוב')) ||
          raw.contains('לא הצלחתי') ||
          raw.contains('לא ניתן');
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
      lines.add('• הרשימה נקייה — זמן טוב לתכנן את השבוע הבא');
      lines.add('• הגדר יעד ברור אחד לשבוע זה');
    }
    lines.add('• קבע זמן קבוע לכל פריט ועמוד בו');
    return lines.join('\n');
  }

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('today_items');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('משימה הושלמה ✓',
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary)),
        backgroundColor: JC.surfaceAlt,
        duration: const Duration(seconds: 2),
      ));
    } catch (_) {
      if (mounted) setState(() => _completing.remove(id));
    }
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final api = ApiService(widget.settings);
      final results = await Future.wait([
        api.getStats(),
        api.getTodayItems(),
        api.getTodayMessage(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats    = results[0] as Map<String, dynamic>;
        _items    = List<Map<String, dynamic>>.from(results[1] as List);
        _todayMsg = results[2] as Map<String, dynamic>;
        _loading  = false;
        _error    = null;
      });
      CacheService.saveList('today_items', _items);
      // Start briefing now that _items is populated.
      if (widget.settings.todayBriefingEnabled && _briefing == null) {
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

    final overdue   = _section('overdue');
    final today     = _section('today');
    final reminders = _section('reminder');
    final isEmpty   = overdue.isEmpty && today.isEmpty && reminders.isEmpty;

    return RefreshIndicator(
      color: JC.blue400,
      backgroundColor: JC.surfaceAlt,
      onRefresh: _fetch,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _JarvisMessageCard(data: _todayMsg, loading: _stats == null),
          const SizedBox(height: 10),
          _StatsHeader(
            stats: _stats,
            onGoToTasks: widget.onGoToTasks,
            onGoToReminders: widget.onGoToReminders,
          ),
          const SizedBox(height: 16),
          if (widget.settings.todayBriefingEnabled) ...[
            _WeeklyBriefingCard(
              text: _briefing,
              loading: _briefingLoading,
              onRefresh: _fetchBriefing,
            ),
            const SizedBox(height: 16),
          ],
          if (isEmpty)
            EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'הכל נקי להיום! 🌟',
              subtitle: 'אין משימות פתוחות — כל הכבוד!',
            )
          else ...[
            if (overdue.isNotEmpty) ...[
              _SectionHeader(label: '⚠️ מאוחרות (${overdue.length})'),
              ...overdue.asMap().entries.map((e) => AnimatedListItem(
                index: e.key,
                child: _TodayItemTile(
  item: e.value,
  isCompleting: _completing.contains(e.value['id']?.toString() ?? ''),
  onComplete: () => _completeTask(e.value),
),
              )),
              const SizedBox(height: 8),
            ],
            if (today.isNotEmpty) ...[
              _SectionHeader(label: '📅 להיום (${today.length})'),
              ...today.asMap().entries.map((e) => AnimatedListItem(
                index: e.key,
                child: _TodayItemTile(
  item: e.value,
  isCompleting: _completing.contains(e.value['id']?.toString() ?? ''),
  onComplete: () => _completeTask(e.value),
),
              )),
              const SizedBox(height: 8),
            ],
            if (reminders.isNotEmpty) ...[
              _SectionHeader(label: '🔔 תזכורות (${reminders.length})'),
              ...reminders.asMap().entries.map((e) => AnimatedListItem(
                index: e.key,
                child: _TodayItemTile(
  item: e.value,
  isCompleting: _completing.contains(e.value['id']?.toString() ?? ''),
  onComplete: () => _completeTask(e.value),
),
              )),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Jarvis message card ──────────────────────────────────────────────────────

class _JarvisMessageCard extends StatelessWidget {
  final Map<String, dynamic>? data;
  final bool loading;
  const _JarvisMessageCard({required this.data, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF0F1929)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JC.indigo500.withValues(alpha: 0.3), width: 0.8),
      ),
      child: loading || data == null
          ? Row(
              textDirection: TextDirection.rtl,
              children: [
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(height: 14, width: 200,
                          decoration: BoxDecoration(color: JC.border, borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 6),
                      Container(height: 12, width: 140,
                          decoration: BoxDecoration(color: JC.border, borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  data!['emoji']?.toString() ?? '☀️',
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data!['message']?.toString() ?? '',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 14,
                      fontFamily: 'Heebo',
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Stats header ─────────────────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final VoidCallback? onGoToTasks;
  final VoidCallback? onGoToReminders;
  const _StatsHeader(
      {required this.stats, this.onGoToTasks, this.onGoToReminders});

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return Row(
        children: List.generate(
            3,
            (_) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 64,
                    decoration: BoxDecoration(
                        color: JC.surfaceAlt,
                        borderRadius: BorderRadius.circular(12)),
                  ),
                )),
      );
    }

    final tasks     = stats!['tasks']     as Map<String, dynamic>? ?? {};
    final reminders = stats!['reminders'] as Map<String, dynamic>? ?? {};
    final total   = (tasks['total']   as num?)?.toInt() ?? 0;
    final done    = (tasks['done']    as num?)?.toInt() ?? 0;
    final pending = (tasks['pending'] as num?)?.toInt() ?? 0;
    final active  = (reminders['active'] as num?)?.toInt() ?? 0;
    final pct     = total > 0 ? (done / total * 100).round() : 0;

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _StatCard(
          value: '$pct%',
          label: 'הושלם',
          color: JC.blue400,
          onTap: onGoToTasks,
          icon: Icons.check_circle_outline_rounded,
        ),
        _StatCard(
          value: '$pending',
          label: 'ממתינות',
          color: JC.amber400,
          onTap: onGoToTasks,
          icon: Icons.list_alt_rounded,
        ),
        _StatCard(
          value: '$active',
          label: 'תזכורות',
          color: JC.textSecondary,
          onTap: onGoToReminders,
          icon: Icons.notifications_outlined,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final IconData? icon;
  const _StatCard(
      {required this.value,
      required this.label,
      required this.color,
      this.onTap,
      this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: onTap != null
                    ? color.withValues(alpha: 0.25)
                    : JC.border,
                width: 0.8),
            boxShadow: onTap != null
                ? [
                    BoxShadow(
                        color: color.withOpacity(0.07),
                        blurRadius: 10,
                        offset: const Offset(0, 2))
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo')),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 10, color: JC.textMuted),
                    const SizedBox(width: 3),
                  ],
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 10,
                          fontFamily: 'Heebo')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: JC.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'Heebo',
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── Today item tile ──────────────────────────────────────────────────────────

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
    'low'  => JC.green500,
    _      => JC.amber400,
  };

  String _formatTime(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt    = DateTime.parse(iso.toString()).toLocal();
      final now   = DateTime.now();
      final day   = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final hhmm  = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (day == today) return 'היום $hhmm';
      if (day == today.subtract(const Duration(days: 1))) return 'אתמול';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $hhmm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReminder = item['type'] == 'reminder';
    final hasId      = item['id'] != null;
    final timeLabel  = _formatTime(item['time']);
    final isOverdue  = item['section'] == 'overdue';
    final canComplete = !isReminder && hasId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue ? JC.cancelRed.withValues(alpha: 0.35) : JC.border,
          width: 0.8,
        ),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          // Leading icon / complete button
          if (canComplete)
            GestureDetector(
              onTap: isCompleting ? null : onComplete,
              child: SizedBox(
                width: 24,
                height: 24,
                child: isCompleting
                    ? CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: JC.green500,
                      )
                    : Icon(
                        Icons.radio_button_unchecked_rounded,
                        color: _priorityColor,
                        size: 22,
                      ),
              ),
            )
          else
            Icon(
              Icons.notifications_outlined,
              color: JC.amber400,
              size: 20,
            ),
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
                    fontFamily: 'Heebo',
                  ),
                ),
                if (timeLabel.isNotEmpty)
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: isOverdue ? JC.cancelRed : JC.textMuted,
                      fontSize: 11,
                      fontFamily: 'Heebo',
                      fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
          if (canComplete) ...[
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
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

// ─── Weekly briefing card ───────────────────────────────────────────────────────

class _WeeklyBriefingCard extends StatelessWidget {
  final String? text;
  final bool loading;
  final VoidCallback onRefresh;

  const _WeeklyBriefingCard({
    required this.text,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // ClipRRect owns the border-radius; the inner Container uses a non-uniform
    // Border without a radius — mixing the two in BoxDecoration causes Flutter
    // to skip painting the decoration entirely (and sometimes the child too).
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          border: Border(
            right: BorderSide(color: JC.blue500, width: 3),
            top: BorderSide(color: JC.border.withValues(alpha: 0.7), width: 0.8),
            left: BorderSide(color: JC.border.withValues(alpha: 0.7), width: 0.8),
            bottom: BorderSide(color: JC.border.withValues(alpha: 0.7), width: 0.8),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Icon(Icons.insights_rounded, size: 18, color: JC.blue400),
                const SizedBox(width: 8),
                Text(
                  'בריפינג שבועי',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  ),
                ),
                const Spacer(),
                if (loading)
                  const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  GestureDetector(
                    onTap: onRefresh,
                    child: Icon(Icons.refresh_rounded, size: 18, color: JC.textMuted),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (text != null && text!.trim().isNotEmpty)
              MarkdownLite(
                text: text!,
                textDirection: TextDirection.rtl,
                baseStyle: TextStyle(
                  color: JC.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                  fontFamily: 'Heebo',
                ),
              )
            else
              Text(
                loading ? 'מכין בריפינג שבועי...' : 'לחץ על ריענון לטעינת הבריפינג.',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: JC.textSecondary,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
