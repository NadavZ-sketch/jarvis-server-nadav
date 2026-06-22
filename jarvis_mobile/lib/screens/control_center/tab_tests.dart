import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';
import '../e2e_reports_screen.dart';

class TabTests extends StatefulWidget {
  final AppSettings settings;
  const TabTests({super.key, required this.settings});

  @override
  State<TabTests> createState() => _TabTestsState();
}

class _TabTestsState extends State<TabTests>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  List<Map<String, dynamic>> _testCases = [];
  Map<String, dynamic>? _schedule;
  bool _loading = true;

  static const _freqOptions = ['manual', 'daily', 'weekly'];
  static const _freqLabels  = {'manual': 'ידני', 'daily': 'יומי', 'weekly': 'שבועי'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _api.fetchTestCases().catchError((_) => <Map<String, dynamic>>[]),
      _api.fetchE2eSchedule().catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _testCases = results[0] as List<Map<String, dynamic>>;
      _schedule  = results[1] as Map<String, dynamic>?;
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
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: E2eReportsPanel(settings: widget.settings),
            ),
          ),
          const SizedBox(height: 16),
          _testCasesCard(),
          const SizedBox(height: 16),
          _scheduleCard(),
          const SizedBox(height: 16),
          _exportCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _testCasesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text(
                  'מקרי בדיקה מוקלטים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo'),
                ),
              ),
              Text('${_testCases.length}', style: const TextStyle(color: Colors.grey)),
            ]),
            const SizedBox(height: 8),
            if (_testCases.isEmpty)
              const Text('אין מקרי בדיקה', style: TextStyle(color: Colors.grey, fontFamily: 'Heebo'))
            else
              ..._testCases.take(5).map((tc) {
                final name   = tc['name']        as String? ?? '—';
                final status = tc['last_status'] as String? ?? 'pending';
                final color  = switch (status) {
                  'pass' => Colors.green,
                  'fail' => Colors.red,
                  _      => Colors.grey,
                };
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(name, style: const TextStyle(fontFamily: 'Heebo', fontSize: 14)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(status, style: TextStyle(fontSize: 11, color: color)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      onPressed: () => _runTest(tc['id'].toString()),
                      tooltip: 'הרץ',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _runTest(String id) async {
    final result = await _api.runTestCase(id).catchError((_) => null);
    if (!mounted) return;
    final status = result?['status'] as String? ?? 'unknown';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('תוצאה: $status', style: const TextStyle(fontFamily: 'Heebo'))),
    );
    _load();
  }

  Widget _scheduleCard() {
    final sched = _schedule?['schedule'] as Map<String, dynamic>?;
    final freq  = sched?['frequency'] as String? ?? 'manual';
    final time  = sched?['time']      as String? ?? '03:00';
    final validFreq = _freqOptions.contains(freq) ? freq : 'manual';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('תזמון E2E',
                style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.schedule, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: validFreq,
                isDense: true,
                items: _freqOptions.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(_freqLabels[f]!, style: const TextStyle(fontFamily: 'Heebo')),
                )).toList(),
                onChanged: (val) => _saveSchedule(val!, time),
              ),
              if (validFreq != 'manual') ...[
                const SizedBox(width: 12),
                const Text('בשעה ', style: TextStyle(fontFamily: 'Heebo', fontSize: 13)),
                GestureDetector(
                  onTap: () => _pickTime(validFreq),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(time, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(String freq) async {
    final sched = _schedule?['schedule'] as Map<String, dynamic>?;
    final current = sched?['time'] as String? ?? '03:00';
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour:   int.tryParse(parts.firstOrNull ?? '3') ?? 3,
        minute: int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0,
      ),
    );
    if (picked != null && mounted) {
      final timeStr = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      await _saveSchedule(freq, timeStr);
    }
  }

  Future<void> _saveSchedule(String freq, String time) async {
    await _api
        .setE2eSchedule({'frequency': freq, 'time': time})
        .catchError((_) => false);
    _load();
  }

  Widget _exportCard() {
    final url = _api.surveysExportUrl();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ייצוא סקרים',
                    style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo')),
                Text('הורד קובץ CSV של כל תשובות הסקרים',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Heebo')),
              ],
            ),
          ),
          TextButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('ייצא CSV', style: TextStyle(fontFamily: 'Heebo')),
            onPressed: () => _openExportUrl(url),
          ),
        ]),
      ),
    );
  }

  Future<void> _openExportUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הכתובת הועתקה ללוח', style: TextStyle(fontFamily: 'Heebo')),
          ),
        );
      }
    }
  }
}
