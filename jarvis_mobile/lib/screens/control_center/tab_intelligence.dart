import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';

class TabIntelligence extends StatefulWidget {
  final AppSettings settings;
  const TabIntelligence({super.key, required this.settings});

  @override
  State<TabIntelligence> createState() => _TabIntelligenceState();
}

class _TabIntelligenceState extends State<TabIntelligence>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  Map<String, dynamic>? _scoreData;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.fetchWeeklyScore().catchError((_) => <String, dynamic>{}),
      _api.fetchWeeklyHistory(weeks: 6).catchError((_) => <Map<String, dynamic>>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _scoreData = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : {};
      _history = results[1] is List
          ? List<Map<String, dynamic>>.from(results[1] as List)
          : [];
      _loading   = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _weeklyScoreCard(),
          const SizedBox(height: 16),
          _historyChart(),
          const SizedBox(height: 16),
          _feedbackSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _weeklyScoreCard() {
    final score = (_scoreData?['score'] as num?)?.toDouble();
    final ups   = _scoreData?['ups']   as int? ?? 0;
    final downs = _scoreData?['downs'] as int? ?? 0;
    final total = _scoreData?['total'] as int? ?? 0;

    final Color scoreColor = score == null
        ? Colors.grey
        : score > 70
            ? Colors.green
            : score > 40
                ? Colors.amber
                : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('ציון שבועי', style: TextStyle(fontFamily: 'Heebo', fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              score != null ? score.toStringAsFixed(1) : '—',
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: scoreColor,
                fontFamily: 'Heebo',
              ),
            ),
            if (total > 0) ...[
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.thumb_up, size: 18, color: Colors.green),
                const SizedBox(width: 4),
                Text('$ups', style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 16),
                const Icon(Icons.thumb_down, size: 18, color: Colors.red),
                const SizedBox(width: 4),
                Text('$downs', style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 16),
                Text('מתוך $total', style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Heebo')),
              ]),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('אין נתוני משוב השבוע', style: TextStyle(color: Colors.grey, fontFamily: 'Heebo', fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _historyChart() {
    if (_history.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('היסטוריה שבועית',
                style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _history.map((week) {
                  final score = (week['score'] as num?)?.toDouble();
                  final label = week['label'] as String? ?? '';
                  final Color barColor = score == null
                      ? Colors.grey.shade300
                      : score > 70
                          ? Colors.green
                          : score > 40
                              ? Colors.amber
                              : Colors.red;
                  final double barHeight = score == null ? 4 : (score / 100 * 56).clamp(4.0, 56.0);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (score != null)
                            Text(
                              score.toStringAsFixed(0),
                              style: TextStyle(fontSize: 9, color: barColor, fontWeight: FontWeight.bold),
                            ),
                          const SizedBox(height: 2),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: barColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(label,
                              style: const TextStyle(fontSize: 9, color: Colors.grey),
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedbackSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('משוב על תשובות', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              'דרג תשובות ישירות מתוך ממשק הצ\'אט. ציון המשוב מתעדכן כאן בזמן אמת.',
              style: TextStyle(fontFamily: 'Heebo', fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              _statChip('חיובי', '${_scoreData?["ups"] ?? 0}', Colors.green),
              _statChip('שלילי', '${_scoreData?["downs"] ?? 0}', Colors.red),
              _statChip('סה״כ', '${_scoreData?["total"] ?? 0}', Colors.blue),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 12, color: color, fontFamily: 'Heebo')),
        const SizedBox(width: 6),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}
