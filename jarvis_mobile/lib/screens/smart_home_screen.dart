import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/surface_card.dart';
import '../widgets/loading_skeleton.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class _DashboardData {
  final Map<String, dynamic> heroCard;
  final List<Map<String, dynamic>> tasks;
  final int tasksBadge;
  final List<Map<String, dynamic>> reminders;
  final int remindersBadge;
  final String? weatherSummary;
  final String? newsSummary;
  final String slot;

  const _DashboardData({
    required this.heroCard,
    required this.tasks,
    required this.tasksBadge,
    required this.reminders,
    required this.remindersBadge,
    this.weatherSummary,
    this.newsSummary,
    required this.slot,
  });

  static _DashboardData empty() => _DashboardData(
        heroCard: {},
        tasks: [],
        tasksBadge: 0,
        reminders: [],
        remindersBadge: 0,
        slot: 'morning',
      );

  static _DashboardData fromJson(Map<String, dynamic> json) {
    final widgets = List<Map<String, dynamic>>.from(json['widgets'] ?? []);
    Map<String, dynamic> w(String t) =>
        widgets.firstWhere((e) => e['type'] == t, orElse: () => {});

    final tasksW     = w('tasks');
    final remW       = w('reminders');
    final weatherW   = w('weather');
    final newsW      = w('news');

    return _DashboardData(
      heroCard:       (json['heroCard'] as Map<String, dynamic>?) ?? {},
      tasks:          List<Map<String, dynamic>>.from(tasksW['data'] ?? []),
      tasksBadge:     (tasksW['badge'] as num?)?.toInt() ?? 0,
      reminders:      List<Map<String, dynamic>>.from(remW['data'] ?? []),
      remindersBadge: (remW['badge'] as num?)?.toInt() ?? 0,
      weatherSummary: (weatherW['data'] as Map?)?.tryGet('summary'),
      newsSummary:    (newsW['data']    as Map?)?.tryGet('summary'),
      slot:           json['slot']?.toString() ?? 'morning',
    );
  }
}

extension _MapX on Map {
  String? tryGet(String key) {
    final v = this[key];
    return v is String ? v : null;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class SmartHomeScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onNavigate;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenChat;

  const SmartHomeScreen({
    super.key,
    required this.settings,
    this.onNavigate,
    this.onOpenDrawer,
    this.onOpenChat,
  });

  @override
  State<SmartHomeScreen> createState() => _SmartHomeScreenState();
}

class _SmartHomeScreenState extends State<SmartHomeScreen>
    with SingleTickerProviderStateMixin {
  _DashboardData _data = _DashboardData.empty();
  bool _loading = true;
  bool _offline = false;

  late final AnimationController _heroAnim;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;

  static const _cacheKey = 'dashboard_context';

  @override
  void initState() {
    super.initState();
    _heroAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _heroFade = CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _heroAnim, curve: Curves.easeOut));

