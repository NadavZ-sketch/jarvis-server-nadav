import 'package:flutter/material.dart';
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_dialogs.dart';
import '../../screens/home/home_helpers.dart';

class QuickActionsCard extends StatelessWidget {
  final HomeController c;
  const QuickActionsCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final actions = <Map<String, dynamic>>[
      {
        'icon': Icons.build_circle_outlined,
        'label': 'בנה את היום',
        'color': const Color(0xFF3B82F6),
        'onTap': () => showBuildDaySheet(context, c),
      },
      {
        'icon': Icons.add_circle_outline_rounded,
        'label': 'משימה חדשה',
        'color': const Color(0xFFA5B4FC),
        'onTap': () => showAddTaskDialog(context, c),
      },
      {
        'icon': Icons.alarm_add_rounded,
        'label': 'תזכורת חדשה',
        'color': const Color(0xFF22C55E),
        'onTap': () => showAddReminderDialog(context, c),
      },
      {
        'icon': Icons.chat_bubble_outline_rounded,
        'label': 'שיחה עם ג׳רוויס',
        'color': const Color(0xFFF59E0B),
        'onTap': () => c.onNavigateToChat?.call(),
      },
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final a = actions[i];
          return QuickActionChip(
            icon: a['icon'] as IconData,
            label: a['label'] as String,
            color: a['color'] as Color,
            onTap: a['onTap'] as VoidCallback,
          );
        },
      ),
    );
  }
}
