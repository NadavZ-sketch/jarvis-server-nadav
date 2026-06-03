import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// Each widget type exposed by /dashboard-context.
class _Topic {
  final String key;
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
  String? _selected;

  HomeController get c => widget.c;

  Map<String, dynamic>? _widgetData(String type) {
    final widgets = c.dashboardContext?['widgets'] as List?;
    if (widgets == null) return null;
    for (final w in widgets) {
      if (w is Map && w['type'] == type) {
        final data = w['data'];
        if (data is Map) return Map<String, dynamic>.from(data);
      }
    }
    return null;
  }

  List<_Topic> get _available =>
      _kTopics.where((t) => _widgetData(t.key) != null).toList();

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
              if (i > 0) ...[
                const SizedBox(height: 8),
                Divider(color: JC.border.withOpacity(0.4), height: 1),
                const SizedBox(height: 8),
              ],
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
    final data = _widgetData(topic.key)!;
    return topic.key == 'weather'
        ? _buildWeather(data)
        : _buildNews(data);
  }

  /// Structured weather display: large temp + condition + max/min/rain chips.
  Widget _buildWeather(Map<String, dynamic> d) {
    final emoji  = (d['emoji']  as String?) ?? '🌡';
    final temp   = d['temp']  as int?;
    final desc   = (d['desc']  as String?) ?? '';
    final max    = d['max']   as int?;
    final min    = d['min']   as int?;
    final rain   = d['rain']  as int?;
    final advice = (d['advice'] as String?) ?? '';
    final city   = (d['city']  as String?) ?? '';

    // Fallback to raw summary if structured fields absent (old server).
    if (temp == null) {
      final summary = (d['summary'] as String?) ?? '';
      return Text(
        summary,
        style: TextStyle(color: JC.textSecondary, fontSize: 12.5, height: 1.5, fontFamily: 'Heebo'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // City + large temp row
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$temp°',
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                    height: 1.0,
                  ),
                ),
                if (desc.isNotEmpty)
                  Text(
                    desc,
                    style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Heebo',
                    ),
                  ),
              ],
            ),
            if (city.isNotEmpty) ...[
              const Spacer(),
              Text(
                city,
                style: TextStyle(
                  color: JC.textSecondary.withOpacity(0.6),
                  fontSize: 11,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Detail chips row
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (max != null && min != null)
              _detailChip('↑$max° ↓$min°', const Color(0xFF60A5FA)),
            if (rain != null && rain > 0)
              _detailChip('$rain% גשם', const Color(0xFF818CF8)),
            if (advice.isNotEmpty)
              _detailChip(advice, const Color(0xFF34D399)),
          ],
        ),
      ],
    );
  }

  Widget _detailChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w600),
      ),
    );
  }

  /// News as a clean headline list.
  Widget _buildNews(Map<String, dynamic> d) {
    final rawHeadlines = d['headlines'];
    final headlines = rawHeadlines is List
        ? rawHeadlines.cast<String>()
        : (d['summary'] as String? ?? '').split('\n').map((l) => l.replaceFirst(RegExp(r'^[•·]\s*'), '')).where((l) => l.isNotEmpty).toList();

    if (headlines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < headlines.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headlines[i],
                  style: TextStyle(
                    color: JC.textSecondary,
                    fontSize: 12.5,
                    height: 1.45,
                    fontFamily: 'Heebo',
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
