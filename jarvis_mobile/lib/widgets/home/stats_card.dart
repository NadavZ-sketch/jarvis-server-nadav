import 'package:flutter/material.dart';
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Progress overview from /stats: task completion, active reminders, shopping.
class StatsCard extends StatelessWidget {
  final HomeController c;
  const StatsCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = c.stats;

    Widget body;
    if (c.statsLoading && s == null) {
      body = const CardSkeleton(lines: 3);
    } else if (s == null) {
      body = const EmptyState(message: 'לא ניתן לטעון סטטיסטיקות');
    } else {
      body = _buildStats(s);
    }

    return SectionCard(
      title: 'התקדמות',
      icon: Icons.insights_rounded,
      iconColor: const Color(0xFF22C55E),
      child: body,
    );
  }

  Widget _buildStats(Map<String, dynamic> s) {
    final tasks = s['tasks'] as Map<String, dynamic>? ?? const {};
    final reminders = s['reminders'] as Map<String, dynamic>? ?? const {};
    final shopping = s['shopping'] as Map<String, dynamic>? ?? const {};

    final taskTotal = (tasks['total'] as num?)?.toInt() ?? 0;
    final taskDone = (tasks['done'] as num?)?.toInt() ?? 0;
    final remActive = (reminders['active'] as num?)?.toInt() ?? 0;
    final remTotal = (reminders['total'] as num?)?.toInt() ?? 0;
    final shopTotal = (shopping['total'] as num?)?.toInt() ?? 0;
    final shopChecked = (shopping['checked'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProgressMeter(
          label: 'משימות שהושלמו',
          fraction: taskTotal == 0 ? 0 : taskDone / taskTotal,
          color: const Color(0xFF22C55E),
          trailing: '$taskDone/$taskTotal',
        ),
        ProgressMeter(
          label: 'תזכורות פעילות',
          fraction: remTotal == 0 ? 0 : remActive / remTotal,
          color: const Color(0xFFF59E0B),
          trailing: '$remActive',
        ),
        if (shopTotal > 0)
          ProgressMeter(
            label: 'רשימת קניות',
            fraction: shopTotal == 0 ? 0 : shopChecked / shopTotal,
            color: const Color(0xFF3B82F6),
            trailing: '$shopChecked/$shopTotal',
          ),
      ],
    );
  }
}
