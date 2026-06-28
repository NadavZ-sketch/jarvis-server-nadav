import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';
import 'improve_workshop.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TabImprove — Slice 3 of the Control Center redesign.
//
// Sections (RTL, Heebo, JC tokens only):
//   A. _load(): Future.wait over getE2eReports, fetchWeeklyScore, fetchProposals
//   B. "בריאות ובדיקות" — metrics grid + recent reports card + buttons
//   C. "סקרים ופידבקים" — round score badge + pills + action buttons
//   D. "אותות שיפור" — feedback-item cards from proposals (status=='proposal')
//   E. "Backlog שיפור" — all proposals as backlog-item cards with 5-step stepper
//   F. "יצירת שיפור" — TextField + "התחל תחקיר" → showImproveInterviewSheet
//
// Polling: adaptive 30 s timer (pause on background) + RefreshIndicator.
// All numbers cast via (x as num?)?.toInt() / ?.toDouble() — never `as int`.
// ─────────────────────────────────────────────────────────────────────────────

class TabImprove extends StatefulWidget {
  final AppSettings settings;
  const TabImprove({super.key, required this.settings});

  @override
  State<TabImprove> createState() => _TabImproveState();
}

class _TabImproveState extends State<TabImprove>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  List<Map<String, dynamic>> _reports = [];
  Map<String, dynamic> _weeklyScore = {};
  List<Map<String, dynamic>> _proposals = [];
  bool _loading = true;
  String? _error;

  // Polling
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 30);

  // Goal field for Section F
  final TextEditingController _goalCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _goalCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _load();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // ── A. Load ───────────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getE2eReports().catchError((_) => <Map<String, dynamic>>[]),
        _api.fetchWeeklyScore().catchError((_) => <String, dynamic>{}),
        _api.fetchProposals().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = List<Map<String, dynamic>>.from(results[0] as List);
        _weeklyScore = (results[1] as Map<String, dynamic>);
        _proposals = List<Map<String, dynamic>>.from(results[2] as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.friendlyError(e);
        _loading = false;
      });
    }
  }

  // ── Snack helpers ─────────────────────────────────────────────────────────
  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
        backgroundColor: color ?? JC.green500,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _snackError(String msg) => _snack(msg, color: JC.cancelRed);

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: JC.cancelRed),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: JC.cancelRed, fontFamily: 'Heebo'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _load,
            child: const Text('נסה שוב',
                style: TextStyle(fontFamily: 'Heebo')),
          ),
        ]),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // B. Health & Tests
            _sectionHeader('בריאות ובדיקות'),
            const SizedBox(height: 8),
            _healthMetricsGrid(),
            const SizedBox(height: 8),
            _reportsCard(),
            const SizedBox(height: 18),

            // C. Surveys & Feedback
            _sectionHeader('סקרים ופידבקים'),
            const SizedBox(height: 8),
            _surveyCard(),
            const SizedBox(height: 18),

            // D. Improvement signals
            _sectionHeader('אותות שיפור'),
            const SizedBox(height: 8),
            _signalsSection(),
            const SizedBox(height: 18),

            // E. Backlog
            _sectionHeader('Backlog שיפור'),
            const SizedBox(height: 8),
            _backlogSection(),
            const SizedBox(height: 18),

            // F. Create improvement
            _sectionHeader('יצירת שיפור'),
            const SizedBox(height: 8),
            _createImproveCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── B. Health metrics grid ─────────────────────────────────────────────────
  Widget _healthMetricsGrid() {
    final latestReport = _reports.isNotEmpty ? _reports.first : null;
    final scoreRaw = latestReport != null
        ? (latestReport['score'] as num?)?.toInt()
        : null;
    final scoreStr = scoreRaw != null ? '$scoreRaw' : '—';
    final scoreColor = scoreRaw == null
        ? JC.textMuted
        : scoreRaw >= 80
            ? JC.green500
            : scoreRaw >= 50
                ? JC.amber400
                : JC.cancelRed;

    final critical = (latestReport?['critical'] as num?)?.toInt() ?? 0;
    final high = (latestReport?['high'] as num?)?.toInt() ?? 0;
    final findings = latestReport != null ? critical + high : null;
    final findingsStr = findings != null ? '$findings' : '—';
    final findingsColor = findings == null
        ? JC.textMuted
        : findings == 0
            ? JC.green500
            : findings <= 2
                ? JC.amber400
                : JC.cancelRed;

    return Row(
      children: [
        Expanded(
          child: _metricBox(
            label: 'ציון E2E',
            value: scoreStr,
            valueColor: scoreColor,
            note: latestReport != null ? 'עדכון אחרון' : 'אין נתונים',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricBox(
            label: 'ממצאים',
            value: findingsStr,
            valueColor: findingsColor,
            note: 'קריטי + גבוה',
          ),
        ),
      ],
    );
  }

  Widget _metricBox({
    required String label,
    required String value,
    required Color valueColor,
    required String note,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border.all(color: JC.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: valueColor,
                  height: 1)),
          const SizedBox(height: 5),
          Text(note,
              style: TextStyle(
                  fontFamily: 'Heebo', fontSize: 10, color: JC.textMuted)),
        ],
      ),
    );
  }

  Widget _reportsCard() {
    final recent = _reports.take(2).toList();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent.isEmpty)
            Text(
              'אין דוחות E2E',
              style: TextStyle(
                  fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
            )
          else
            ...recent.map((r) {
              final ts = (r['created_at'] as String?) ?? '';
              final time = ts.length >= 16 ? ts.substring(11, 16) : ts;
              final crit = (r['critical'] as num?)?.toInt() ?? 0;
              final hi = (r['high'] as num?)?.toInt() ?? 0;
              final med = (r['medium'] as num?)?.toInt() ?? 0;
              final lo = (r['low'] as num?)?.toInt() ?? 0;
              final accentColor = crit > 0 ? JC.cancelRed : JC.textMuted;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _eventRow(
                  accentColor: accentColor,
                  child: Text(
                    '$time · 🔴$crit 🟠$hi 🟡$med 🔵$lo',
                    style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 12,
                        color: JC.textSecondary),
                  ),
                ),
              );
            }).toList(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                label: 'הרץ בדיקות',
                color: JC.green500,
                onPressed: _runE2E,
              ),
              _actionButton(
                label: 'סרוק קוד',
                color: JC.blue400,
                onPressed: _runCodeScan,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runE2E() async {
    try {
      await _api.triggerE2E();
      _snack('בדיקות הופעלו');
    } catch (e) {
      _snackError(ApiService.friendlyError(e));
    }
  }

  Future<void> _runCodeScan() async {
    try {
      await _api.runCodeScan();
      _snack('סריקת קוד הושלמה');
      await _load();
    } catch (e) {
      _snackError(ApiService.friendlyError(e));
    }
  }

  // ── C. Surveys & Feedback ─────────────────────────────────────────────────
  Widget _surveyCard() {
    final scoreRaw = (_weeklyScore['score'] as num?)?.toInt();
    final ups = (_weeklyScore['ups'] as num?)?.toInt() ?? 0;
    final downs = (_weeklyScore['downs'] as num?)?.toInt() ?? 0;
    final total = (_weeklyScore['total'] as num?)?.toInt() ?? 0;
    final scoreStr = scoreRaw != null ? '$scoreRaw' : '—';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'תמונת קול המשתמש',
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "ג'רוויס מאחד סקרים, thumbs down, הערות חופשיות ותוצאות שימוש לאותות שיפור.",
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 11,
                          color: JC.textMuted,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Round score badge
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scoreRaw == null
                        ? JC.border
                        : scoreRaw >= 70
                            ? JC.green500
                            : scoreRaw >= 40
                                ? JC.amber400
                                : JC.cancelRed,
                    width: 2.5,
                  ),
                  color: JC.surfaceAlt,
                ),
                alignment: Alignment.center,
                child: Text(
                  scoreStr,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w900,
                    fontSize: scoreRaw != null ? 20 : 16,
                    color: scoreRaw == null
                        ? JC.textMuted
                        : scoreRaw >= 70
                            ? JC.green500
                            : scoreRaw >= 40
                                ? JC.amber400
                                : JC.cancelRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Pills
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill('$ups חיובי', JC.green500),
              _pill('$downs שלילי', JC.cancelRed),
              _pill('סה"כ $total', JC.blue400),
            ],
          ),
          const SizedBox(height: 10),
          // Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                label: 'התחל סקר חכם',
                color: JC.blue400,
                onPressed: () => showSmartSurveySheet(
                    context, _api, widget.settings.userName),
              ),
              _actionButton(
                label: 'הפק הצעות',
                color: JC.green500,
                onPressed: _generateBacklog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _generateBacklog() async {
    try {
      await _api.generateBacklog();
      await _load();
      _snack('הופקו הצעות');
    } catch (e) {
      _snackError(ApiService.friendlyError(e));
    }
  }

  // ── D. Improvement signals (proposals) ────────────────────────────────────
  Widget _signalsSection() {
    // Take proposals with status=='proposal', fallback to all
    var signals = _proposals
        .where((p) => (p['status'] as String? ?? '') == 'proposal')
        .toList();
    if (signals.isEmpty) signals = _proposals;
    final display = signals.take(4).toList();

    if (display.isEmpty) {
      return _eventRow(
        accentColor: JC.textMuted,
        child: Text(
          'אין אותות שיפור זמינים',
          style: TextStyle(
              fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
        ),
      );
    }

    return Column(
      children: display.map((proposal) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _feedbackItemCard(proposal),
      )).toList(),
    );
  }

  Widget _feedbackItemCard(Map<String, dynamic> proposal) {
    final title = (proposal['title'] as String? ?? '—');
    final whyNow = (proposal['why_now'] as String? ?? '').trim();
    final sub = whyNow.isNotEmpty ? whyNow : 'מקור: שימוש';
    final scores = proposal['scores'] as Map<String, dynamic>? ?? {};
    final impact = (scores['impact'] as num?)?.toInt();
    final confidence = (scores['confidence'] as num?)?.toInt();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: JC.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: TextStyle(
                fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (impact != null) _pill('Impact $impact', JC.amber400),
              if (confidence != null) _pill('Confidence $confidence', JC.blue400),
            ],
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'התחל תחקיר',
            color: JC.blue400,
            onPressed: () => showImproveInterviewSheet(
              context,
              _api,
              initialGoal: title,
            ),
          ),
        ],
      ),
    );
  }

  // ── E. Backlog ─────────────────────────────────────────────────────────────
  Widget _backlogSection() {
    if (_proposals.isEmpty) {
      return _card(
        child: Text(
          'אין פריטי backlog',
          style: TextStyle(
              fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
        ),
      );
    }
    return Column(
      children: _proposals.map((p) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _backlogItemCard(p),
      )).toList(),
    );
  }

  Widget _backlogItemCard(Map<String, dynamic> proposal) {
    final title = (proposal['title'] as String? ?? '—');
    final whyNow = (proposal['why_now'] as String? ?? '').trim();
    final statusRaw = (proposal['status'] as String? ?? '');
    final statusHe = _statusHe(statusRaw);
    final statusColor = _statusColor(statusRaw);
    final sub = 'מקור: ${whyNow.isNotEmpty ? whyNow : "שימוש"} · סטטוס: $statusHe';
    final progress = _statusProgress(statusRaw);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 11,
                          color: JC.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _pill(statusHe, statusColor),
            ],
          ),
          const SizedBox(height: 10),
          // 5-segment stepper
          _stepper(progress),
          const SizedBox(height: 8),
          _actionButton(
            label: 'התחל תחקיר',
            color: JC.blue400,
            onPressed: () => showImproveInterviewSheet(
              context,
              _api,
              initialGoal: title,
            ),
          ),
        ],
      ),
    );
  }

  // 5-segment stepper: returns number 1-5 indicating active step
  // Mapping:
  //   proposal        → 1 active
  //   draft_plan/planning → 2 active
  //   in_progress/active  → 3 active
  //   validation      → 4 active
  //   done            → 5 (all done)
  int _statusProgress(String status) {
    switch (status.toLowerCase()) {
      case 'proposal':
        return 1;
      case 'draft_plan':
      case 'planning':
        return 2;
      case 'in_progress':
      case 'active':
        return 3;
      case 'validation':
        return 4;
      case 'done':
        return 5;
      default:
        return 1;
    }
  }

  Widget _stepper(int activeStep) {
    // activeStep is 1..5; steps up to activeStep-1 are done,
    // activeStep itself is active (gold), rest are muted.
    // Exception: if activeStep==5 all are done (green).
    return Row(
      children: List.generate(5, (i) {
        final step = i + 1;
        Color color;
        if (activeStep == 5) {
          color = JC.green500;
        } else if (step < activeStep) {
          color = JC.green500;
        } else if (step == activeStep) {
          color = JC.amber400;
        } else {
          color = JC.border;
        }
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i < 4 ? 3 : 0),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      }),
    );
  }

  String _statusHe(String status) {
    switch (status.toLowerCase()) {
      case 'proposal':
        return 'הצעה';
      case 'in_progress':
      case 'active':
        return 'בביצוע';
      case 'done':
        return 'הושלם';
      default:
        return status.isNotEmpty ? status : 'הצעה';
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'done':
        return JC.green500;
      case 'in_progress':
      case 'active':
        return JC.amber400;
      case 'proposal':
        return JC.blue400;
      default:
        return JC.textMuted;
    }
  }

  // ── F. Create improvement ─────────────────────────────────────────────────
  Widget _createImproveCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "תחקיר שיפור עם ג'רוויס",
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "הכנס מטרה ראשית — ג'רוויס ישאל שאלות דינמיות המבוססות על המטרה ועל כל תשובה בדרך.",
                      style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 11,
                          color: JC.textMuted,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _pill('דינמי', JC.blue400),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _goalCtrl,
            style: TextStyle(
                fontFamily: 'Heebo', fontSize: 13, color: JC.textPrimary),
            decoration: InputDecoration(
              hintText: 'מה תרצה לשפר?',
              hintStyle: TextStyle(
                  fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
              filled: true,
              fillColor: JC.surfaceAlt,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: JC.amber400, width: 1.5),
              ),
            ),
            minLines: 1,
            maxLines: 3,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 10),
          _actionButton(
            label: 'התחל תחקיר',
            color: JC.amber400,
            onPressed: () {
              final goal = _goalCtrl.text.trim();
              showImproveInterviewSheet(
                context,
                _api,
                initialGoal: goal.isNotEmpty ? goal : null,
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Shared section header (gold text + gradient line) ─────────────────────
  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Heebo',
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: JC.amber400,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [JC.amber400.withOpacity(0.34), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared card container ─────────────────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: JC.surface,
        border: Border.all(color: JC.border.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: JC.shadow.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 18)),
        ],
      ),
      child: child,
    );
  }

  // ── Event row with RTL-aware start accent ──────────────────────────────────
  Widget _eventRow({required Color accentColor, required Widget child}) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border.all(color: JC.border.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Small action button ───────────────────────────────────────────────────
  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.42)),
        backgroundColor: color.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
            fontFamily: 'Heebo', fontWeight: FontWeight.w900, fontSize: 11),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }

  // ── Pill ──────────────────────────────────────────────────────────────────
  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.38)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
