import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_settings.dart';
import '../../services/api_service.dart';

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
                  'מקרי בדיקה',
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo'),
                ),
              ),
              Text(
                '${_testCases.length}',
                style: const TextStyle(color: Colors.grey),
              ),
            ]),
            const SizedBox(height: 8),
            if (_testCases.isEmpty)
              const Text(
                'אין מקרי בדיקה',
                style: TextStyle(color: Colors.grey, fontFamily: 'Heebo'),
              )
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
                  title: Text(
                    name,
                    style: const TextStyle(fontFamily: 'Heebo', fontSize: 14),
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      onPressed: () => _runTest(tc['id'] as String),
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
      SnackBar(
        content: Text(
          'תוצאה: $status',
          style: const TextStyle(fontFamily: 'Heebo'),
        ),
      ),
    );
    _load();
  }

  Widget _scheduleCard() {
    final sched = _schedule?['schedule'] as Map<String, dynamic>?;
    final freq  = sched?['frequency'] as String? ?? 'לא מוגדר';
    final time  = sched?['time']      as String? ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'לוח זמנים — E2E',
              style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.schedule, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                '$freq${time.isNotEmpty ? " בשעה $time" : ""}',
                style: const TextStyle(fontFamily: 'Heebo'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _showScheduleEditor,
                child: const Text('ערוך', style: TextStyle(fontFamily: 'Heebo')),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _showScheduleEditor() async {
    final freqCtrl = TextEditingController(
      text: (_schedule?['schedule'] as Map?)?['frequency'] as String? ?? 'daily',
    );
    final timeCtrl = TextEditingController(
      text: (_schedule?['schedule'] as Map?)?['time'] as String? ?? '03:00',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'ערוך לוח זמנים',
          style: TextStyle(fontFamily: 'Heebo'),
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: freqCtrl,
            decoration: const InputDecoration(labelText: 'תדירות (daily / weekly)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: timeCtrl,
            decoration: const InputDecoration(labelText: 'שעה (HH:mm)'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('שמור'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _api
          .setE2eSchedule({'frequency': freqCtrl.text, 'time': timeCtrl.text})
          .catchError((_) => false);
      _load();
    }
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
                Text(
                  'ייצוא סקרים',
                  style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Heebo'),
                ),
                Text(
                  'הורד קובץ CSV של כל תשובות הסקרים',
                  style: TextStyle(
                    fontSize: 12, color: Colors.grey, fontFamily: 'Heebo',
                  ),
                ),
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
      // Fallback: copy to clipboard and notify
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'הכתובת הועתקה ללוח',
              style: TextStyle(fontFamily: 'Heebo'),
            ),
          ),
        );
      }
    }
  }
}
