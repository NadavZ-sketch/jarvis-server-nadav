import 'package:flutter/material.dart';
import '../../screens/home/home_controller.dart';
import '../productivity/week_strip.dart';

/// Home-screen card wrapping [WeekStripWidget]. Uses [HomeController.weekDayMeta]
/// and [HomeController.selectedWeekDay]. Navigates to Calendar on non-today tap.
class WeekStripCard extends StatelessWidget {
  final HomeController c;
  const WeekStripCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    return WeekStripWidget(
      selected: c.selectedWeekDay,
      dayData: c.weekDayMeta,
      onDayTapped: (day) {
        c.selectWeekDay(day);
        final now = DateTime.now();
        final isToday = day.year == now.year &&
            day.month == now.month &&
            day.day == now.day;
        if (!isToday) c.onNavigateToCalendar?.call();
      },
    );
  }
}