    _loadCache();
    _refresh();
  }

  @override
  void dispose() {
    _heroAnim.dispose();
    super.dispose();
  }

  Future<void> _loadCache() async {
    final cached = await CacheService.load(_cacheKey);
    if (cached is Map<String, dynamic> && mounted) {
      setState(() {
        _data = _DashboardData.fromJson(cached);
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final api = ApiService(widget.settings);
      final json = await api.getDashboardContext();
      if (!mounted) return;
      await CacheService.save(_cacheKey, json);
      final next = _DashboardData.fromJson(json);
      setState(() {
        _data = next;
        _loading = false;
        _offline = false;
      });
      _heroAnim.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _greetingLine() {
    final name = widget.settings.userName.isNotEmpty
        ? widget.settings.userName
        : '';
    const greetings = {
      'morning':      'בוקר טוב',
      'late_morning': 'בוקר טוב',
      'noon':         'צהריים טובים',
      'afternoon':    'שלום',
      'evening':      'ערב טוב',
      'night':        'לילה טוב',
    };
    final g = greetings[_data.slot] ?? 'שלום';
    return name.isNotEmpty ? '$g, $name' : g;
  }

  String _todayLabel() {
    final now = DateTime.now();
    const days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    final day = days[now.weekday % 7];
    return 'יום $day, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  Color _urgencyColor(Map<String, dynamic> r) {
    final iso = r['scheduled_time']?.toString();
    if (iso == null) return JC.textMuted;
    try {
      final dt  = DateTime.parse(iso).toLocal();
      final min = dt.difference(DateTime.now()).inMinutes;
      if (min < 30)  return JC.cancelRed;
      if (min < 60)  return JC.amber400;
    } catch (_) {}
    return JC.green500;
  }

  String _fmtTime(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt    = DateTime.parse(iso.toString()).toLocal();
      final today = DateTime.now();
      final hhmm  = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (dt.day == today.day) return 'היום $hhmm';
      if (dt.day == today.day + 1) return 'מחר $hhmm';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $hhmm';
    } catch (_) {
      return '';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        color: JC.blue400,
        backgroundColor: JC.surfaceAlt,
        onRefresh: _refresh,
        child: _loading && _data.heroCard.isEmpty
            ? LoadingSkeleton(itemCount: 4, itemHeight: 80)
            : _buildBody(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: widget.onOpenDrawer != null
          ? IconButton(
              icon: Icon(Icons.menu_rounded, color: JC.textSecondary, size: 22),
              onPressed: widget.onOpenDrawer,
            )
          : null,
      title: Column(
        children: [
          Text(
            _greetingLine(),
            style: TextStyle(
                color: JC.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Heebo'),
            textDirection: TextDirection.rtl,
          ),
          Text(
            _todayLabel(),
            style: TextStyle(
                color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        if (_offline)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Icon(Icons.wifi_off_rounded,
                color: JC.amber400, size: 18),
          ),
      ],
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (_offline) _OfflineBanner(),
        const SizedBox(height: 8),

        // ── Hero Card ──────────────────────────────────────────────────────
        _buildHeroCard(),
        const SizedBox(height: 16),

        // ── Secondary row: Tasks + Reminders ──────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _TasksWidget(
              tasks: _data.tasks,
              badge: _data.tasksBadge,
              onShowAll: () => widget.onNavigate?.call(2),
            )),
            const SizedBox(width: 12),
            Expanded(child: _RemindersWidget(
              reminders: _data.reminders,
              badge: _data.remindersBadge,
              urgencyColor: _urgencyColor,
              formatTime: _fmtTime,
              onShowAll: () => widget.onNavigate?.call(2),
            )),
          ],
        ),
        const SizedBox(height: 16),

        // ── Tertiary strip: Weather + News ─────────────────────────────────
        if (_data.weatherSummary != null || _data.newsSummary != null)
          _TertiaryStrip(
            weatherSummary: _data.weatherSummary,
            newsSummary: _data.newsSummary,
          ),

        const SizedBox(height: 16),

        // ── Quick actions ──────────────────────────────────────────────────
        _QuickActions(settings: widget.settings, onAdded: _refresh),
        const SizedBox(height: 12),

        // ── Chat shortcut ──────────────────────────────────────────────────
        _ChatShortcut(onTap: widget.onOpenChat ?? () => widget.onNavigate?.call(1)),
      ],
    );
  }

  Widget _buildHeroCard() {
    final text = _data.heroCard['text']?.toString() ?? '';
    final confidence = (_data.heroCard['confidence'] as num?)?.toDouble() ?? 0.0;

    if (text.isEmpty) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _heroFade,
      child: SlideTransition(
        position: _heroSlide,
        child: SurfaceCard(
          radius: 18,
          padding: const EdgeInsets.all(20),
          color: JC.blue500.withValues(alpha: 0.08),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: confidence >= 0.65 ? JC.blue400 : JC.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ג׳רביס',
                    style: TextStyle(
                        color: JC.blue400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Heebo',
                        letterSpacing: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 15,
                    height: 1.55,
                    fontFamily: 'Heebo'),
              ),
              const SizedBox(height: 14),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  _HeroAction(
                    label: 'שאל ג׳רביס',
                    isPrimary: true,
                    onTap: widget.onOpenChat ?? () => widget.onNavigate?.call(1),
                  ),
                  const SizedBox(width: 8),
                  _HeroAction(
                    label: 'משימות',
                    isPrimary: false,
                    onTap: () => widget.onNavigate?.call(2),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Hero Action Button ───────────────────────────────────────────────────────

class _HeroAction extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _HeroAction({
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? JC.blue500 : JC.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary ? null : Border.all(color: JC.border),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: isPrimary ? Colors.white : JC.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'Heebo'),
        ),
      ),
    );
  }
}

// ─── Offline Banner ───────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(Icons.wifi_off_rounded, color: JC.amber400, size: 16),
          const SizedBox(width: 8),
          Text(
            'אין חיבור לאינטרנט — מציג נתונים שמורים',
            textDirection: TextDirection.rtl,
            style: TextStyle(
                color: JC.amber400, fontSize: 12, fontFamily: 'Heebo'),
          ),
        ],
      ),
    );
  }
}

