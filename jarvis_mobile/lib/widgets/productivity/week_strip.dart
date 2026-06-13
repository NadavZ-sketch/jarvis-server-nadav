import 'package:flutter/material.dart';
import '../../main.dart' show JC;

class DayMeta {
  final int tasks;
  final int reminders;
  final int overdue;
  const DayMeta({this.tasks = 0, this.reminders = 0, this.overdue = 0});
  bool get hasItems => tasks > 0 || reminders > 0 || overdue > 0;
}

class WeekStripWidget extends StatelessWidget {
  final DateTime selected;
  final Map<DateTime, DayMeta> dayData;
  final ValueChanged<DateTime> onDayTapped;

  const WeekStripWidget({
    super.key,
    required this.selected,
    required this.dayData,
    required this.onDayTapped,
  });

  // Hebrew day abbreviations: Sunday=0…Saturday=6
  static const _dayNames = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Start from Sunday of the current week (weekday % 7 so Sunday=0)
    final startOfWeek = today.subtract(Duration(days: today.weekday % 7));

    return Container(
      color: JC.surface,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Row(
        children: List.generate(7, (i) {
          final day = startOfWeek.add(Duration(days: i));
          final key = DateTime(day.year, day.month, day.day);
          final meta = dayData[key] ?? const DayMeta();
          final isToday = key == today;
          final selKey = DateTime(selected.year, selected.month, selected.day);
          final isSelected = selKey == key && !isToday;
          final isPast = day.isBefore(today);

          return Expanded(
            child: GestureDetector(
              onTap: () => onDayTapped(day),
              child: _DayPill(
                dayName: _dayNames[day.weekday % 7],
                dayNumber: day.day,
                isToday: isToday,
                isSelected: isSelected,
                isPast: isPast,
                meta: meta,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Day pill ─────────────────────────────────────────────────────────────────

class _DayPill extends StatelessWidget {
  final String dayName;
  final int dayNumber;
  final bool isToday;
  final bool isSelected;
  final bool isPast;
  final DayMeta meta;

  const _DayPill({
    required this.dayName,
    required this.dayNumber,
    required this.isToday,
    required this.isSelected,
    required this.isPast,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isToday
        ? Colors.white
        : isPast
            ? JC.textMuted
            : JC.textSecondary;
    final bgColor = isToday
        ? JC.blue500
        : isSelected
            ? JC.blue500.withOpacity(0.15)
            : Colors.transparent;
    final borderColor =
        isSelected ? JC.blue500 : Colors.transparent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dayName,
                style: TextStyle(
                  color: textColor.withOpacity(isPast ? 0.5 : 0.7),
                  fontSize: 9.5,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$dayNumber',
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _DotRow(meta: meta),
        const SizedBox(height: 2),
      ],
    );
  }
}

// ─── Dot row ─────────────────────────────────────────────────────────────────

class _DotRow extends StatelessWidget {
  final DayMeta meta;
  const _DotRow({required this.meta});

  @override
  Widget build(BuildContext context) {
    // Priority order: overdue (red) → tasks (blue) → reminders (amber)
    final dots = <Color>[
      if (meta.overdue > 0) JC.cancelRed,
      if (meta.tasks > 0) JC.blue400,
      if (meta.reminders > 0) JC.amber400,
    ];

    return SizedBox(
      height: 5,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < dots.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dots[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
