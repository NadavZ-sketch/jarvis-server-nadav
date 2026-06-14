import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Reminders with an inline 7-day strip on top (merged from the old calendar
/// card). Tapping today shows the urgency grouping (soon / today / next);
/// tapping another day shows that day's reminders.
class RemindersCard extends StatelessWidget {
  final HomeController c;
  const RemindersCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime.now();

    final sorted = c.reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null || iso.isEmpty) return false;
      try {
        final dt = DateTime.parse(iso).toLocal();
        return !dt.isBefore(now.subtract(const Duration(minutes: 1)));
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['scheduled_time'] as String? ?? '')
          .compareTo(b['scheduled_time'] as String? ?? ''));

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text('תזכורות (${sorted.length})',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  )),
            ]),
          ),
          Divider(color: JC.border, height: 1),
          // ── 7-day strip ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                itemBuilder: (_, i) {
                  final offset = i - 3;
                  final day = today.add(Duration(days: offset));
                  final isToday = offset == 0;
                  final isSelected = offset == c.selectedDayOffset;
                  final remCount = c.reminderCountForDay(day);

                  return Semantics(
                    button: true,
                    label: '${hebrewDays[day.weekday % 7]} ${day.day}, $remCount תזכורות',
                    selected: isSelected,
                    child: GestureDetector(
                      onTap: () => c.selectDay(offset),
                      child: Container(
                        width: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? JC.blue500
                              : isToday
                                  ? JC.blue500.withValues(alpha: 0.15)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(
                                  color: JC.blue500.withValues(alpha: 0.5), width: 1)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(hebrewDays[day.weekday % 7],
                                style: TextStyle(
                                  color: isSelected ? JC.onAccent : JC.textMuted,
                                  fontSize: 10,
                                  fontFamily: 'Heebo',
                                )),
                            const SizedBox(height: 3),
                            Text('${day.day}',
                                style: TextStyle(
                                  color: isSelected ? JC.onAccent : JC.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Heebo',
                                )),
                            const SizedBox(height: 3),
                            if (remCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? JC.onAccent.withValues(alpha: 0.3)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('$remCount',
                                    style: TextStyle(
                                      color: isSelected
                                          ? JC.onAccent
                                          : const Color(0xFFF59E0B),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Heebo',
                                    )),
                              )
                            else
                              const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(color: JC.border, height: 1),
          // ── Body: today → urgency grouping, other day → that day's list ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: c.selectedDayOffset == 0
                ? _todayView(now, sorted)
                : _dayView(c.selectedDayOffset),
          ),
        ],
      ),
    );
  }

  /// Today: the urgency grouping (soon within 2h / later today / future).
  Widget _todayView(DateTime now, List<Map<String, dynamic>> sorted) {
    if (sorted.isEmpty) {
      return const EmptyState(message: 'אין תזכורות קרובות');
    }

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
        final dt = DateTime.parse(r['scheduled_time'] as String).toLocal();
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
        final dt = DateTime.parse(r['scheduled_time'] as String).toLocal();
        return !(dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year);
      } catch (_) {
        return false;
      }
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (urgent.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 0.8),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_rounded,
                color: Color(0xFFEF4444), size: 14),
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
        _groupHeader('בקרוב', const Color(0xFFEF4444)),
        const SizedBox(height: 6),
        ...urgent.map((r) => _row(r, const Color(0xFFEF4444))),
        if (todayLater.isNotEmpty || upcoming.isNotEmpty)
          const SizedBox(height: 10),
      ],
      if (todayLater.isNotEmpty) ...[
        _groupHeader('היום', const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        ...todayLater.map((r) => _row(r, const Color(0xFFF59E0B))),
        if (upcoming.isNotEmpty) const SizedBox(height: 10),
      ],
      if (upcoming.isNotEmpty) ...[
        _groupHeader('הבא', const Color(0xFF3B82F6)),
        const SizedBox(height: 6),
        ...upcoming.take(3).map((r) => _row(r, const Color(0xFF3B82F6))),
        if (upcoming.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+${upcoming.length - 3} נוספות',
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ),
      ],
    ]);
  }

  /// Another selected day: a flat chronological list for that day.
  Widget _dayView(int offset) {
    final events = c.remindersForOffset(offset);
    if (events.isEmpty) {
      return const EmptyState(message: 'אין תזכורות ביום זה');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeader('אירועים ביום זה', const Color(0xFFF59E0B)),
      const SizedBox(height: 6),
      ...events.take(6).map((r) => _row(r, const Color(0xFFF59E0B))),
      if (events.length > 6)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+${events.length - 6} נוספות',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ),
    ]);
  }

  Widget _groupHeader(String label, Color color) {
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

  Widget _row(Map<String, dynamic> reminder, Color accent) {
    final text = reminder['text'] as String? ?? '—';
    final iso = reminder['scheduled_time'] as String?;
    final timeStr = timeOfDay(iso);
    final remaining = formatRemTime(iso);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(start: BorderSide(color: accent, width: 2)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(timeStr.isEmpty ? '—' : timeStr,
                style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
            if (remaining.isNotEmpty)
              Text(remaining,
                  style: TextStyle(
                      color: accent, fontSize: 11, fontFamily: 'Heebo')),
          ]),
        ),
      ]),
    );
  }
}
