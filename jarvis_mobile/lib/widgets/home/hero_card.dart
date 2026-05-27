import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Time-aware greeting hero. Prefers the server's per-slot [heroCard] text from
/// /dashboard-context, falling back to a local greeting + /today-message.
class HeroCard extends StatelessWidget {
  final HomeController c;
  const HeroCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final greeting = dynamicGreeting(c.settings.userName);
    final hero = c.dashboardContext?['heroCard'] as Map<String, dynamic>?;
    final heroText = (hero?['text'] as String?)?.trim();
    final subtitle = (heroText != null && heroText.isNotEmpty)
        ? heroText
        : (c.todayMessage.isNotEmpty ? c.todayMessage : todayDateLine());

    final todayRemCount = c.remindersForOffset(0).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A2E4A), JC.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(greetingEmoji(), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting,
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Heebo',
                        )),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                          color: JC.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                          fontFamily: 'Heebo',
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('${c.openTasks} משימות פתוחות', JC.blue400),
              if (c.highPriorityCount > 0)
                _chip('${c.highPriorityCount} דחופות', const Color(0xFFEF4444)),
              if (todayRemCount > 0)
                _chip('$todayRemCount תזכורות היום', const Color(0xFFF59E0B)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            )),
      ]),
    );
  }
}
