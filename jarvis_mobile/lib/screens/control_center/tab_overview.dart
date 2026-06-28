import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Health score formula (documented):
//   Server unreachable (empty/error health response) → 0.
//   Otherwise start at 100, -10 if active_model is absent/empty.
//   Clamped to [0, 100].
//
// In practice this gives:
//   Server up, active_model present  → 100
//   Server up, active_model missing  → 90
//   Server down                       → 0
// ─────────────────────────────────────────────────────────────────────────────

class TabOverview extends StatefulWidget {
  final AppSettings settings;
  const TabOverview({super.key, required this.settings});

  @override
  State<TabOverview> createState() => _TabOverviewState();
}

class _TabOverviewState extends State<TabOverview>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  Map<String, dynamic>? _health;
  int _latencyMs = 0;
  List<Map<String, dynamic>> _log = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;

  // Polling
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 30);

  // Scroll controller — used by "פתח לוג" to jump to recent-actions section
  final ScrollController _scrollCtrl = ScrollController();

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
    _scrollCtrl.dispose();
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Measure round-trip latency for the health call
      final sw = Stopwatch()..start();
      final health = await _api.healthCheck().catchError((_) => <String, dynamic>{});
      sw.stop();

      final log = await _api
          .fetchExecutionLog(limit: 8)
          .catchError((_) => <Map<String, dynamic>>[]);

      final eventsData = await _api
          .getControlCenterEvents()
          .catchError((_) => <String, dynamic>{});

      if (!mounted) return;
      setState(() {
        _health = health;
        _latencyMs = sw.elapsedMilliseconds;
        _log = log;
        _alerts = List<Map<String, dynamic>>.from(
            eventsData['alerts'] as List? ?? []);
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

  // ── Health score ──────────────────────────────────────────────────────────
  int get _healthScore {
    if (_health == null || _health!.isEmpty) return 0;
    int score = 100;
    final model = (_health!['active_model'] as String? ?? '').trim();
    if (model.isEmpty) score -= 10;
    return score.clamp(0, 100);
  }

  // ── Status dot color ──────────────────────────────────────────────────────
  Color get _dotColor {
    final score = _healthScore;
    if (score >= 90) return JC.green500;
    if (score >= 60) return JC.amber400;
    return JC.cancelRed;
  }

  // ── Severity color for alerts ─────────────────────────────────────────────
  Color _severityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'urgent':
      case 'bad':
        return JC.cancelRed;
      case 'warning':
      case 'warn':
        return JC.amber400;
      default:
        return JC.blue400;
    }
  }

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
          Text(_error!,
              style: TextStyle(color: JC.cancelRed, fontFamily: 'Heebo'),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
              onPressed: _load,
              child: const Text('נסה שוב',
                  style: TextStyle(fontFamily: 'Heebo'))),
        ]),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            _statusCard(),
            const SizedBox(height: 12),
            _metricsGrid(),
            const SizedBox(height: 18),
            _sectionHeader('דורש פעולה'),
            const SizedBox(height: 8),
            _alertsSection(),
            const SizedBox(height: 18),
            _sectionHeader('פעולות אחרונות'),
            const SizedBox(height: 8),
            _recentActionsCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Section header (gold text + trailing gradient line) ───────────────────
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

  // ── Status card ───────────────────────────────────────────────────────────
  Widget _statusCard() {
    final online = _health != null && _health!.isNotEmpty;
    final headline = online ? "ג'רוויס פעיל ובריא" : "ג'רוויס אינו זמין";
    final sub = online
        ? 'שרת, DB וספקי מודלים זמינים · ${_latencyMs}ms'
        : 'השרת לא הגיב';

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
                      headline,
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: JC.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sub,
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 12,
                        color: JC.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _PulsingDot(color: _dotColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: 'פתח לוג',
                  color: JC.blue400,
                  onPressed: () => _scrollToLog(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  label: 'הסבר מצב',
                  color: JC.amber400,
                  onPressed: () => _showStatusExplain(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _scrollToLog() {
    // Scroll to the bottom of the list where פעולות אחרונות lives
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  void _showStatusExplain(BuildContext context) {
    final score = _healthScore;
    final model = (_health?['active_model'] as String? ?? '—');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JC.surface,
        title: Text('הסבר מצב המערכת',
            style: TextStyle(
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w900,
                color: JC.amber400)),
        content: Text(
          'ציון בריאות: $score/100\n'
          'מודל פעיל: $model\n'
          'השהייה: ${_latencyMs}ms\n\n'
          'חישוב הציון:\n'
          '• מתחיל מ-100\n'
          '• 0 אם השרת לא זמין\n'
          '• -10 אם אין מודל פעיל',
          style: TextStyle(fontFamily: 'Heebo', color: JC.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('סגור',
                style: TextStyle(fontFamily: 'Heebo', color: JC.blue400)),
          ),
        ],
      ),
    );
  }

  // ── 2-column metrics grid ─────────────────────────────────────────────────
  Widget _metricsGrid() {
    final score = _healthScore;
    final model = (_health?['active_model'] as String? ?? '—');
    // Truncate very long model names for display
    final modelShort = model.length > 12 ? '${model.substring(0, 12)}…' : model;
    final scoreColor = score >= 90
        ? JC.green500
        : score >= 60
            ? JC.amber400
            : JC.cancelRed;
    final scoreNote = score == 100
        ? 'כל המערכות פעילות'
        : score >= 90
            ? 'בעיה אחת לא קריטית'
            : score >= 60
                ? 'כמה בעיות'
                : 'בעיות קריטיות';
    return Row(
      children: [
        Expanded(
            child: _metricBox(
          label: 'ציון בריאות',
          value: '$score',
          valueColor: scoreColor,
          note: scoreNote,
        )),
        const SizedBox(width: 10),
        Expanded(
            child: _metricBox(
          label: 'מודל פעיל',
          value: modelShort,
          valueColor: JC.blue400,
          note: 'fallback מוכן',
        )),
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

  // ── Alerts / "דורש פעולה" ─────────────────────────────────────────────────
  Widget _alertsSection() {
    if (_alerts.isEmpty) {
      return _eventRow(
        accentColor: JC.green500,
        child: Text(
          'אין התראות — הכל תקין',
          style:
              TextStyle(fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
        ),
      );
    }
    return Column(
      children: _alerts.map((alert) => _alertRow(alert)).toList(),
    );
  }

  Widget _alertRow(Map<String, dynamic> alert) {
    final severity = (alert['severity'] as String? ?? 'info').toLowerCase();
    final title = alert['title'] as String? ?? '';
    final message = alert['message'] as String? ?? '';
    final accentColor = _severityColor(severity);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _eventRow(
        accentColor: accentColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: JC.textPrimary)),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(message,
                  style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 12,
                      color: JC.textMuted)),
            ],
            // Action buttons are wired in later slices once the target tabs
            // (agents / improve) expose the matching navigation + actions.
          ],
        ),
      ),
    );
  }

  // ── Recent actions / "פעולות אחרונות" ────────────────────────────────────
  Widget _recentActionsCard() {
    if (_log.isEmpty) {
      return _card(
        child: Text(
          'אין פעולות אחרונות',
          style: TextStyle(
              fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
        ),
      );
    }
    return Column(
      children: _log.map((entry) {
        final ts = entry['created_at'] as String? ?? '';
        // HH:MM from ISO timestamp (e.g. 2025-06-28T19:42:00Z)
        final time = ts.length >= 16 ? ts.substring(11, 16) : ts;
        final agent = entry['agent'] as String? ?? '—';
        final cmd = (entry['cmd'] as String?)?.trim().isNotEmpty == true
            ? entry['cmd'] as String
            : (entry['model'] as String? ?? '');
        final cmdShort = cmd.length > 28 ? '${cmd.substring(0, 28)}…' : cmd;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _eventRow(
            accentColor: JC.green500,
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted),
                children: [
                  TextSpan(
                      text: time,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: JC.textPrimary,
                          fontFamily: 'monospace')),
                  TextSpan(text: ' · $agent'),
                  if (cmdShort.isNotEmpty)
                    TextSpan(
                        text: ' · $cmdShort',
                        style: TextStyle(color: JC.textMuted)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
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

  // ── Event row with inline-start (RTL-aware) accent border ───────────────────
  Widget _eventRow({required Color accentColor, required Widget child}) {
    // In an RTL layout, inline-start is the right side.
    // We use a Stack approach: a thin accent strip on the start side,
    // then the content, to avoid BorderRadius clipping asymmetry.
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
          textDirection: TextDirection.rtl, // RTL: start = right
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing status dot
// ─────────────────────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.28).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween<double>(begin: 1.0, end: 0.72).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: widget.color.withOpacity(0.55), blurRadius: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
