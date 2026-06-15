import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

class _Topic {
  final String key;
  final String emoji;
  final String label;
  final Color color;
  const _Topic(this.key, this.emoji, this.label, this.color);
}

const _kTopics = [
  _Topic('news',   '📰', 'חדשות',      Color(0xFFF59E0B)),
  _Topic('sports', '⚽', 'ספורט',       Color(0xFF22C55E)),
  _Topic('tech',   '💻', 'טכנולוגיה',  Color(0xFFA78BFA)),
];

/// Weather pill always visible + tabbed news/sports/tech feed.
class WeatherNewsCard extends StatefulWidget {
  final HomeController c;
  const WeatherNewsCard(this.c, {super.key});

  @override
  State<WeatherNewsCard> createState() => _WeatherNewsCardState();
}

class _WeatherNewsCardState extends State<WeatherNewsCard>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<_Topic> _lastAvailable = [];

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

  void _syncTabController(List<_Topic> available) {
    if (available.length != _lastAvailable.length) {
      _tabController?.dispose();
      _tabController = available.isEmpty
          ? null
          : TabController(length: available.length, vsync: this);
      _lastAvailable = List.from(available);
    }
  }

  @override
  void initState() {
    super.initState();
    _syncTabController(_available);
  }

  @override
  void didUpdateWidget(WeatherNewsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTabController(_available);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weatherData = _widgetData('weather');
    final available = _available;

    Widget body;
    if (c.dashboardLoading && c.dashboardContext == null) {
      body = const CardSkeleton(lines: 4);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Weather pill (always visible) ──
          if (weatherData != null) ...[
            _buildWeatherPill(weatherData),
            const SizedBox(height: 10),
          ],
          // ── Tab bar + content ──
          if (available.isEmpty && weatherData == null)
            const EmptyState(message: 'אין מידע זמין כרגע')
          else if (available.isNotEmpty && _tabController != null) ...[
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Heebo', fontSize: 12),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: JC.border,
              tabs: available
                  .map((t) => Tab(text: '${t.emoji} ${t.label}'))
                  .toList(),
              labelColor: JC.textPrimary,
              unselectedLabelColor: JC.textMuted,
              indicatorColor: JC.blue500,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 160,
              child: TabBarView(
                controller: _tabController,
                children: available.map((t) {
                  final data = _widgetData(t.key)!;
                  return _buildHeadlineList(data, t.color);
                }).toList(),
              ),
            ),
          ],
        ],
      );
    }

    return SectionCard(
      title: 'סביבה',
      icon: Icons.public_rounded,
      iconColor: const Color(0xFF60A5FA),
      child: body,
    );
  }

  /// Compact weather pill: emoji · temp · desc · chips row.
  Widget _buildWeatherPill(Map<String, dynamic> d) {
    final emoji = (d['emoji'] as String?) ?? '🌡';
    final temp  = d['temp']  as int?;
    final desc  = (d['desc'] as String?) ?? '';
    final max   = d['max']   as int?;
    final min   = d['min']   as int?;
    final rain  = d['rain']  as int?;
    final city  = (d['city'] as String?) ?? '';

    if (temp == null) {
      final summary = (d['summary'] as String?) ?? '';
      return Text(summary,
          style: TextStyle(
              color: JC.textSecondary,
              fontSize: 12.5,
              height: 1.5,
              fontFamily: 'Heebo'));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('$temp°',
                  style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                      height: 1.0)),
              if (city.isNotEmpty) ...[
                const Spacer(),
                Text(city,
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 11,
                        fontFamily: 'Heebo')),
              ],
            ]),
            if (desc.isNotEmpty)
              Text(desc,
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 11,
                      fontFamily: 'Heebo')),
            const SizedBox(height: 4),
            Wrap(spacing: 5, children: [
              if (max != null && min != null)
                _wChip('↑$max° ↓$min°', const Color(0xFF60A5FA)),
              if (rain != null && rain > 0)
                _wChip('$rain% גשם', const Color(0xFF818CF8)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _wChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.7),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600)),
    );
  }

  /// Renders a headline list (news, sports, or tech — same structure).
  Widget _buildHeadlineList(Map<String, dynamic> d, Color dotColor) {
    final rawHeadlines = d['headlines'];
    final headlines = rawHeadlines is List
        ? rawHeadlines.whereType<String>().toList()
        : (d['summary'] as String? ?? '')
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^[•·]\s*'), ''))
            .where((l) => l.isNotEmpty)
            .toList();

    if (headlines.isEmpty) return const EmptyState(message: 'אין כותרות');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (int i = 0; i < headlines.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(headlines[i],
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12.5,
                      height: 1.45,
                      fontFamily: 'Heebo')),
            ),
          ]),
        ],
      ],
    );
  }
}
