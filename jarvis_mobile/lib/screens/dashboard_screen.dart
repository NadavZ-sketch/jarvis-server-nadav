import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

class DashboardScreen extends StatefulWidget {
  final AppSettings settings;
  /// Called when user taps "show all" on a section — navigates to that tab
  final ValueChanged<int>? onNavigate;

  const DashboardScreen({
    super.key,
    required this.settings,
    this.onNavigate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _tasks     = [];
  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _notes     = [];

  @override
  void initState() {
    super.initState();
    _loadCaches();
    _refresh();
  }

  Future<void> _loadCaches() async {
    final t = await CacheService.loadList('tasks');
    final r = await CacheService.loadList('reminders');
    final n = await CacheService.loadList('notes');
    if (mounted) {
      setState(() {
        if (t != null) _tasks     = t;
        if (r != null) _reminders = r;
        if (n != null) _notes     = n;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final api = ApiService(widget.settings);
      final results = await Future.wait([
        api.getTasks(),
        api.getReminders(),
        api.getNotes(),
      ]);
      if (mounted) {
        setState(() {
          _tasks     = results[0];
          _reminders = results[1];
          _notes     = results[2];
        });
      }
    } catch (_) {}
  }

  String _greeting() {
    final h = DateTime.now().hour;
    final name = widget.settings.userName.isNotEmpty
        ? widget.settings.userName
        : 'שם';
    if (h < 12) return 'בוקר טוב, $name 🌅';
    if (h < 17) return 'צהריים טובים, $name ☀️';
    if (h < 21) return 'ערב טוב, $name 🌆';
    return 'לילה טוב, $name 🌙';
  }

  String _todayLabel() {
    final now  = DateTime.now();
    const days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    final day  = days[now.weekday % 7];
    return 'יום $day, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  List<Map<String, dynamic>> get _activeTasks =>
      _tasks.where((t) => t['done'] != true).toList();

  bool _isOverdue(Map<String, dynamic> t) {
    final iso = t['due_date'];
    if (iso == null) return false;
    try { return DateTime.parse(iso.toString()).toLocal().isBefore(DateTime.now()); }
    catch (_) { return false; }
  }

  List<Map<String, dynamic>> get _upcomingReminders {
    final now = DateTime.now();
    return _reminders.where((r) {
      try {
        return DateTime.parse(r['scheduled_time'].toString()).isAfter(now);
      } catch (_) { return false; }
    }).take(3).toList();
  }

  String _formatDue(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt   = DateTime.parse(iso.toString()).toLocal();
      final now  = DateTime.now();
      final day  = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day == today) return 'היום';
      if (day == today.add(const Duration(days: 1))) return 'מחר';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  String _formatRemTime(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt   = DateTime.parse(iso.toString()).toLocal();
      final now  = DateTime.now();
      final day  = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final hhmm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (day == today) return 'היום $hhmm';
      if (day == today.add(const Duration(days: 1))) return 'מחר $hhmm';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $hhmm';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _activeTasks.where(_isOverdue).length;

    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          children: [
            Text(_greeting(),
                style: const TextStyle(
                    color: JC.textPrimary, fontSize: 16,
                    fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
                textDirection: TextDirection.rtl),
            Text(_todayLabel(),
                style: const TextStyle(
                    color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'),
                textDirection: TextDirection.rtl),
          ],
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: JC.blue400,
        backgroundColor: JC.surfaceAlt,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ── Quick actions ──────────────────────────────────────────────
            _QuickActions(settings: widget.settings, onAdded: _refresh),
            const SizedBox(height: 20),

            // ── Tasks ─────────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.checklist_rounded,
              title: 'משימות פתוחות',
              count: _activeTasks.length,
              badge: overdue > 0 ? '$overdue איחור' : null,
              onTap: () => widget.onNavigate?.call(2),
            ),
            if (_activeTasks.isEmpty)
              _EmptyCard(label: 'אין משימות פתוחות 🎉')
            else
              ..._activeTasks.take(3).map((t) {
                final overdueTile = _isOverdue(t);
                final dueLabel    = _formatDue(t['due_date']);
                return _DashTile(
                  leading: Icon(Icons.radio_button_unchecked_rounded,
                      color: JC.blue500, size: 18),
                  title: t['content']?.toString() ?? '',
                  subtitle: dueLabel.isNotEmpty ? dueLabel : null,
                  subtitleColor: overdueTile ? JC.cancelRed : JC.textMuted,
                );
              }),
            if (_activeTasks.length > 3)
              _ShowAllButton(
                  label: 'כל המשימות (${_activeTasks.length})',
                  onTap: () => widget.onNavigate?.call(2)),

            const SizedBox(height: 20),

            // ── Reminders ─────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.notifications_rounded,
              title: 'תזכורות קרובות',
              count: _upcomingReminders.length,
              onTap: () => widget.onNavigate?.call(3),
            ),
            if (_upcomingReminders.isEmpty)
              _EmptyCard(label: 'אין תזכורות קרובות')
            else
              ..._upcomingReminders.map((r) => _DashTile(
                    leading: const Icon(Icons.access_time_rounded,
                        color: JC.blue400, size: 18),
                    title: r['text']?.toString() ?? '',
                    subtitle: _formatRemTime(r['scheduled_time']),
                  )),
            if (_reminders.length > 3)
              _ShowAllButton(
                  label: 'כל התזכורות',
                  onTap: () => widget.onNavigate?.call(3)),

            const SizedBox(height: 20),

            // ── Notes ─────────────────────────────────────────────────────
            _SectionHeader(
              icon: Icons.notes_rounded,
              title: 'הערות אחרונות',
              count: _notes.length,
              onTap: () => widget.onNavigate?.call(4),
            ),
            if (_notes.isEmpty)
              _EmptyCard(label: 'אין הערות עדיין')
            else
              ..._notes.take(2).map((n) {
                final title   = n['title']?.toString() ?? '';
                final content = n['content']?.toString() ?? '';
                return _DashTile(
                  leading: const Icon(Icons.sticky_note_2_outlined,
                      color: JC.blue300, size: 18),
                  title: title.isNotEmpty ? title : content,
                  subtitle: title.isNotEmpty
                      ? (content.length > 60
                          ? '${content.substring(0, 60)}...'
                          : content)
                      : null,
                );
              }),
            if (_notes.length > 2)
              _ShowAllButton(
                  label: 'כל ההערות',
                  onTap: () => widget.onNavigate?.call(4)),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final String? badge;
  final VoidCallback? onTap;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, color: JC.blue400, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: JC.textPrimary, fontSize: 15,
                  fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
          const SizedBox(width: 6),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: JC.blue500.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: JC.blue400, fontSize: 11,
                      fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
            ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: JC.cancelRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(badge!,
                  style: TextStyle(
                      color: JC.cancelRed, fontSize: 11,
                      fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
            ),
          ],
          const Spacer(),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: const Text('הכל',
                  style: TextStyle(
                      color: JC.blue400, fontSize: 12, fontFamily: 'Heebo')),
            ),
        ],
      ),
    );
  }
}

// ─── Dash Tile ────────────────────────────────────────────────────────────────

class _DashTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;

