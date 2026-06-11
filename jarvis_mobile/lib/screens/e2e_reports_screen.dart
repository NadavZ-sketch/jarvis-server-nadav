import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_settings.dart';
import '../main.dart' show JC;
import '../services/api_service.dart';
import '../transitions/slide_fade_route.dart';
import '../widgets/empty_state.dart';

// ─── Localised labels ──────────────────────────────────────────────────────
const _sevLabel  = {'critical':'קריטי','high':'גבוה','medium':'בינוני','low':'נמוך'};
const _sevEmoji  = {'critical':'🔴','high':'🟠','medium':'🟡','low':'🟢'};
const _statLabel = {'new':'🆕 חדש','regression':'🔁 רגרסיה','flaky':'📉 פלייקי','done':'✅ בוצע'};
const _catHe     = {'API':'ממשק API','Flutter UI':'Flutter','Static':'קוד סטטי',
                    'Hebrew Quality':'איכות עברית','Other':'כללי',
                    // code-scan categories
                    'security':'אבטחה','reliability':'אמינות','performance':'ביצועים',
                    'ux_backend':'חוויית שימוש','bug':'באג','quality':'איכות',
                    'ui':'ממשק','accessibility':'נגישות'};

// ─── List screen ───────────────────────────────────────────────────────────

class E2eReportsScreen extends StatefulWidget {
  final AppSettings settings;
  final bool embedded;
  const E2eReportsScreen({super.key, required this.settings, this.embedded = false});

  @override
  State<E2eReportsScreen> createState() => _E2eReportsScreenState();
}

class E2eReportsPanel extends StatelessWidget {
  final AppSettings settings;
  const E2eReportsPanel({super.key, required this.settings});

  @override
  Widget build(BuildContext context) =>
      E2eReportsScreen(settings: settings, embedded: true);
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

