import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// 7-day strip; tapping a day filters the events list below it.
class CalendarCard extends StatelessWidget {
  final HomeController c;
  const CalendarCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dayEvents = c.remindersForOffset(c.selectedDayOffset);

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: JC.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(Icons.calendar_today_rounded, color: JC.blue400, size: 16),
              const SizedBox(width: 8),
              Text('לוח שנה',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  )),
            ]),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: 7,
                itemBuilder: (_, i) {
                  final offset = i - 3;
                  final day = today.add(Duration(days: offset));
                  final isToday = offset == 0;
                  final isSelected = offset == c.selectedDayOffset;
                  final remCount = c.reminderCountForDay(day);

                  return GestureDetector(
                    onTap: () => c.selectDay(offset),
                    child: Container(
                      width: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? JC.blue500
                            : isToday
                                ? JC.blue500.withOpacity(0.15)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: JC.blue500.withOpacity(0.5), width: 1)
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
                                    : const Color(0xFFF59E0B).withOpacity(0.18),
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
                  );
                },
              ),
            ),
          ),
          if (dayEvents.isNotEmpty) ...[
            Divider(color: JC.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.selectedDayOffset == 0 ? 'אירועים היום' : 'אירועים ביום זה',
                      style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 8),
                  ...dayEvents.take(3).map((r) {
                    final text = r['text'] as String? ?? '—';
                    final time = timeOfDay(r['scheduled_time'] as String?);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Container(
                          width: 36,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(time.isEmpty ? '--:--' : time,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFF59E0B),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Heebo',
                              )),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: JC.textSecondary,
                                fontSize: 12,
                                fontFamily: 'Heebo',
                              )),
                        ),
                      ]),
                    );
                  }),
                  if (dayEvents.length > 3)
                    Text('+${dayEvents.length - 3} נוספות',
                        style: TextStyle(
                            color: JC.textMuted,
                            fontSize: 11,
                            fontFamily: 'Heebo')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
