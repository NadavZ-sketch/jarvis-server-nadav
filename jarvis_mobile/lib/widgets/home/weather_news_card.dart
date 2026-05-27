import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Dynamic weather + news summaries pulled from /dashboard-context widgets.
class WeatherNewsCard extends StatelessWidget {
  final HomeController c;
  const WeatherNewsCard(this.c, {super.key});

  String? _widgetSummary(String type) {
    final widgets = c.dashboardContext?['widgets'] as List?;
    if (widgets == null) return null;
    for (final w in widgets) {
      if (w is Map && w['type'] == type) {
        final data = w['data'];
        if (data is Map && data['summary'] is String) {
          final s = (data['summary'] as String).trim();
          return s.isEmpty ? null : s;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final weather = _widgetSummary('weather');
    final news = _widgetSummary('news');

    Widget body;
    if (c.dashboardLoading && c.dashboardContext == null) {
      body = const CardSkeleton(lines: 3);
    } else if (weather == null && news == null) {
      body = const EmptyState(message: 'אין מידע זמין כרגע');
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (weather != null)
          _row('🌤', 'מזג אוויר', weather, const Color(0xFF60A5FA)),
        if (weather != null && news != null) const SizedBox(height: 12),
        if (news != null)
          _row('📰', 'חדשות', news, const Color(0xFFF59E0B)),
      ]);
    }

    return SectionCard(
      title: 'סביבה',
      icon: Icons.public_rounded,
      iconColor: const Color(0xFF60A5FA),
      child: body,
    );
  }

  Widget _row(String emoji, String label, String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo')),
        ]),
        const SizedBox(height: 4),
        Text(text,
            style: TextStyle(
              color: JC.textSecondary,
              fontSize: 12.5,
              height: 1.5,
              fontFamily: 'Heebo',
            )),
      ],
    );
  }
}