  // Labels a report as a standalone code scan vs a full end-to-end run.
  Widget _kindBadge(String kind) {
    final isScan = kind == 'code_scan';
    final color  = isScan ? const Color(0xFFA855F7) : JC.blue400;
    final label  = isScan ? '🔍 סריקת קוד' : '🧪 בדיקת קצה';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.6),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10,
              fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
    );
  }

  bool _scanning = false;

  // Run a standalone code-error scan; it's saved as a report and shows in this list.
  Future<void> _runScan() async {
    if (_scanning) return;
    if (mounted) setState(() => _scanning = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔍 סורק שגיאות קוד...')),
    );
    try {
      await _api.runCodeScan();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ הסריקה נשמרה כדוח — פתח אותו כדי לשלוח לקלוד')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאת סריקה: ${ApiService.friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
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
    if (widget.embedded) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: _buildBody(),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: JC.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'דוחות בדיקות E2E',
            style: TextStyle(color: JC.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w600, fontFamily: 'Heebo', letterSpacing: 0.3),
          ),
          actions: [
            IconButton(
              tooltip: 'סרוק שגיאות קוד',
              icon: _scanning
                  ? SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: JC.blue400))
                  : Icon(Icons.bug_report_outlined, color: JC.textPrimary),
              onPressed: _scanning ? null : _runScan,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _reports.isEmpty) {
      // When embedded inside a scrolling parent (control center) the incoming
      // vertical constraints are unbounded, so a bare Center could expand toward
      // infinity and overflow. Give it a fixed-height box instead.
      final spinner = CircularProgressIndicator(color: JC.blue400);
      if (widget.embedded) {
        return SizedBox(height: 120, child: Center(child: spinner));
      }
      return Center(child: spinner);
    }
    if (_error != null && _reports.isEmpty) {
      final errorBody = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.error_outline, color: JC.cancelRed, size: 48),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
          const SizedBox(height: 16),
          TextButton(onPressed: _load, child: const Text('נסה שוב')),
        ]),
      );
      // Embedded: avoid an unbounded Center (overflows the parent ListView).
      if (widget.embedded) return errorBody;
      return Center(child: errorBody);
    }
    if (_reports.isEmpty) {
      if (widget.embedded) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: Text(
            'אין דוחות עדיין. שלח "בצע בדיקות קצה" מהשיחה כדי להתחיל.',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
          ),
        );
      }
      return const EmptyState(
        icon: Icons.fact_check_outlined,
        title: 'אין דוחות עדיין',
        subtitle: 'שלח "בצע בדיקות קצה" מהשיחה כדי להתחיל',
      );
    }
    if (widget.embedded) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _reports.length,
        itemBuilder: (_, i) => _buildCard(_reports[i], _reports.length - i),
      );
    }
    return RefreshIndicator(
      color: JC.blue400,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _reports.length,
        itemBuilder: (_, i) => _buildCard(_reports[i], _reports.length - i),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> r, int reportNumber) {
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
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 24),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: JC.cancelRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: JC.cancelRed, size: 26),
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
                color: _scoreColor(score).withValues(alpha: 0.15),
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
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: JC.blue400.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: JC.blue400.withValues(alpha: 0.35), width: 0.6),
                    ),
                    child: Text('#$reportNumber',
                        style: TextStyle(color: JC.blue400,
                            fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
                  ),
                  const SizedBox(width: 8),
                  _kindBadge((r['kind'] as String?) ?? 'e2e'),
                  const SizedBox(width: 8),
                  Expanded(child: Text(date,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: JC.textPrimary,
                          fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Heebo'))),
                ]),
                const SizedBox(height: 4),
                Text('$count ממצאים · 🔴 $critical · 🟠 $high · 🟡 $medium · 🟢 $low',
                    style: TextStyle(color: JC.textMuted,
                        fontSize: 12, fontFamily: 'Heebo')),
              ],
            )),
            Icon(Icons.chevron_left_rounded, color: JC.textMuted),
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
          title: Text('למחוק את הדוח?',
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
          content: Text('הפעולה לא הפיכה.',
              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text('מחק', style: TextStyle(color: JC.cancelRed))),
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

  // Filter state
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _sevFilter    = {};
  final Set<String> _statusFilter = {};
  final Set<String> _catFilter    = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() =>
        setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

  Set<String> get _availableCategories =>
      _findings.map((f) => (f['category'] as String?) ?? '').where((c) => c.isNotEmpty).toSet();

  List<Map<String, dynamic>> get _filteredFindings {
    return _visibleFindings.where((f) {
      if (_sevFilter.isNotEmpty) {
        final sev = (f['severity'] as String?) ?? 'low';
        if (!_sevFilter.contains(sev)) return false;
      }
      if (_statusFilter.isNotEmpty) {
        final st = (f['status'] as String?) ?? 'new';
        if (!_statusFilter.contains(st)) return false;
      }
      if (_catFilter.isNotEmpty) {
        final cat = (f['category'] as String?) ?? '';
        if (!_catFilter.contains(cat)) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final finding = (f['finding'] as String? ?? '').toLowerCase();
        final target  = (f['target'] as String? ?? '').toLowerCase();
        final rec     = (f['recommendation'] as String? ?? '').toLowerCase();
        if (!finding.contains(_searchQuery) &&
            !target.contains(_searchQuery) &&
            !rec.contains(_searchQuery)) return false;
      }
      return true;
    }).toList();
  }

  bool get _hasActiveFilter =>
      _sevFilter.isNotEmpty || _statusFilter.isNotEmpty ||
      _catFilter.isNotEmpty || _searchQuery.isNotEmpty;

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() {
      _sevFilter.clear();
      _statusFilter.clear();
      _catFilter.clear();
    });
  }

  void _toggleFilter(Set<String> group, String value) =>
      setState(() => group.contains(value) ? group.remove(value) : group.add(value));

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
        ..addAll(_filteredFindings
            .where((f) => !_isDone(f))
            .map(_fp)
            .whereType<String>());
    });
  }

  void _deselectAll() => setState(() => _selectedFingerprints.clear());

  Future<void> _generatePromptFromSelected() async {
    if (_selectedFingerprints.isEmpty || _actionLoading) return;
    setState(() => _actionLoading = true);
    final fps = Set<String>.from(_selectedFingerprints);
    try {
      final prompt = await _api.generatePromptForSelected(
          widget.runId, fps.toList());
      if (!mounted) return;
      if (prompt.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('השרת החזיר פרומפט ריק — נסה שוב')),
        );
        return;
      }
      await Clipboard.setData(ClipboardData(text: prompt));

      // Auto-mark as done — fire-and-forget; a failure here must not hide the copied prompt
      try {
        await _api.markFindingsDone(widget.runId, fps.toList());
        if (mounted) {
          setState(() {
            for (int i = 0; i < _findings.length; i++) {
              final fp = _fp(_findings[i]);
              if (fp != null && fps.contains(fp)) {
                _findings[i] = Map<String, dynamic>.from(_findings[i])
                  ..['status'] = 'done';
              }
            }
            _selectedFingerprints.clear();
          });
        }
      } catch (markErr) {
        if (mounted) {
          setState(() => _selectedFingerprints.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                '📋 פרומפט הועתק — לא הצלחנו לסמן כהושלם (${ApiService.friendlyError(markErr)})')),
          );
          return;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            '📋 פרומפט ל-${fps.length} ממצאים הועתק וסומן כהושלם — הדבק בקלוד קוד')),
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

  void _showFindingExplanation(BuildContext ctx, Map<String, dynamic> f) {
    final sev     = (f['severity'] as String?) ?? 'low';
    final finding = (f['finding'] as String?) ?? '';
    final rec     = (f['recommendation'] as String?) ?? '';
    final cat     = (f['category'] as String?) ?? '';
    final done    = (f['status'] as String?) == 'done';
    final catHe   = _catHe[cat] ?? cat;
    final fp      = _fp(f);
    final selected = fp != null && _selectedFingerprints.contains(fp);

    const impactMap = {
      'critical': 'בעיה קריטית — עלולה לשבש את פעולת היישום ולמנוע מהמשתמש להשתמש בו כראוי.',
      'high':     'בעיה חשובה — עלולה לגרום לתקלות תכופות ולפגוע בפונקציות מרכזיות של האפליקציה.',
      'medium':   'בעיה בינונית — עלולה לגרום לאי-נוחות מדי פעם, אך לא משבשת שימוש יומיומי.',
      'low':      'בעיה קלה — שיפור מומלץ שיכול לשפר את חוויית השימוש.',
    };
    final impact = impactMap[sev] ?? '';

    showModalBottomSheet(
      context: ctx,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: JC.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              )),
              const SizedBox(height: 16),
              Row(children: [
                _Chip(text: catHe, color: JC.blue400),
                const SizedBox(width: 8),
                _Chip(
                  text: '${_sevEmoji[sev] ?? ''} ${_sevLabel[sev] ?? sev}',
                  color: _sevColor(sev),
                ),
                if (done) ...[
                  const SizedBox(width: 8),
                  const _Chip(text: '✅ בוצע', color: Color(0xFF22C55E)),
                ],
              ]),
              const SizedBox(height: 16),
              Text('מה הבעיה?',
                  style: TextStyle(color: JC.textSecondary, fontSize: 11,
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600,
                      letterSpacing: 0.4)),
              const SizedBox(height: 5),
              Text(finding,
                  style: TextStyle(color: JC.textPrimary, fontSize: 14,
                      fontFamily: 'Heebo', height: 1.5)),
              const SizedBox(height: 14),
              Text('מה זה גורם?',
                  style: TextStyle(color: JC.textSecondary, fontSize: 11,
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600,
                      letterSpacing: 0.4)),
              const SizedBox(height: 5),
              Text(impact,
                  style: TextStyle(color: _sevColor(sev), fontSize: 13,
                      fontFamily: 'Heebo', height: 1.45)),
              if (rec.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('איך לתקן?',
                    style: TextStyle(color: JC.textSecondary, fontSize: 11,
                        fontFamily: 'Heebo', fontWeight: FontWeight.w600,
                        letterSpacing: 0.4)),
                const SizedBox(height: 5),
                Text(rec,
                    style: const TextStyle(color: Color(0xFF22C55E), fontSize: 13,
                        fontFamily: 'Heebo', height: 1.45)),
              ],
              if (!done) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (fp != null) {
                        setState(() {
                          if (selected) {
                            _selectedFingerprints.remove(fp);
                          } else {
                            _selectedFingerprints.add(fp);
                          }
                        });
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: selected ? JC.textMuted : JC.blue400,
                      side: BorderSide(color: selected ? JC.border : JC.blue400, width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      selected ? 'בטל בחירה' : 'בחר לתיקון',
                      style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteRun() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: Text('למחוק את הדוח הזה?',
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
          content: Text('כל הממצאים יוסרו לצמיתות.',
              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text('מחק', style: TextStyle(color: JC.cancelRed))),
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
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: JC.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.date,
            style: TextStyle(color: JC.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
          ),
          actions: [
            if (hasSelected)
              TextButton(
                onPressed: _deselectAll,
                child: Text('בטל בחירה',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 13)),
              )
            else
              TextButton(
                onPressed: _activeCount == 0 ? null : _selectAll,
                child: Text('בחר הכל',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 13)),
              ),
            IconButton(
              tooltip: 'מחק דוח',
              icon: Icon(Icons.delete_outline, color: JC.cancelRed),
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
          ? Center(child: SizedBox(height: 44,
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
      return Center(child: CircularProgressIndicator(color: JC.blue400));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_error!, textAlign: TextAlign.center,
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
      ));
    }

    final critical = _counts['critical'] ?? 0;
    final high     = _counts['high']     ?? 0;
    final medium   = _counts['medium']   ?? 0;
    final low      = _counts['low']      ?? 0;

    final byOrder  = ['critical', 'high', 'medium', 'low'];
    final filtered = _filteredFindings;
    final groups   = <String, List<Map<String, dynamic>>>{};
    for (final f in filtered) {
      final s = (f['severity'] as String?) ?? 'low';
      groups.putIfAbsent(s, () => []).add(f);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      children: [
        // ── Header card ─────────────────────────────────────────────────
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
                width: 60, height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _scoreColor(_score).withValues(alpha: 0.15),
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
                  Text('$_activeCount פתוחים${_doneCount > 0 ? ' · $_doneCount ✅' : ''}',
                      style: TextStyle(color: JC.textPrimary,
                          fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
                  const SizedBox(height: 5),
                  Wrap(spacing: 10, children: [
                    if (critical > 0) Text('🔴 $critical קריטי',
                        style: TextStyle(color: _sevColor('critical'),
                            fontSize: 12, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                    if (high > 0) Text('🟠 $high גבוה',
                        style: TextStyle(color: _sevColor('high'),
                            fontSize: 12, fontFamily: 'Heebo')),
                    if (medium > 0) Text('🟡 $medium בינוני',
                        style: TextStyle(color: _sevColor('medium'),
                            fontSize: 12, fontFamily: 'Heebo')),
                    if (low > 0) Text('🟢 $low נמוך',
                        style: TextStyle(color: _sevColor('low'),
                            fontSize: 12, fontFamily: 'Heebo')),
                  ]),
                ],
              )),
            ]),
            if (_doneCount > 0) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _showDone = !_showDone),
                child: Row(children: [
                  Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 14, color: JC.textMuted),
                  const SizedBox(width: 5),
                  Text(_showDone ? 'הסתר שבוצעו' : 'הצג שבוצעו ($_doneCount)',
                      style: TextStyle(color: JC.textMuted,
                          fontSize: 12, fontFamily: 'Heebo')),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 10),

        // ── Search bar ──────────────────────────────────────────────────
        TextField(
          controller: _searchCtrl,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'חפש ממצא, קובץ או המלצה...',
            hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
            prefixIcon: Icon(Icons.search_rounded, color: JC.textMuted, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded, size: 18, color: JC.textMuted),
                    onPressed: _searchCtrl.clear,
                  )
                : null,
            filled: true,
            fillColor: JC.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: JC.border, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: JC.border, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: JC.blue400, width: 1),
            ),
          ),
          style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
        ),
        const SizedBox(height: 8),

        // ── Filter chips ────────────────────────────────────────────────
        _buildFilterChips(),
        if (_hasActiveFilter) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: _clearFilters,
              child: Text('נקה סינון',
                  style: TextStyle(color: JC.blue400,
                      fontSize: 12, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        const SizedBox(height: 8),

        // ── Findings ────────────────────────────────────────────────────
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(
                _hasActiveFilter ? 'אין ממצאים תואמים לסינון' : '🎉 אין ממצאים פתוחים — הכל תקין!',
                style: TextStyle(color: JC.textSecondary,
                    fontSize: 15, fontFamily: 'Heebo'))),
          )
        else
          for (final sev in byOrder)
            if (groups[sev] != null) ..._sectionFor(sev, groups[sev]!),
      ],
    );
  }

  Widget _buildFilterChips() {
    final cats = _availableCategories.toList()..sort();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        // Severity
        ..._buildChipGroup(
          items: ['critical', 'high', 'medium', 'low'],
          group: _sevFilter,
          labelFn: (v) => '${_sevEmoji[v] ?? ''} ${_sevLabel[v] ?? v}',
          colorFn: _sevColor,
        ),
        _divider(),
        // Status
        ..._buildChipGroup(
          items: ['new', 'regression', 'flaky'],
          group: _statusFilter,
          labelFn: (v) => _statLabel[v] ?? v,
          colorFn: (v) => const {'new': Color(0xFF3B82F6), 'regression': Color(0xFFF97316),
            'flaky': Color(0xFFEAB308)}[v] ?? JC.textMuted,
        ),
        if (cats.isNotEmpty) ...[
          _divider(),
          ..._buildChipGroup(
            items: cats,
            group: _catFilter,
            labelFn: (v) => _catHe[v] ?? v,
            colorFn: (_) => JC.blue400,
          ),
        ],
      ]),
    );
  }

  List<Widget> _buildChipGroup({
    required List<String> items,
    required Set<String> group,
    required String Function(String) labelFn,
    required Color Function(String) colorFn,
  }) {
    return items.map((v) {
      final active = group.contains(v);
      final col = colorFn(v);
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: GestureDetector(
          onTap: () => _toggleFilter(group, v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? col.withValues(alpha: 0.18) : JC.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? col : JC.border,
                width: active ? 1.2 : 0.6,
              ),
            ),
            child: Text(labelFn(v),
                style: TextStyle(
                    color: active ? col : JC.textMuted,
                    fontSize: 12, fontFamily: 'Heebo',
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ),
        ),
      );
    }).toList();
  }

  Widget _divider() => Container(
      height: 20, width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: JC.border);

  List<Widget> _sectionFor(String sev, List<Map<String, dynamic>> items) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(children: [
        Container(width: 3, height: 16,
            decoration: BoxDecoration(color: _sevColor(sev),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('${_sevLabel[sev] ?? sev} (${items.length})',
            style: TextStyle(color: _sevColor(sev),
                fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
      ]),
    ),
    ...items.map(_findingCard),
  ];

  Widget _findingCard(Map<String, dynamic> f) {
    final target   = (f['target'] as String?) ?? '';
    final finding  = (f['finding'] as String?) ?? '';
    final fix      = (f['recommendation'] as String?) ?? '';
    final cat      = (f['category'] as String?) ?? '';
    final lat      = f['latency_ms'] as int?;
    final sev      = (f['severity'] as String?) ?? 'low';
    final status   = (f['status'] as String?) ?? 'new';
    final done     = status == 'done';
    final fp       = _fp(f);
    final selected = fp != null && _selectedFingerprints.contains(fp);
    final catHe    = _catHe[cat] ?? cat;
    final statText = _statLabel[status] ?? status;

    return Opacity(
      opacity: done ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: () => _showFindingExplanation(context, f),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: selected ? JC.blue500.withValues(alpha: 0.06) : JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? JC.blue400 : JC.border,
              width: selected ? 1.5 : 0.5,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Severity stripe
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: _sevColor(sev),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Chips row
                    Row(children: [
                      _Chip(text: catHe, color: JC.blue400),
                      const SizedBox(width: 6),
                      _Chip(text: statText,
                          color: const {'🔁 רגרסיה': Color(0xFFF97316),
                            '📉 פלייקי': Color(0xFFEAB308),
                            '✅ בוצע': Color(0xFF22C55E),
                          }[statText] ?? const Color(0xFF3B82F6)),
                    ]),
                    const SizedBox(height: 8),
                    // Finding — the main content
                    Text(finding,
                        style: TextStyle(
                            color: done ? JC.textMuted : JC.textPrimary,
                            fontSize: 13, fontFamily: 'Heebo', height: 1.45,
                            decoration: done ? TextDecoration.lineThrough : null)),
                    // Fix recommendation
                    if (fix.isNotEmpty && !done) ...[
                      const SizedBox(height: 8),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.arrow_forward_rounded,
                            size: 14, color: Color(0xFF22C55E)),
                        const SizedBox(width: 5),
                        Expanded(child: Text(fix,
                            style: const TextStyle(color: Color(0xFF22C55E),
                                fontSize: 12, fontFamily: 'Heebo', height: 1.4))),
                      ]),
                    ],
                    // Footer: target + latency
                    if (target.isNotEmpty || lat != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (target.isNotEmpty) target.length > 50 ? '…${target.substring(target.length - 50)}' : target,
                          if (lat != null) '$lat ms',
                        ].join(' · '),
                        style: TextStyle(color: JC.textMuted,
                            fontSize: 11, fontFamily: 'Heebo'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ]),
                ),
              ),
              // Checkbox
              if (!done) Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 20, height: 20,
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelection(f),
                      activeColor: JC.blue500,
                      side: BorderSide(color: JC.textMuted.withValues(alpha: 0.5), width: 1.2),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ]),
          ),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.6),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontSize: 11,
              fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
    );
  }
}