  const _DashTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: JC.textPrimary, fontSize: 14,
                        fontFamily: 'Heebo')),
                if (subtitle != null)
                  Text(subtitle!,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          color: subtitleColor ?? JC.textMuted,
                          fontSize: 12,
                          fontFamily: 'Heebo')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String label;
  const _EmptyCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Text(label,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
              color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo')),
    );
  }
}

class _ShowAllButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ShowAllButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
              color: JC.blue400, fontSize: 12, fontFamily: 'Heebo'),
        ),
      ),
    );
  }
}

// ─── Quick Actions row ────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final AppSettings settings;
  final VoidCallback onAdded;
  const _QuickActions({required this.settings, required this.onAdded});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _QABtn(
          icon: Icons.add_task_rounded,
          label: '+ משימה',
          onTap: () => _showTaskSheet(context),
        ),
        const SizedBox(width: 10),
        _QABtn(
          icon: Icons.notification_add_outlined,
          label: '+ תזכורת',
          onTap: () => _showReminderSheet(context),
        ),
        const SizedBox(width: 10),
        _QABtn(
          icon: Icons.note_add_outlined,
          label: '+ הערה',
          onTap: () => _showNoteSheet(context),
        ),
      ],
    );
  }

  void _showTaskSheet(BuildContext context) {
    final ctrl = TextEditingController();
    _sheet(context, 'משימה חדשה', ctrl, () async {
      final val = ctrl.text.trim();
      if (val.isEmpty) return;
      await ApiService(settings).addTask(val);
      onAdded();
    });
  }

  void _showNoteSheet(BuildContext context) {
    final ctrl = TextEditingController();
    _sheet(context, 'הערה חדשה', ctrl, () async {
      final val = ctrl.text.trim();
      if (val.isEmpty) return;
      await ApiService(settings).addNote(val);
      onAdded();
    });
  }

  void _showReminderSheet(BuildContext context) {
    final ctrl = TextEditingController();
    _sheet(context, 'תזכורת חדשה', ctrl, () async {
      final val = ctrl.text.trim();
      if (val.isEmpty) return;
      final when = DateTime.now().add(const Duration(hours: 1));
      await ApiService(settings).addReminder(val, when.toIso8601String());
      onAdded();
    }, hint: 'מה להזכיר לך? (בעוד שעה)');
  }

  void _sheet(BuildContext context, String title, TextEditingController ctrl,
      Future<void> Function() onSave, {String hint = 'תוכן...'}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title,
                style: const TextStyle(
                    color: JC.textPrimary, fontSize: 16,
                    fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              textDirection: TextDirection.rtl,
              autofocus: true,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                filled: true, fillColor: JC.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JC.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JC.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JC.blue500)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: JC.blue500,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try { await onSave(); } catch (_) {}
                },
                child: const Text('הוסף',
                    style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QABtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QABtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: Column(
            children: [
              Icon(icon, color: JC.blue400, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: const TextStyle(
                      color: JC.textSecondary, fontSize: 12,
                      fontFamily: 'Heebo')),
            ],
          ),
        ),
      ),
    );
  }
}
