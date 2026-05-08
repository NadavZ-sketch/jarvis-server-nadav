import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_settings.dart';
import '../main.dart' show JC;
import '../services/api_service.dart';
import '../transitions/slide_fade_route.dart';
import '../widgets/empty_state.dart';

// ─── List screen ───────────────────────────────────────────────────────────

class E2eReportsScreen extends StatefulWidget {
  final AppSettings settings;
  const E2eReportsScreen({super.key, required this.settings});

  @override
  State<E2eReportsScreen> createState() => _E2eReportsScreenState();
}

class _E2eReportsScreenState extends State<E2eReportsScreen> {
  late final ApiService _api = ApiService(widget.settings);
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final reports = await _api.getE2eReports();
      if (!mounted) return;
      setState(() { _reports = reports; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiService.friendlyError(e); _loading = false; });
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt).inDays;
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      if (diff == 0) return 'היום $hh:$mm';
      if (diff == 1) return 'אתמול $hh:$mm';
      return '${dt.day}/${dt.month}/${dt.year} $hh:$mm';
    } catch (_) { return iso; }
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF22C55E);
    if (score >= 60) return const Color(0xFFEAB308);
    return JC.cancelRed;
  }

  Future<void> _open(Map<String, dynamic> report) async {
    final updated = await Navigator.push<bool>(
      context,
      SlideFadeRoute(page: E2eReportDetailScreen(
        runId:    report['run_id'] as String,
        date:     _formatDate(report['created_at'] as String?),
        settings: widget.settings,
      )),
    );
    if (updated == true) _load();
  }

  Future<void> _delete(String runId) async {
    try {
      await _api.deleteE2eRun(runId);
      if (!mounted) return;
      setState(() => _reports.removeWhere((r) => r['run_id'] == runId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאת מחיקה: ${ApiService.friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: JC.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'דוחות בדיקות E2E',
            style: TextStyle(color: JC.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w600, fontFamily: 'Heebo', letterSpacing: 0.3),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _reports.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: JC.blue400));
    }
    if (_error != null && _reports.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: JC.cancelRed, size: 48),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('נסה שוב')),
        ]),
      ));
    }
    if (_reports.isEmpty) {
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'אין דוחות עדיין',
        subtitle: 'שלח "בצע בדיקות קצה" מהשיחה כדי להתחיל',
      );
    }
    return RefreshIndicator(
      color: JC.blue400,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _reports.length,
        itemBuilder: (_, i) => _buildCard(_reports[i]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r) {
    final score    = (r['score'] as int?) ?? 0;
    final critical = (r['critical'] as int?) ?? 0;
    final high     = (r['high'] as int?) ?? 0;
    final medium   = (r['medium'] as int?) ?? 0;
    final low      = (r['low'] as int?) ?? 0;
    final count    = (r['count'] as int?) ?? 0;
    final date     = _formatDate(r['created_at'] as String?);
    final runId    = r['run_id'] as String;

    return Dismissible(
      key: Key(runId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await _confirmDelete() ?? false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: JC.cancelRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: JC.cancelRed, size: 26),
      ),
      onDismissed: (_) => _delete(runId),
      child: InkWell(
        onTap: () => _open(r),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JC.border, width: 0.5),
          ),
          child: Row(children: [
            // Score badge
            Container(
              width: 56, height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _scoreColor(score).withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: _scoreColor(score), width: 1.5),
              ),
              child: Text('$score',
                  style: TextStyle(color: _scoreColor(score),
                      fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                    style: const TextStyle(color: JC.textPrimary,
                        fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
                const SizedBox(height: 4),
                Text('$count ממצאים · 🔴 $critical · 🟠 $high · 🟡 $medium · 🟢 $low',
                    style: const TextStyle(color: JC.textMuted,
                        fontSize: 12, fontFamily: 'Heebo')),
              ],
            )),
            const Icon(Icons.chevron_left_rounded, color: JC.textMuted),
          ]),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: const Text('למחוק את הדוח?',
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
          content: const Text('הפעולה לא הפיכה.',
              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('מחק', style: TextStyle(color: JC.cancelRed))),
          ],
        ),
      ),
    );
  }
}

// ─── Detail screen ─────────────────────────────────────────────────────────

class E2eReportDetailScreen extends StatefulWidget {
  final String runId;
  final String date;
  final AppSettings settings;
  const E2eReportDetailScreen({
    super.key, required this.runId, required this.date, required this.settings,
  });

  @override
  State<E2eReportDetailScreen> createState() => _E2eReportDetailScreenState();
}

class _E2eReportDetailScreenState extends State<E2eReportDetailScreen> {
  late final ApiService _api = ApiService(widget.settings);
  List<Map<String, dynamic>> _findings = [];
  Map<String, int> _counts = {};
  int _score = 0;
  bool _loading = true;
  String? _error;
  bool _actionLoading = false;

