import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TabBrain — Slice 4c of the Control Center redesign.
//
// Sections:
//   A. "איך ג'רוויס החליט" — Decision Trace: most recent trace as a 5-step
//      numbered flow + compact list of the last few entries below.
//   B. "מודלים ו-fallback" — Provider health boxes; active provider highlighted.
//   C. "זיכרון בשימוש" — Pending memory cards with אשר/שכח real-action buttons.
//
// Polling policy:
//   No automatic poll timer — /health/providers probes the network and can take
//   up to ~20 s, making a periodic timer impractical. Pull-to-refresh is the
//   primary refresh mechanism. _load() is called once on init.
//
// candidates parsing:
//   The server stores `candidates` via JSON.stringify into a jsonb column, so
//   it arrives as a JSON String. _parseCandidates() handles both cases:
//   String → jsonDecode → List; already a List → use as-is; failure → [].
//
// Provider → health key mapping (fixed display order):
//   Gemini  → 'gemini_google'
//   Groq    → 'groq'
//   DeepSeek→ 'deepseek'
//   Ollama  → 'ollama'
//
// Active provider: healthCheck() returns active_model (e.g. "gemini-2.0-flash").
//   We lowercase-compare it against display names: contains 'gemini', 'groq',
//   'deepseek', or 'ollama'.
//
// Memory optimistic flow:
//   On tap of אשר or שכח, immediately remove the card from _memories.
//   On API failure, re-insert at the original index + show SnackBar.
// ─────────────────────────────────────────────────────────────────────────────

class TabBrain extends StatefulWidget {
  final AppSettings settings;
  const TabBrain({super.key, required this.settings});

  @override
  State<TabBrain> createState() => _TabBrainState();
}

