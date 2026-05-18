import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';

class TodayTab extends StatefulWidget {
  final AppSettings settings;
  const TodayTab({super.key, required this.settings});

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _todayMsg;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCache();
    _fetch();
  }

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('today_items');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
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
          _StatsHeader(stats: _stats),
          const SizedBox(height: 16),
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
                child: _TodayItemTile(item: e.value, context: context),
              )),
              const SizedBox(height: 8),
            ],
            if (today.isNotEmpty) ...[
              _SectionHeader(label: '📅 להיום (${today.length})'),
              ...today.asMap().entries.map((e) => AnimatedListItem(
                index: e.key,
                child: _TodayItemTile(item: e.value, context: context),
              )),
              const SizedBox(height: 8),
            ],
            if (reminders.isNotEmpty) ...[
              _SectionHeader(label: '🔔 תזכורות (${reminders.length})'),
              ...reminders.asMap().entries.map((e) => AnimatedListItem(
                index: e.key,
                child: _TodayItemTile(item: e.value, context: context),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                    style: const TextStyle(
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
  const _StatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null) {
      return Row(
        children: List.generate(3, (_) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 64,
            decoration: BoxDecoration(
              color: JC.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        )),
      );
    }

    final tasks     = stats!['tasks']     as Map<String, dynamic>? ?? {};
    final reminders = stats!['reminders'] as Map<String, dynamic>? ?? {};
    final total     = (tasks['total']   as num?)?.toInt() ?? 0;
    final done      = (tasks['done']    as num?)?.toInt() ?? 0;
    final pending   = (tasks['pending'] as num?)?.toInt() ?? 0;
    final active    = (reminders['active'] as num?)?.toInt() ?? 0;
    final pct       = total > 0 ? (done / total * 100).round() : 0;

    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _StatCard(value: '$pct%',    label: 'הושלם',          color: JC.blue400),
        _StatCard(value: '$pending', label: 'ממתינות',         color: JC.amber400),
        _StatCard(value: '$active',  label: 'תזכורות פעילות', color: JC.textSecondary),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCard({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(color: color, fontSize: 20,
                    fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: JC.textMuted,
                    fontSize: 10, fontFamily: 'Heebo')),
          ],
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
        style: const TextStyle(
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
  final BuildContext context;
  const _TodayItemTile({required this.item, required this.context});

  Color get _priorityColor => switch (item['priority']?.toString()) {
    'high'   => JC.cancelRed,
    'low'    => JC.green500,
    _        => JC.amber400,
  };

  String _formatTime(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt  = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final timeStr = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      if (day == today) return 'היום $timeStr';
      if (day == today.subtract(const Duration(days: 1))) return 'אתמול';
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} $timeStr';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final isReminder = item['type'] == 'reminder';
    final timeLabel  = _formatTime(item['time']);
    final isOverdue  = item['section'] == 'overdue';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOverdue
              ? JC.cancelRed.withValues(alpha: 0.35)
              : JC.border,
          width: 0.8,
        ),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(
            isReminder ? Icons.notifications_outlined : Icons.check_circle_outline_rounded,
            color: isReminder ? JC.amber400 : JC.blue500,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title']?.toString() ?? '',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
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
          if (!isReminder) ...[
            const SizedBox(width: 6),
            Container(
              width: 8, height: 8,
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