// ─── Tasks Widget ─────────────────────────────────────────────────────────────

class _TasksWidget extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  final int badge;
  final VoidCallback onShowAll;

  const _TasksWidget({
    required this.tasks,
    required this.badge,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _WidgetHeader(
            icon: Icons.checklist_rounded,
            title: 'משימות',
            badge: badge,
            onTap: onShowAll,
          ),
          const SizedBox(height: 8),
          if (tasks.isEmpty)
            _MiniEmpty(label: 'הכל טוב 🎉')
          else
            ...tasks.map((t) => _MiniRow(
                  icon: Icons.radio_button_unchecked_rounded,
                  iconColor: t['priority'] == 'high' ? JC.cancelRed : JC.blue500,
                  label: t['content']?.toString() ?? '',
                )),
          if (badge > 0)
            _MoreChip(count: badge, onTap: onShowAll),
        ],
      ),
    );
  }
}

// ─── Reminders Widget ─────────────────────────────────────────────────────────

class _RemindersWidget extends StatelessWidget {
  final List<Map<String, dynamic>> reminders;
  final int badge;
  final Color Function(Map<String, dynamic>) urgencyColor;
  final String Function(dynamic) formatTime;
  final VoidCallback onShowAll;

  const _RemindersWidget({
    required this.reminders,
    required this.badge,
    required this.urgencyColor,
    required this.formatTime,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _WidgetHeader(
            icon: Icons.notifications_rounded,
            title: 'תזכורות',
            badge: badge,
            onTap: onShowAll,
          ),
          const SizedBox(height: 8),
          if (reminders.isEmpty)
            _MiniEmpty(label: 'אין תזכורות')
          else
            ...reminders.map((r) => _MiniRow(
                  icon: Icons.access_time_rounded,
                  iconColor: urgencyColor(r),
                  label: r['text']?.toString() ?? '',
                  sub: formatTime(r['scheduled_time']),
                )),
          if (badge > 0)
            _MoreChip(count: badge, onTap: onShowAll),
        ],
      ),
    );
  }
}

// ─── Widget Header ────────────────────────────────────────────────────────────

