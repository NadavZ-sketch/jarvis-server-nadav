import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';

class TabOverview extends StatefulWidget {
  final AppSettings settings;
  const TabOverview({super.key, required this.settings});

  @override
  State<TabOverview> createState() => _TabOverviewState();
}

class _TabOverviewState extends State<TabOverview>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  Map<String, dynamic>? _health;
  List<Map<String, dynamic>> _log = [];
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  static const _providers = ['Ollama', 'Groq', 'DeepSeek', 'Gemini'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.healthCheck().catchError((_) => <String, dynamic>{}),
        _api.fetchExecutionLog(limit: 20).catchError((_) => <Map<String, dynamic>>[]),
        _api.getStats().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _health = results[0] as Map<String, dynamic>;
        _log    = results[1] as List<Map<String, dynamic>>;
        _stats  = results[2] as Map<String, dynamic>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiService.friendlyError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 40, color: Colors.red),
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        TextButton(onPressed: _load, child: const Text('נסה שוב')),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _serverStatusCard(),
          const SizedBox(height: 16),
          _modelChainCard(),
          const SizedBox(height: 16),
          _executionLogCard(),
          const SizedBox(height: 16),
          _agentsAccordion(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _serverStatusCard() {
    final online = _health != null && _health!.isNotEmpty;
    final model = _health?['active_model'] as String? ?? '—';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.circle, size: 12, color: online ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(online ? 'שרת פעיל' : 'שרת לא זמין',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
              if (online && model != '—')
                Text('מודל פעיל: $model',
                    style: const TextStyle(fontSize: 12, fontFamily: 'Heebo', color: Colors.grey)),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _modelChainCard() {
    final active = (_health?['active_model'] as String? ?? '').toLowerCase();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('שרשרת מודלים',
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
            const SizedBox(height: 12),
            Row(children: _providers.map((p) {
              final isActive = active.isNotEmpty && active.contains(p.toLowerCase());
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Chip(
                  label: Text(p, style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? Colors.green.shade800 : null,
                  )),
                  backgroundColor: isActive ? Colors.green.shade50 : null,
                  side: isActive
                      ? BorderSide(color: Colors.green.shade400, width: 1.5)
                      : null,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList()),
          ],
        ),
      ),
    );
  }

  Widget _executionLogCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('לוג ביצוע (20 אחרונים)',
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
            const SizedBox(height: 8),
            if (_log.isEmpty)
              const Text('אין רשומות', style: TextStyle(color: Colors.grey, fontFamily: 'Heebo'))
            else
              ..._log.map((e) {
                final ts = e['created_at'] as String? ?? '';
                final time = ts.length >= 19 ? ts.substring(11, 19) : ts;
                final agent = e['agent'] as String? ?? '—';
                final ms = e['duration_ms'];
                final status = e['status'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 65, child: Text(time,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey))),
                    Expanded(child: Text(agent,
                        style: const TextStyle(fontSize: 12, fontFamily: 'Heebo'),
                        overflow: TextOverflow.ellipsis)),
                    if (ms != null)
                      Text('${ms}ms',
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 6),
                    Icon(
                      status == 'ok' ? Icons.check_circle_outline : Icons.error_outline,
                      size: 14,
                      color: status == 'ok' ? Colors.green : Colors.red,
                    ),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _agentsAccordion() {
    final agentUsage = (_stats?['agentUsage'] as Map?)?.cast<String, dynamic>() ?? {};
    final entries = agentUsage.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    return Card(
      child: ExpansionTile(
        title: const Text('שימוש בסוכנים',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
        initiallyExpanded: false,
        children: entries.isEmpty
            ? [const ListTile(
                title: Text('אין נתונים', style: TextStyle(color: Colors.grey, fontFamily: 'Heebo')))]
            : entries.map((e) => ListTile(
                title: Text(e.key, style: const TextStyle(fontFamily: 'Heebo', fontSize: 14)),
                trailing: Text('${e.value}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                dense: true,
                minVerticalPadding: 0,
              )).toList(),
      ),
    );
  }
}
