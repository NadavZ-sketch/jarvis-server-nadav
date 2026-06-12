import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';

class CalendarScreen extends StatefulWidget {
  final AppSettings settings;
  const CalendarScreen({super.key, required this.settings});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused  = DateTime.now();
  DateTime _selected = DateTime.now();
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _loading = true;
  CalendarFormat _format = CalendarFormat.week;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  DateTime _dateOnly(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    try {
      final allEvents = await ApiService(widget.settings).getCalendarEvents();
      final map = <DateTime, List<Map<String, dynamic>>>{};
      for (final e in allEvents) {
        final raw = e['date'];
        if (raw == null) continue;
        try {
          final day = _dateOnly(DateTime.parse(raw.toString()));
          map.putIfAbsent(day, () => []).add(e);
        } catch (_) {}
      }
      if (mounted) setState(() { _events = map; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) =>
      _events[_dateOnly(day)] ?? [];

  @override
  Widget build(BuildContext context) {
    final dayEvents = _eventsForDay(_selected);

    return Scaffold(
      backgroundColor: JC.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context),
        backgroundColor: JC.blue500,
        elevation: 2,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Column(
        children: [
          _CalendarHeader(
            focused: _focused,
            format: _format,
            onToggleFormat: () => setState(() =>
              _format = _format == CalendarFormat.week
                  ? CalendarFormat.month
                  : CalendarFormat.week),
            onRefresh: _loadEvents,
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: JC.border, width: 0.8),
            ),
            child: TableCalendar(
              locale: 'he_IL',
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2027, 12, 31),
              focusedDay: _focused,
              calendarFormat: _format,
              availableCalendarFormats: const {
                CalendarFormat.month: 'חודש',
                CalendarFormat.week: 'שבוע',
              },
              selectedDayPredicate: (d) => isSameDay(d, _selected),
              eventLoader: _eventsForDay,
              startingDayOfWeek: StartingDayOfWeek.sunday,
              calendarBuilders: CalendarBuilders(
                markerBuilder: (ctx, day, events) =>
                    _buildMarkers(day, events.cast<Map<String, dynamic>>()),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: _format == CalendarFormat.month,
                defaultTextStyle: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
                weekendTextStyle: TextStyle(
                    color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13),
                outsideTextStyle: TextStyle(
                    color: JC.textMuted.withOpacity(0.4),
                    fontFamily: 'Heebo', fontSize: 13),
                todayDecoration: BoxDecoration(
                    color: JC.blue500.withOpacity(0.25),
                    shape: BoxShape.circle),
                todayTextStyle: TextStyle(
                    color: JC.blue400, fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700, fontSize: 13),
                selectedDecoration: BoxDecoration(
                    color: JC.blue500, shape: BoxShape.circle),
                selectedTextStyle: const TextStyle(
                    color: Colors.white, fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700, fontSize: 13),
                markersMaxCount: 0,
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextStyle: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600, fontSize: 14),
                leftChevronIcon: Icon(Icons.chevron_left, color: JC.textMuted, size: 20),
                rightChevronIcon: Icon(Icons.chevron_right, color: JC.textMuted, size: 20),
                headerPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                    color: JC.textMuted, fontFamily: 'Heebo',
                    fontSize: 11, fontWeight: FontWeight.w600),
                weekendStyle: TextStyle(
                    color: JC.textMuted, fontFamily: 'Heebo',
                    fontSize: 11, fontWeight: FontWeight.w600),
              ),
              onDaySelected: (selected, focused) =>
                  setState(() { _selected = selected; _focused = focused; }),
              onPageChanged: (focused) =>
                  setState(() => _focused = focused),
              onFormatChanged: (f) => setState(() => _format = f),
            ),
          ),
          const SizedBox(height: 8),
          _DayHeader(date: _selected, count: dayEvents.length),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: JC.blue400))
                : dayEvents.isEmpty
                    ? _EmptyDay()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        itemCount: dayEvents.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _EventTile(event: dayEvents[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkers(DateTime day, List<Map<String, dynamic>> events) {
    if (events.isEmpty) return const SizedBox.shrink();
    final types = events.map((e) => e['type']?.toString() ?? '').toSet();
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (types.contains('task'))    _Dot(color: JC.blue400),
        if (types.contains('reminder')) _Dot(color: JC.amber400),
        if (types.contains('calendar')) _Dot(color: JC.indigo500),
      ],
    );
  }

  Future<void> _showAddSheet(BuildContext ctx) async {
    final textCtrl = TextEditingController();
    DateTime date = _selected;
    TimeOfDay time = const TimeOfDay(hour: 9, minute: 0);
    String type = 'reminder';

    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 24,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: JC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('הוספה ליום ${_formatShortDate(date)}',
                  style: TextStyle(color: JC.textPrimary, fontSize: 17,
                      fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
              const SizedBox(height: 16),
              // Type toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _TypeToggle(
                    label: 'משימה',
                    icon: Icons.check_circle_outline_rounded,
                    color: JC.blue400,
                    active: type == 'task',
                    onTap: () => setSheet(() => type = 'task'),
                  ),
                  const SizedBox(width: 8),
                  _TypeToggle(
                    label: 'תזכורת',
                    icon: Icons.notifications_outlined,
                    color: JC.amber400,
                    active: type == 'reminder',
                    onTap: () => setSheet(() => type = 'reminder'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                textDirection: TextDirection.rtl,
                autofocus: true,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 15),
                decoration: InputDecoration(
                  hintText: type == 'task' ? 'כותרת המשימה...' : 'מה להזכיר לך?',
                  hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                  filled: true,
                  fillColor: JC.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.blue500, width: 1.5)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: _PickerTile(
                      icon: Icons.calendar_today_outlined,
                      label: '${date.day.toString().padLeft(2, '0')}/'
                          '${date.month.toString().padLeft(2, '0')}/'
                          '${date.year}',
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: sheetCtx,
                          initialDate: date,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                          builder: (c, child) => Theme(
                            data: Theme.of(c).copyWith(
                                colorScheme: ColorScheme.dark(
                                    primary: JC.blue500, surface: JC.surface)),
                            child: child!,
                          ),
                        );
                        if (picked != null) setSheet(() => date = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PickerTile(
                      icon: Icons.access_time_rounded,
                      label: time.format(sheetCtx),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetCtx,
                          initialTime: time,
                          builder: (c, child) => Theme(
                            data: Theme.of(c).copyWith(
                                colorScheme: ColorScheme.dark(
                                    primary: JC.blue500, surface: JC.surface)),
                            child: child!,
                          ),
                        );
                        if (picked != null) setSheet(() => time = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final text = textCtrl.text.trim();
                    if (text.isEmpty) return;
                    final scheduled = DateTime(
                        date.year, date.month, date.day, time.hour, time.minute);
                    Navigator.pop(sheetCtx);
                    try {
                      if (type == 'task') {
                        await ApiService(widget.settings).addTask(text,
                            dueDate: scheduled.toUtc().toIso8601String());
                      } else {
                        await ApiService(widget.settings).addReminder(
                            text, scheduled.toUtc().toIso8601String());
                      }
                      _loadEvents();
                    } catch (_) {}
                  },
                  child: Text('הוסף',
                      style: const TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatShortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

// ─── Calendar Header ──────────────────────────────────────────────────────────

class _CalendarHeader extends StatelessWidget {
  final DateTime focused;
  final CalendarFormat format;
  final VoidCallback onToggleFormat;
  final VoidCallback onRefresh;

  const _CalendarHeader({
    required this.focused,
    required this.format,
    required this.onToggleFormat,
    required this.onRefresh,
  });

  static const _months = ['', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי',
      'יוני', 'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            '${_months[focused.month]} ${focused.year}',
            style: TextStyle(
              color: JC.textPrimary,
              fontFamily: 'Heebo',
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          // Week / Month toggle pill
          Container(
            decoration: BoxDecoration(
              color: JC.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JC.border, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PillBtn(
                  label: 'שבוע',
                  active: format == CalendarFormat.week,
                  onTap: () {
                    if (format != CalendarFormat.week) onToggleFormat();
                  },
                ),
                _PillBtn(
                  label: 'חודש',
                  active: format == CalendarFormat.month,
                  onTap: () {
                    if (format != CalendarFormat.month) onToggleFormat();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: JC.textMuted, size: 19),
            onPressed: onRefresh,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _PillBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _PillBtn({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? JC.blue500.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? JC.blue400 : JC.textMuted,
            fontFamily: 'Heebo',
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─── Day header ───────────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final DateTime date;
  final int count;
  const _DayHeader({required this.date, required this.count});

  static const _days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
  static const _months = ['', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי',
      'יוני', 'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'];

  @override
  Widget build(BuildContext context) {
    final isToday = isSameDay(date, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Text(
            isToday
                ? 'היום, ${date.day} ב${_months[date.month]}'
                : 'יום ${_days[date.weekday % 7]}, ${date.day} ב${_months[date.month]}',
            style: TextStyle(
              color: isToday ? JC.blue400 : JC.textSecondary,
              fontSize: 13,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: JC.blue500.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: JC.blue400, fontSize: 11,
                  fontFamily: 'Heebo', fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Empty day ────────────────────────────────────────────────────────────────

class _EmptyDay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available_rounded, color: JC.textMuted, size: 44),
          const SizedBox(height: 12),
          Text('אין פריטים ביום זה',
              style: TextStyle(
                  color: JC.textMuted, fontFamily: 'Heebo', fontSize: 15)),
          const SizedBox(height: 6),
          Text('לחץ + להוספת משימה או תזכורת',
              style: TextStyle(
                  color: JC.textMuted.withOpacity(0.6),
                  fontFamily: 'Heebo', fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Event tile ───────────────────────────────────────────────────────────────

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventTile({required this.event});

  Color get _accentColor {
    final t = event['type']?.toString() ?? '';
    if (t == 'task') return JC.blue400;
    if (t == 'reminder') return JC.amber400;
    return JC.indigo500;
  }

  String get _typeLabel {
    final t = event['type']?.toString() ?? '';
    if (t == 'task') return 'משימה';
    if (t == 'reminder') return 'תזכורת';
    return 'אירוע';
  }

  IconData get _typeIcon {
    final t = event['type']?.toString() ?? '';
    if (t == 'task') return Icons.check_circle_outline_rounded;
    if (t == 'reminder') return Icons.notifications_outlined;
    return Icons.event_rounded;
  }

  String? _extractTime(dynamic raw) {
    if (raw == null) return null;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      if (dt.hour == 0 && dt.minute == 0) return null;
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDone = event['done'] == true;
    final timeStr = _extractTime(event['date']);
    final color = isDone ? JC.textMuted : _accentColor;
    final isHighPriority = event['priority'] == 'high';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? JC.border
              : isHighPriority
                  ? color.withOpacity(0.5)
                  : color.withOpacity(0.3),
          width: isHighPriority ? 1.2 : 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: JC.shadow.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(isDone ? 0.06 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_typeIcon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  event['title']?.toString() ?? '',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: isDone ? JC.textMuted : JC.textPrimary,
                    fontFamily: 'Heebo',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (timeStr != null) ...[
                  const SizedBox(height: 3),
                  Text(timeStr,
                      style: TextStyle(
                          color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _typeLabel,
              style: TextStyle(
                  color: color, fontSize: 10,
                  fontFamily: 'Heebo', fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Marker dot ───────────────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5, height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── Type toggle for add sheet ────────────────────────────────────────────────

class _TypeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  const _TypeToggle({
    required this.label, required this.icon, required this.color,
    required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : JC.border,
            width: active ? 1.4 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? color : JC.textMuted),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: active ? color : JC.textSecondary,
              fontFamily: 'Heebo', fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }
}

// ─── Date / time picker tile ──────────────────────────────────────────────────

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: JC.blue400),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, style: TextStyle(
                  color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