class _WidgetHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int badge;
  final VoidCallback onTap;

  const _WidgetHeader({
    required this.icon,
    required this.title,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, color: JC.blue400, size: 15),
          const SizedBox(width: 5),
          Text(
            title,
            style: TextStyle(
                color: JC.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Heebo'),
          ),
          const Spacer(),
          if (badge > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: JC.blue500.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '+$badge',
                style: TextStyle(
                    color: JC.blue400,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Heebo'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Mini Row ─────────────────────────────────────────────────────────────────

class _MiniRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? sub;

  const _MiniRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: iconColor, size: 13),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  label,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 12,
                      fontFamily: 'Heebo'),
                ),
                if (sub != null && sub!.isNotEmpty)
                  Text(
                    sub!,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 10,
                        fontFamily: 'Heebo'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniEmpty extends StatelessWidget {
  final String label;
  const _MiniEmpty({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: TextStyle(
            color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _MoreChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '+ $count נוספים',
          textDirection: TextDirection.rtl,
          style: TextStyle(
              color: JC.blue400,
              fontSize: 11,
              fontFamily: 'Heebo'),
        ),
      ),
    );
  }
}

// ─── Tertiary Strip ───────────────────────────────────────────────────────────

class _TertiaryStrip extends StatelessWidget {
  final String? weatherSummary;
  final String? newsSummary;

  const _TertiaryStrip({this.weatherSummary, this.newsSummary});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true, // RTL scroll starts from right
        children: [
          if (weatherSummary != null)
            _StripCard(
              icon: Icons.wb_sunny_outlined,
              iconColor: JC.amber400,
              label: 'מזג אוויר',
              text: weatherSummary!,
            ),
          if (newsSummary != null)
            _StripCard(
              icon: Icons.newspaper_rounded,
              iconColor: JC.blue300,
              label: 'חדשות',
              text: newsSummary!,
            ),
        ],
      ),
    );
  }
}

class _StripCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String text;

  const _StripCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      margin: const EdgeInsetsDirectional.only(end: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      radius: 14,
      child: SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Icon(icon, color: iconColor, size: 14),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo'),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              text,
              textDirection: TextDirection.rtl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 12,
                  height: 1.4,
                  fontFamily: 'Heebo'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final AppSettings settings;
  final VoidCallback onAdded;

  const _QuickActions({required this.settings, required this.onAdded});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        _QABtn(icon: Icons.add_task_rounded,          label: '+ משימה',  onTap: () => _taskSheet(context)),
        const SizedBox(width: 10),
        _QABtn(icon: Icons.notification_add_outlined, label: '+ תזכורת', onTap: () => _reminderSheet(context)),
        const SizedBox(width: 10),
        _QABtn(icon: Icons.note_add_outlined,         label: '+ הערה',   onTap: () => _noteSheet(context)),
      ],
    );
  }

  void _taskSheet(BuildContext ctx) {
    final c = TextEditingController();
    _sheet(ctx, 'משימה חדשה', c, () async {
      final v = c.text.trim();
      if (v.isEmpty) return;
      await ApiService(settings).addTask(v);
      onAdded();
    });
  }

  void _reminderSheet(BuildContext ctx) {
    final c = TextEditingController();
    _sheet(ctx, 'תזכורת חדשה', c, () async {
      final v = c.text.trim();
      if (v.isEmpty) return;
      final when = DateTime.now().add(const Duration(hours: 1));
      await ApiService(settings).addReminder(v, when.toIso8601String());
      onAdded();
    }, hint: 'מה להזכיר לך? (בעוד שעה)');
  }

  void _noteSheet(BuildContext ctx) {
    final c = TextEditingController();
    _sheet(ctx, 'הערה חדשה', c, () async {
      final v = c.text.trim();
      if (v.isEmpty) return;
      await ApiService(settings).addNote(v);
      onAdded();
    });
  }

  void _sheet(
    BuildContext ctx,
    String title,
    TextEditingController ctrl,
    Future<void> Function() onSave, {
    String hint = 'תוכן...',
  }) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(c).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Heebo')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              textDirection: TextDirection.rtl,
              autofocus: true,
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                filled: true,
                fillColor: JC.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: JC.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: JC.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: JC.blue500)),
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
                  Navigator.pop(c);
                  try { await onSave(); } catch (_) {}
                },
                child: const Text('הוסף',
                    style: TextStyle(
                        fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
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
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
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
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Heebo')),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Chat Shortcut ────────────────────────────────────────────────────────────

class _ChatShortcut extends StatelessWidget {
  final VoidCallback onTap;
  const _ChatShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(Icons.auto_awesome_rounded, color: JC.blue400, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'שאל את ג׳רביס...',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: JC.textMuted,
                    fontSize: 14,
                    fontFamily: 'Heebo'),
              ),
            ),
            Icon(Icons.arrow_back_ios_new_rounded,
                color: JC.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}