  // Selection state
  final Set<String> _selectedFingerprints = {};
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _api.getE2eRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _findings = List<Map<String, dynamic>>.from(data['findings'] ?? []);
        _counts   = Map<String, int>.from(data['counts'] ?? {});
        _score    = (data['score'] as int?) ?? 0;
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = ApiService.friendlyError(e); _loading = false; });
    }
  }

  bool _isDone(Map<String, dynamic> f) => (f['status'] as String?) == 'done';
  String? _fp(Map<String, dynamic> f) => f['fingerprint'] as String?;

  List<Map<String, dynamic>> get _visibleFindings =>
      _showDone ? _findings : _findings.where((f) => !_isDone(f)).toList();

  void _toggleSelection(Map<String, dynamic> f) {
    if (_isDone(f)) return;
    final fp = _fp(f);
    if (fp == null) return;
    setState(() {
      if (_selectedFingerprints.contains(fp)) {
        _selectedFingerprints.remove(fp);
      } else {
        _selectedFingerprints.add(fp);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedFingerprints
        ..clear()
        ..addAll(_findings
            .where((f) => !_isDone(f))
            .map(_fp)
            .whereType<String>());
    });
  }

  void _deselectAll() => setState(() => _selectedFingerprints.clear());

  Future<void> _generatePromptFromSelected() async {
    if (_selectedFingerprints.isEmpty || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      final prompt = await _api.generatePromptForSelected(
          widget.runId, _selectedFingerprints.toList());
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: prompt));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            '📋 פרומפט ל-${_selectedFingerprints.length} ממצאים הועתק — הדבק בקלוד קוד')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: ${ApiService.friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _markSelectedDone() async {
    if (_selectedFingerprints.isEmpty || _actionLoading) return;
    setState(() => _actionLoading = true);
    try {
      await _api.markFindingsDone(widget.runId, _selectedFingerprints.toList());
      if (!mounted) return;
      final marked = Set<String>.from(_selectedFingerprints);
      setState(() {
        for (int i = 0; i < _findings.length; i++) {
          final fp = _fp(_findings[i]);
          if (fp != null && marked.contains(fp)) {
            _findings[i] = Map<String, dynamic>.from(_findings[i])
              ..['status'] = 'done';
          }
        }
        _selectedFingerprints.clear();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${marked.length} ממצאים סומנו כבוצע')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: ${ApiService.friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _deleteRun() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: const Text('למחוק את הדוח הזה?',
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
          content: const Text('כל הממצאים יוסרו לצמיתות.',
              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('מחק', style: TextStyle(color: JC.cancelRed))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteE2eRun(widget.runId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאת מחיקה: ${ApiService.friendlyError(e)}')),
      );
    }
  }

  Color _sevColor(String sev) {
    switch (sev) {
      case 'critical': return JC.cancelRed;
      case 'high':     return const Color(0xFFF97316);
      case 'medium':   return const Color(0xFFEAB308);
      default:         return const Color(0xFF22C55E);
    }
  }

  String _sevEmoji(String sev) {
    switch (sev) {
      case 'critical': return '🔴';
      case 'high':     return '🟠';
      case 'medium':   return '🟡';
      default:         return '🟢';
    }
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF22C55E);
    if (score >= 60) return const Color(0xFFEAB308);
    return JC.cancelRed;
  }

  int get _doneCount => _findings.where(_isDone).length;
  int get _activeCount => _findings.length - _doneCount;

  @override
  Widget build(BuildContext context) {
    final hasSelected = _selectedFingerprints.isNotEmpty;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: JC.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.date,
            style: const TextStyle(color: JC.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
          ),
          actions: [
            if (hasSelected)
              TextButton(
                onPressed: _deselectAll,
                child: const Text('בטל בחירה',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 13)),
              )
            else
              TextButton(
                onPressed: _activeCount == 0 ? null : _selectAll,
                child: const Text('בחר הכל',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 13)),
              ),
            IconButton(
              tooltip: 'מחק דוח',
              icon: const Icon(Icons.delete_outline, color: JC.cancelRed),
              onPressed: _deleteRun,
            ),
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar: hasSelected ? _buildActionBar() : null,
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      decoration: BoxDecoration(
        color: JC.surface,
        border: Border(top: BorderSide(color: JC.border, width: 0.5)),
      ),
      child: _actionLoading
          ? const Center(child: SizedBox(height: 44,
              child: CircularProgressIndicator(color: JC.blue400)))
          : Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _markSelectedDone,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
                  label: Text('בוצע (${_selectedFingerprints.length})',
                      style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF22C55E),
                    side: const BorderSide(color: Color(0xFF22C55E)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generatePromptFromSelected,
                  icon: const Icon(Icons.content_copy_rounded, size: 17),
                  label: Text('פרומפט (${_selectedFingerprints.length})',
                      style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.blue500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: JC.blue400));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
      ));
    }

    final critical = _counts['critical'] ?? 0;
    final high     = _counts['high']     ?? 0;
    final medium   = _counts['medium']   ?? 0;
    final low      = _counts['low']      ?? 0;

    final byOrder = ['critical', 'high', 'medium', 'low'];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final f in _visibleFindings) {
      final s = (f['severity'] as String?) ?? 'low';
      groups.putIfAbsent(s, () => []).add(f);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JC.border, width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 64, height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _scoreColor(_score).withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _scoreColor(_score), width: 2),
                ),
                child: Text('$_score',
                    style: TextStyle(color: _scoreColor(_score),
                        fontSize: 22, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ציון כללי',
                      style: TextStyle(color: JC.textMuted,
                          fontSize: 12, fontFamily: 'Heebo')),
                  const SizedBox(height: 4),
                  Text('$_activeCount פתוחים${_doneCount > 0 ? ' · $_doneCount ✅ בוצע' : ''}',
                      style: const TextStyle(color: JC.textPrimary,
                          fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
                  const SizedBox(height: 6),
                  Text('🔴 $critical · 🟠 $high · 🟡 $medium · 🟢 $low',
                      style: const TextStyle(color: JC.textSecondary,
                          fontSize: 13, fontFamily: 'Heebo')),
                ],
              )),
            ]),
            if (_doneCount > 0) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _showDone = !_showDone),
                child: Row(children: [
                  Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 15, color: JC.textMuted),
                  const SizedBox(width: 5),
                  Text(_showDone ? 'הסתר ממצאים שבוצעו' : 'הצג ממצאים שבוצעו ($_doneCount)',
                      style: const TextStyle(color: JC.textMuted,
                          fontSize: 12, fontFamily: 'Heebo')),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            const Text('בחר ממצאים ← צור פרומפט לקלוד או סמן כבוצע',
                style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
          ]),
        ),
        const SizedBox(height: 16),

        if (_visibleFindings.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('🎉 אין ממצאים פתוחים — הכל תקין!',
                style: TextStyle(color: JC.textSecondary,
                    fontSize: 16, fontFamily: 'Heebo'))),
          )
        else
          for (final sev in byOrder)
            if (groups[sev] != null) ..._sectionFor(sev, groups[sev]!),
      ],
    );
  }

  List<Widget> _sectionFor(String sev, List<Map<String, dynamic>> items) {
    final sevLabel = {
      'critical': 'קריטי', 'high': 'גבוה', 'medium': 'בינוני', 'low': 'נמוך',
    }[sev]!;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Row(children: [
          Text('${_sevEmoji(sev)} $sevLabel',
              style: TextStyle(color: _sevColor(sev),
                  fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
          const SizedBox(width: 8),
          Text('(${items.length})',
              style: const TextStyle(color: JC.textMuted,
                  fontSize: 12, fontFamily: 'Heebo')),
        ]),
      ),
      ...items.map(_findingCard),
    ];
  }

  Widget _findingCard(Map<String, dynamic> f) {
    final target   = (f['target'] as String?) ?? '';
    final finding  = (f['finding'] as String?) ?? '';
    final fix      = (f['recommendation'] as String?) ?? '';
    final cat      = (f['category'] as String?) ?? '';
    final lat      = f['latency_ms'] as int?;
    final status   = (f['status'] as String?) ?? 'new';
    final done     = status == 'done';
    final fp       = _fp(f);
    final selected = fp != null && _selectedFingerprints.contains(fp);

    final statusBadge = done
        ? const _Chip(text: '✅ בוצע', color: Color(0xFF22C55E))
        : {
            'regression': const _Chip(text: '🔁 רגרסיה', color: Color(0xFFF97316)),
            'flaky':      const _Chip(text: '📉 פלייקי', color: Color(0xFFEAB308)),
            'new':        const _Chip(text: '🆕 חדש',    color: Color(0xFF3B82F6)),
          }[status] ?? const SizedBox.shrink();

    return Opacity(
      opacity: done ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: done ? null : () => _toggleSelection(f),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? JC.blue500.withOpacity(0.07) : JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? JC.blue400 : JC.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!done) Padding(
              padding: const EdgeInsets.only(top: 1, left: 6),
              child: SizedBox(
                width: 20, height: 20,
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelection(f),
                  activeColor: JC.blue500,
                  side: BorderSide(color: JC.textMuted.withOpacity(0.5), width: 1.2),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _Chip(text: cat, color: JC.blue400),
                  if (lat != null) _Chip(text: '$lat ms', color: JC.textMuted),
                  statusBadge,
                ]),
                const SizedBox(height: 8),
                Text(target,
                    style: TextStyle(
                        color: done ? JC.textMuted : JC.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600,
                        fontFamily: 'Heebo', letterSpacing: 0.2,
                        decoration: done ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 6),
                Text(finding,
                    style: const TextStyle(color: JC.textSecondary,
                        fontSize: 13, fontFamily: 'Heebo', height: 1.4)),
                if (fix.isNotEmpty && !done) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('✅ $fix',
                        style: const TextStyle(color: Color(0xFF22C55E),
                            fontSize: 12, fontFamily: 'Heebo', height: 1.4)),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4), width: 0.6),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11,
              fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
    );
  }
}
