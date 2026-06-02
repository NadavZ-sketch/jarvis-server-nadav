import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Each widget type exposed by /dashboard-context.
class _Topic {
  final String key; // matches w['type'] from the API
  final String emoji;
  final String label;
  final Color color;
  const _Topic(this.key, this.emoji, this.label, this.color);
}

const _kTopics = [
  _Topic('weather', '🌤', 'מזג אוויר', Color(0xFF60A5FA)),
  _Topic('news', '📰', 'חדשות', Color(0xFFF59E0B)),
];

/// Dynamic weather + news card with per-topic chip filter.
class WeatherNewsCard extends StatefulWidget {
  final HomeController c;
  const WeatherNewsCard(this.c, {super.key});

  @override
  State<WeatherNewsCard> createState() => _WeatherNewsCardState();
}

class _WeatherNewsCardState extends State<WeatherNewsCard> {
  /// null = show all available topics.
  String? _selected;

  HomeController get c => widget.c;

  String? _summary(String type) {
    final widgets = c.dashboardContext?['widgets'] as List?;
    if (widgets == null) return null;
    for (final w in widgets) {
      if (w is Map && w['type'] == type) {
        final data = w['data'];
        if (data is Map && data['summary'] is String) {
          final s = (data['summary'] as String).trim();
          if (s.isEmpty) return null;
          if (s.contains('לא הצלחתי') || s.contains('סליחה') ||
              (s.contains('בעיה') && s.contains('נסה שוב'))) return null;
          return s;
        }
      }
    }
    return null;
  }

  /// Returns which topics actually have content right now.
  List<_Topic> get _available =>
      _kTopics.where((t) => _summary(t.key) != null).toList();

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (c.dashboardLoading && c.dashboardContext == null) {
      body = const CardSkeleton(lines: 3);
    } else {
      final available = _available;
      if (available.isEmpty) {
        body = const EmptyState(message: 'אין מידע זמין כרגע');
      } else {
        // If user's pinned selection has no data, fall back to "all".
        final activeKey =
            (_selected != null && available.any((t) => t.key == _selected))
                ? _selected
                : null;

        final shown = activeKey != null
            ? available.where((t) => t.key == activeKey).toList()
            : available;

        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildChips(available, activeKey),
            const SizedBox(height: 12),
            for (int i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildSection(shown[i]),
            ],
          ],
        );
      }
    }

    return SectionCard(
      title: 'סביבה',
      icon: Icons.public_rounded,
      iconColor: const Color(0xFF60A5FA),
      child: body,
    );
  }

  Widget _buildChips(List<_Topic> available, String? activeKey) {
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          // "הכל" chip
          _chip(
            emoji: '🌐',
            label: 'הכל',
            selected: activeKey == null,
            color: const Color(0xFF6366F1),
            onTap: () => setState(() => _selected = null),
          ),
          ...available.map((t) {
            final sel = activeKey == t.key;
            return Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: _chip(
                emoji: t.emoji,
                label: t.label,
                selected: sel,
                color: t.color,
                onTap: () => setState(() => _selected = sel ? null : t.key),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip({
    required String emoji,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.18) : const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : JC.border.withOpacity(0.7),
            width: 0.8,
          ),
        ),
        child: Text(
          '$emoji $label',
          style: TextStyle(
            color: selected ? color : JC.textSecondary,
            fontSize: 11,
            fontFamily: 'Heebo',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSection(_Topic topic) {
    final text = _summary(topic.key)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(topic.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text(
            topic.label,
            style: TextStyle(
              color: topic.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'Heebo',
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            color: JC.textSecondary,
            fontSize: 12.5,
            height: 1.5,
            fontFamily: 'Heebo',
          ),
        ),
      ],
    );
  }
}
