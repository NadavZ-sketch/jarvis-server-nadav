import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';
import '../main.dart' show JC;
import '../app_settings.dart';

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

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  DateTime _dateOnly(DateTime dt) => DateTime.utc(dt.year, dt.month, dt.day);

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    try {
      final url = Uri.parse('${widget.settings.serverUrl}/calendar-events');
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data   = jsonDecode(res.body);
        final events = (data['events'] as List).cast<Map<String, dynamic>>();
        final map    = <DateTime, List<Map<String, dynamic>>>{};
        for (final e in events) {
          final raw = e['date'];
          if (raw == null) continue;
          try {
            final day = _dateOnly(DateTime.parse(raw.toString()));
            map.putIfAbsent(day, () => []).add(e);
          } catch (_) {}
        }
        if (mounted) setState(() { _events = map; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('לוח שנה',
            style: TextStyle(color: JC.textPrimary, fontSize: 18,
                fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: JC.textMuted, size: 20),
            onPressed: _loadEvents,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JC.blue400))
          : Column(
              children: [
                // ── Calendar ──────────────────────────────────────────────
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
                    selectedDayPredicate: (d) => isSameDay(d, _selected),
                    eventLoader: _eventsForDay,
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      defaultTextStyle: const TextStyle(
                          color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
                      weekendTextStyle: const TextStyle(
                          color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13),
                      todayDecoration: BoxDecoration(
                          color: JC.blue500.withOpacity(0.3),
                          shape: BoxShape.circle),
                      todayTextStyle: const TextStyle(
                          color: JC.blue400, fontFamily: 'Heebo',
                          fontWeight: FontWeight.w700, fontSize: 13),
                      selectedDecoration: const BoxDecoration(
                          color: JC.blue500, shape: BoxShape.circle),
                      selectedTextStyle: const TextStyle(
                          color: Colors.white, fontFamily: 'Heebo',
                          fontWeight: FontWeight.w700, fontSize: 13),
                      markerDecoration: const BoxDecoration(
                          color: JC.blue400, shape: BoxShape.circle),
                      markerSize: 5,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                          color: JC.textPrimary, fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600, fontSize: 15),
                      leftChevronIcon: Icon(Icons.chevron_left, color: JC.textMuted),
                      rightChevronIcon: Icon(Icons.chevron_right, color: JC.textMuted),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                          color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
                      weekendStyle: TextStyle(
                          color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
                    ),
                    onDaySelected: (selected, focused) =>
                        setState(() { _selected = selected; _focused = focused; }),
                    onPageChanged: (focused) =>
                        setState(() => _focused = focused),
                  ),
                ),

                // ── Events for selected day ────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        _formatSelectedDate(_selected),
                        style: const TextStyle(color: JC.textSecondary,
                            fontSize: 13, fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      if (dayEvents.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: JC.blue500.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${dayEvents.length}',
                              style: const TextStyle(color: JC.blue400,
                                  fontSize: 11, fontFamily: 'Heebo',
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),

                Expanded(
                  child: dayEvents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.event_available_rounded,
                                  color: JC.textMuted, size: 40),
                              SizedBox(height: 10),
                              Text('אין אירועים ביום זה',
                                  style: TextStyle(color: JC.textMuted,
                                      fontFamily: 'Heebo', fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: dayEvents.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _EventTile(event: dayEvents[i]),
                        ),
                ),
              ],
            ),
    );
  }

  String _formatSelectedDate(DateTime d) {
    const days = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    const months = ['', 'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
        'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'];
    return 'יום ${days[d.weekday % 7]}, ${d.day} ב${months[d.month]}';
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final isTask     = event['type'] == 'task';
    final isDone     = event['done'] == true;
    final timeStr    = _extractTime(event['date']);
    final color      = isTask ? JC.blue400 : const Color(0xFFF59E0B);
    final icon       = isTask ? Icons.check_circle_outline_rounded
                               : Icons.alarm_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone ? JC.border : color.withOpacity(0.35),
          width: 0.9,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(isDone ? 0.07 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isDone ? JC.textMuted : color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['title'] ?? '',
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
                      style: const TextStyle(color: JC.textMuted,
                          fontFamily: 'Heebo', fontSize: 11)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isTask ? 'משימה' : 'תזכורת',
              style: TextStyle(color: color, fontSize: 10,
                  fontFamily: 'Heebo', fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String? _extractTime(dynamic raw) {
    if (raw == null) return null;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      if (dt.hour == 0 && dt.minute == 0) return null;
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return null; }
  }
}