class _TabBrainState extends State<TabBrain>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  List<Map<String, dynamic>> _trace = [];
  Map<String, dynamic> _providers = {};
  List<Map<String, dynamic>> _memories = [];
  Map<String, dynamic> _health = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchDecisionTrace(limit: 20).catchError((_) => <Map<String, dynamic>>[]),
        _api.fetchHealthProviders().catchError((_) => <String, dynamic>{}),
        _api.fetchPendingMemories().catchError((_) => <Map<String, dynamic>>[]),
        _api.healthCheck().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _trace    = results[0] as List<Map<String, dynamic>>;
        _providers = results[1] as Map<String, dynamic>;
        _memories = results[2] as List<Map<String, dynamic>>;
        _health   = results[3] as Map<String, dynamic>;
        _loading  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = ApiService.friendlyError(e);
        _loading = false;
      });
    }
  }

  // ── candidates JSON-string → List ─────────────────────────────────────────
  List<dynamic> _parseCandidates(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return [];
  }

  // ── Active model → provider name matching ─────────────────────────────────
  bool _isActiveProvider(String providerName) {
    final activeModel =
        (_health['active_model'] as String? ?? '').toLowerCase();
    if (activeModel.isEmpty) return false;
    return activeModel.contains(providerName.toLowerCase());
  }

  // ── Provider status → color ───────────────────────────────────────────────
  // available: value == 'ok' OR (ollama) value.startsWith('configured')
  // error: value.startsWith('error')
  // muted: everything else ('missing key', 'not configured', etc.)
  Color _providerColor(String? value) {
    if (value == null) return JC.textMuted;
    final v = value.toLowerCase();
    if (v == 'ok' || v.startsWith('configured')) return JC.green500;
    if (v.startsWith('error')) return JC.cancelRed;
    return JC.textMuted;
  }

  bool _providerAvailable(String? value) {
    if (value == null) return false;
    final v = value.toLowerCase();
    return v == 'ok' || v.startsWith('configured');
  }

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
            _sectionHeader('איך ג\'רוויס החליט'),
            const SizedBox(height: 8),
            _decisionTraceSection(),
            const SizedBox(height: 18),
            _sectionHeader('מודלים ו-fallback'),
            const SizedBox(height: 8),
            _providersSection(),
            const SizedBox(height: 18),
            _sectionHeader('זיכרון בשימוש'),
            const SizedBox(height: 8),
            _memoriesSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section A — Decision Trace
  // ─────────────────────────────────────────────────────────────────────────

  Widget _decisionTraceSection() {
    if (_trace.isEmpty) {
      return _card(
        child: Text(
          'אין עדיין מסלולי החלטה',
          style: TextStyle(
              fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
        ),
      );
    }

    final latest = _trace.first;
    final input       = latest['input'] as String? ?? '—';
    final intent      = latest['intent'] as String? ?? '—';
    final ambiguous   = latest['ambiguous'] as bool? ?? false;
    final candidates  = _parseCandidates(latest['candidates']);
    final routeMode   = latest['route_mode'] as String? ?? '';
    final agent       = latest['agent'] as String? ?? '—';
    final model       = latest['model'] as String? ?? '—';
    final durationMs  = (latest['duration_ms'] as num?)?.toInt() ?? 0;

    final routeLabel = switch (routeMode) {
      'fast'   => 'זיהוי מהיר',
      'llm'    => 'מודל שפה',
      'forced' => 'נכפה',
      _        => routeMode,
    };

    final candidatesStr = candidates.isNotEmpty
        ? candidates.map((c) => c.toString()).join(', ')
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numbered step flow
              _traceStep(1, 'קלט', input),
              _traceStepDivider(),
              _traceStep(
                2,
                'כוונה',
                '$intent · ${ambiguous ? 'מעורפל' : 'חד-משמעי'} · $candidatesStr',
              ),
              _traceStepDivider(),
              _traceStep(3, 'ניתוב', routeLabel),
              _traceStepDivider(),
              _traceStep(4, 'סוכן', agent),
              _traceStepDivider(),
              _traceStep(5, 'מודל', '$model · ${durationMs}ms'),
            ],
          ),
        ),
        // Recent trace compact list (skip first — already shown above)
        if (_trace.length > 1) ...[
          const SizedBox(height: 8),
          ..._trace.skip(1).take(4).map((entry) {
            final ts      = entry['created_at'] as String? ?? '';
            final time    = ts.length >= 16 ? ts.substring(11, 16) : ts;
            final ent     = entry['intent'] as String? ?? '—';
            final ag      = entry['agent'] as String? ?? '—';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _eventRow(
                accentColor: JC.blue400,
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontFamily: 'Heebo', fontSize: 12, color: JC.textMuted),
                    children: [
                      TextSpan(
                        text: time,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: JC.textPrimary,
                        ),
                      ),
                      TextSpan(text: ' · $ent · $ag'),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _traceStep(int num, String label, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number circle
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: JC.amber400.withOpacity(0.15),
              border: Border.all(color: JC.amber400.withOpacity(0.45)),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$num',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: JC.amber400,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: JC.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 12,
                    color: JC.textMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _traceStepDivider() {
    return Padding(
      padding: const EdgeInsets.only(right: 13), // aligns under step-number center in RTL
      child: Container(
        width: 1,
        height: 10,
        color: JC.border.withOpacity(0.3),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section B — Models & Fallback
  // ─────────────────────────────────────────────────────────────────────────

  // Fixed display order: Gemini, Groq, DeepSeek, Ollama
  static const _providerOrder = [
    ('Gemini',   'gemini_google'),
    ('Groq',     'groq'),
    ('DeepSeek', 'deepseek'),
    ('Ollama',   'ollama'),
  ];

  Widget _providersSection() {
    return _card(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _providerOrder.map((entry) {
          final displayName = entry.$1;
          final key         = entry.$2;
          final value       = _providers[key] as String?;
          final color       = _providerColor(value);
          final available   = _providerAvailable(value);
          // Match active model: contains part of the display name (lowercased)
          // 'Gemini' → active_model contains 'gemini'
          // 'DeepSeek' → active_model contains 'deepseek'
          final isActive    = _isActiveProvider(displayName);

          return _providerBox(
            displayName: displayName,
            statusValue: value ?? 'לא מוגדר',
            color: color,
            available: available,
            isActive: isActive,
          );
        }).toList(),
      ),
    );
  }

  Widget _providerBox({
    required String displayName,
    required String statusValue,
    required Color color,
    required bool available,
    required bool isActive,
  }) {
    // Active: gold border + amber background tint
    // Available (not active): green border + subtle bg
    // Muted/error: border in color
    final borderColor = isActive
        ? JC.amber400
        : available
            ? JC.green500.withOpacity(0.55)
            : color.withOpacity(0.35);
    final bgColor = isActive
        ? JC.amber400.withOpacity(0.12)
        : available
            ? JC.green500.withOpacity(0.07)
            : Colors.transparent;

    // Truncate long status strings for display
    final statusShort = statusValue.length > 22
        ? '${statusValue.substring(0, 22)}…'
        : statusValue;

    return Container(
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(
          color: borderColor,
          width: isActive ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: isActive ? JC.amber400 : JC.textPrimary,
                  ),
                ),
              ),
              if (isActive)
                _pill('פעיל', JC.amber400)
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            statusShort,
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 10,
              color: color,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section C — Pending Memories
  // ─────────────────────────────────────────────────────────────────────────

  Widget _memoriesSection() {
    if (_memories.isEmpty) {
      return _eventRow(
        accentColor: JC.green500,
        child: Text(
          'אין זיכרונות הממתינים לאישור',
          style: TextStyle(
              fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
        ),
      );
    }
    return Column(
      children: List.generate(_memories.length, (i) {
        final mem = _memories[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _memoryCard(mem, i),
        );
      }),
    );
  }

  Widget _memoryCard(Map<String, dynamic> mem, int index) {
    // id may arrive as an int or a uuid string — toString() is safe for both.
    final id      = mem['id']?.toString() ?? '';
    final content = mem['content'] as String? ?? '—';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content,
            style: TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: JC.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'נוצר משיחה · ממתין לאישור',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 11,
              color: JC.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionButton(
                label: 'אשר',
                color: JC.green500,
                onPressed: () => _approveMemory(id, index),
              ),
              const SizedBox(width: 8),
              _actionButton(
                label: 'שכח',
                color: JC.cancelRed,
                onPressed: () => _deleteMemory(id, index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Memory optimistic actions ─────────────────────────────────────────────

  Future<void> _approveMemory(String id, int index) async {
    if (id.isEmpty) return;
    final removed = _memories[index];
    setState(() => _memories.removeAt(index));
    bool ok = false;
    try {
      ok = await _api.approveMemory(id);
    } catch (_) {}
    if (!ok && mounted) {
      // Revert: the server did not confirm the approval.
      setState(() => _memories.insert(index.clamp(0, _memories.length), removed));
      _showSnackBar('אישור הזיכרון נכשל');
    }
  }

  Future<void> _deleteMemory(String id, int index) async {
    if (id.isEmpty) return;
    final removed = _memories[index];
    setState(() => _memories.removeAt(index));
    bool ok = false;
    try {
      ok = await _api.deleteMemory(id);
    } catch (_) {}
    if (!ok && mounted) {
      // Revert: the server did not confirm the deletion.
      setState(() => _memories.insert(index.clamp(0, _memories.length), removed));
      _showSnackBar('מחיקת הזיכרון נכשלה');
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
        backgroundColor: JC.cancelRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared widget helpers (mirror tab_overview / tab_agents)
  // ─────────────────────────────────────────────────────────────────────────

  /// Gold text + trailing gradient line (identical to tab_overview).
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

  /// Rounded card with surface color, subtle border and drop shadow.
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
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }

  /// RTL-aware event row with inline-start accent stripe.
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

  /// Outlined action button (mirrors tab_overview / tab_agents).
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

  /// Small colored badge pill (mirrors tab_agents).
  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.38)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
