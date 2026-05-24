import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ══════════════════════════════════════════════════════════════════════════════
// AgentDetailSheet — 4 tabs: כרטיס · מידע · חיבורים · דאשבורד
// Shared between ProgressMapScreen and ControlCenterPreviewScreen.
// ══════════════════════════════════════════════════════════════════════════════

class AgentDetailSheet extends StatefulWidget {
  final Map<String, dynamic> agent;
  final String base;
  const AgentDetailSheet({super.key, required this.agent, required this.base});

  @override
  State<AgentDetailSheet> createState() => _AgentDetailSheetState();
}

class _AgentDetailSheetState extends State<AgentDetailSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _promptCtrl = TextEditingController();
  bool _buildingPrompt = false;
  bool _descExpanded = false;
  String? _generatedPrompt;
  String? _reviewText;
  bool _promptCopied = false;
  Timer? _copyTimer;

  static const _kAgentIcons = {
    'router': '🔀', 'chatAgent': '💬', 'taskAgent': '✅', 'reminderAgent': '⏰',
    'memoryAgent': '🧠', 'weatherAgent': '🌤', 'newsAgent': '📰', 'stocksAgent': '📈',
    'translationAgent': '🌐', 'sportsAgent': '⚽', 'shoppingAgent': '🛒',
    'notesAgent': '📝', 'musicAgent': '🎵', 'messagingAgent': '📨',
    'draftAgent': '✍️', 'insightAgent': '💡', 'securityAgent': '🛡',
    'codeErrorAgent': '🐛', 'e2eAgent': '🧪', 'agentFactoryAgent': '🏭', 'surveyAgent': '📋',
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _promptCtrl.dispose();
    _copyTimer?.cancel();
    super.dispose();
  }

  // ── Field accessors ────────────────────────────────────────────────────────
  Map<String, dynamic> get a => widget.agent;
  String get _id           => (a['id'] ?? '').toString();
  String get _nameHe       => (a['nameHe'] ?? a['name'] ?? a['id'] ?? '').toString();
  String get _role         => (a['role'] ?? '').toString();
  String get _mission      => (a['mission'] ?? a['description'] ?? '').toString();
  String get _prompt       => (a['prompt'] ?? '').toString();
  String get _risk         => (a['risk'] ?? 'low').toString();
  String get _mode         => (a['mode'] ?? '').toString();
  String get _status       => (a['status'] ?? 'active').toString();
  num    get _autonomy     => (a['autonomy'] ?? 0) as num;
  List<String> get _responsibilities =>
      List<String>.from(a['responsibilities'] ?? const []);
  List<String> get _tools        => List<String>.from(a['tools'] ?? const []);
  List<String> get _permissions  => List<String>.from(a['permissions'] ?? const []);
  List<Map<String, dynamic>> get _connections => List<Map<String, dynamic>>.from(
      (a['connections'] ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
  Map<String, dynamic>? get _metrics => a['metrics'] as Map<String, dynamic>?;
  int?   get _healthScore  => (a['healthScore'] as num?)?.toInt();
  num?   get _avgMs        => _metrics?['avgMs'] as num?;
  int    get _callCount    => (_metrics?['count'] as num?)?.toInt() ?? 0;
  String? get _lastCalledAt => _metrics?['lastCalledAt']?.toString();
  String get _icon         => _kAgentIcons[_id] ?? '🤖';

  // ── Helpers ────────────────────────────────────────────────────────────────
  Color _riskColor(String r) => switch (r) {
        'high'   => const Color(0xFFEF4444),
        'medium' => const Color(0xFFF59E0B),
        'low'    => const Color(0xFF22C55E),
        _        => const Color(0xFF64748B),
      };

  Color _healthColor(int? s) {
    if (s == null) return const Color(0xFF64748B);
    if (s >= 80) return const Color(0xFF22C55E);
    if (s >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _latencyLabel(num? ms) {
    if (ms == null) return '—';
    if (ms <= 800) return 'מהיר';
    if (ms <= 2000) return 'בינוני';
    return 'איטי';
  }

  Color _latencyColor(num? ms) {
    if (ms == null) return const Color(0xFF64748B);
    if (ms <= 800) return const Color(0xFF22C55E);
    if (ms <= 2000) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  String _relativeDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'עכשיו';
    if (diff.inHours < 1) return 'לפני ${diff.inMinutes} דק׳';
    if (diff.inDays < 1) return 'לפני ${diff.inHours} שע׳';
    if (diff.inDays == 1) return 'אתמול';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    if (diff.inDays < 30) return 'לפני ${(diff.inDays / 7).floor()} שבועות';
    return 'לפני ${(diff.inDays / 30).floor()} חודשים';
  }

  Future<void> _buildPrompt() async {
    final req = _promptCtrl.text.trim();
    if (req.isEmpty) return;
    setState(() {
      _buildingPrompt = true;
      _generatedPrompt = null;
      _reviewText = null;
    });
    try {
      final res = await http.post(
        Uri.parse('${widget.base}/progress-map/build-prompt'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'agentId': _id, 'changeRequest': req}),
      ).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _generatedPrompt = d['prompt']?.toString();
          _reviewText      = d['reviewText']?.toString();
        });
      }
    } catch (_) {}
    finally {
      if (mounted) setState(() => _buildingPrompt = false);
    }
  }

  Future<void> _copyPrompt() async {
    if (_generatedPrompt == null) return;
    await Clipboard.setData(ClipboardData(text: _generatedPrompt!));
    if (!mounted) return;
    setState(() => _promptCopied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _promptCopied = false);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Agent header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                    ),
                    child: Center(
                        child: Text(_icon,
                            style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_nameHe,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Color(0xFFE2E8F0), fontFamily: 'Heebo',
                              fontWeight: FontWeight.w700, fontSize: 16,
                            )),
                        if (_role.isNotEmpty)
                          Text(_role,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontFamily: 'Heebo', fontSize: 12)),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 4, runSpacing: 4,
                          textDirection: TextDirection.rtl,
                          children: [
                            if (_healthScore != null)
                              _badge('$_healthScore%',
                                  _healthColor(_healthScore), icon: '🎯'),
                            _badge(
                              _risk == 'high'
                                  ? 'סיכון גבוה'
                                  : _risk == 'medium'
                                      ? 'בינוני'
                                      : 'סיכון נמוך',
                              _riskColor(_risk), icon: '🔒',
                            ),
                            if (_mode.isNotEmpty)
                              _badge(_mode, const Color(0xFF38BDF8),
                                  icon: '⚙️'),
                            if (_avgMs != null)
                              _badge(_latencyLabel(_avgMs),
                                  _latencyColor(_avgMs), icon: '⚡'),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _status == 'disabled'
                                ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                                : const Color(0xFF22C55E)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _status == 'disabled'
                                  ? const Color(0xFFEF4444)
                                      .withValues(alpha: 0.3)
                                  : const Color(0xFF22C55E)
                                      .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _status == 'disabled'
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF22C55E),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _status == 'disabled' ? 'מושבת' : 'פעיל',
                                style: TextStyle(
                                  color: _status == 'disabled'
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF22C55E),
                                  fontFamily: 'Heebo', fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Tab bar
            TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              indicatorColor: const Color(0xFF6366F1),
              labelColor: const Color(0xFF818CF8),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
              unselectedLabelStyle:
                  const TextStyle(fontFamily: 'Heebo', fontSize: 13),
              tabs: const [
                Tab(text: 'כרטיס'),
                Tab(text: 'מידע'),
                Tab(text: 'חיבורים'),
                Tab(text: 'דאשבורד'),
              ],
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildCardTab(),
                  _buildInfoTab(),
                  _buildConnectionsTab(),
                  _buildDashboardTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: כרטיס ──────────────────────────────────────────────────────────
  Widget _buildCardTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Description (expandable)
        if (_mission.isNotEmpty) ...[
          _sectionLabel('תיאור'),
          GestureDetector(
            onTap: () => setState(() => _descExpanded = !_descExpanded),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _mission,
                  textAlign: TextAlign.right,
                  maxLines: _descExpanded ? null : 3,
                  overflow: _descExpanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontFamily: 'Heebo', fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  _descExpanded ? 'הצג פחות ↑' : 'הצג עוד ↓',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontFamily: 'Heebo', fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Responsibilities
        if (_responsibilities.isNotEmpty) ...[
          _sectionLabel('תחומי אחריות עיקריים'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E3A5F), width: 0.7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _responsibilities
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          textDirection: TextDirection.rtl,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('▸ ',
                                style: TextStyle(
                                    color: Color(0xFF6366F1), fontSize: 12)),
                            Expanded(
                              child: Text(r,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontFamily: 'Heebo',
                                    fontSize: 12, height: 1.4,
                                  )),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Prompt preview
        if (_prompt.isNotEmpty) ...[
          _sectionLabel('תצוגת פרומפט'),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E3A5F), width: 0.7),
            ),
            child: Text(
              _prompt,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontFamily: 'Heebo', fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Prompt Builder
        _sectionLabel('Prompt Builder 🔧'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0F1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E3A5F), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextField(
                controller: _promptCtrl,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'Heebo', fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'תאר שינוי לסוכן זה...',
                  hintStyle: TextStyle(
                      color: Color(0xFF64748B), fontFamily: 'Heebo'),
                  contentPadding: EdgeInsets.all(10),
                  filled: true,
                  fillColor: Color(0xFF111827),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFF1E3A5F)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide:
                        BorderSide(color: Color(0xFF1E3A5F), width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFF6366F1)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _buildingPrompt ? null : _buildPrompt,
                  icon: _buildingPrompt
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    _buildingPrompt ? 'יוצר פרומפט...' : 'צור פרומפט',
                    style: const TextStyle(
                        fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF6366F1).withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              if (_reviewText != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('📋 Jarvis הבין:',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Color(0xFF818CF8), fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700, fontSize: 12,
                          )),
                      const SizedBox(height: 6),
                      Text(_reviewText!,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8), fontFamily: 'Heebo',
                            fontSize: 12, height: 1.45,
                          )),
                    ],
                  ),
                ),
              ],
              if (_generatedPrompt != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E3A5F)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(children: [
                        GestureDetector(
                          onTap: _copyPrompt,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2235),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFF1E3A5F)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                _promptCopied
                                    ? Icons.check_rounded
                                    : Icons.copy_rounded,
                                size: 12,
                                color: const Color(0xFF6366F1),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _promptCopied ? 'הועתק!' : 'העתק',
                                style: const TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontFamily: 'Heebo', fontSize: 11),
                              ),
                            ]),
                          ),
                        ),
                        const Spacer(),
                        const Text('🔧 פרומפט מוכן',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Color(0xFF94A3B8), fontFamily: 'Heebo',
                              fontSize: 12, fontWeight: FontWeight.w600,
                            )),
                      ]),
                      const SizedBox(height: 8),
                      Divider(
                          color: const Color(0xFF1E3A5F), height: 1),
                      const SizedBox(height: 8),
                      SelectableText(
                        _generatedPrompt!,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8), fontFamily: 'Heebo',
                          fontSize: 12, height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Tab 2: מידע ───────────────────────────────────────────────────────────
  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _infoRow('ID', _id),
        if (_role.isNotEmpty) _infoRow('תפקיד', _role),
        _infoRow('אוטונומיה', '${_autonomy.toInt()}%'),
        _infoRow('רמת סיכון', _risk),
        _infoRow('מצב', _mode.isEmpty ? '—' : _mode),
        _infoRow('סטטוס', _status == 'disabled' ? 'מושבת' : 'פעיל'),
        if (_tools.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('כלים'),
          Wrap(
            spacing: 6, runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: _tools
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF38BDF8)
                                .withValues(alpha: 0.25)),
                      ),
                      child: Text(t,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontFamily: 'Heebo', fontSize: 11,
                          )),
                    ))
                .toList(),
          ),
        ],
        if (_permissions.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('הרשאות'),
          Wrap(
            spacing: 6, runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: _permissions
                .map((p) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFF59E0B)
                                .withValues(alpha: 0.25)),
                      ),
                      child: Text(p,
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontFamily: 'Heebo', fontSize: 11,
                          )),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontFamily: 'Heebo', fontSize: 12)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    color: Color(0xFFE2E8F0), fontFamily: 'Heebo',
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  // ── Tab 3: חיבורים ────────────────────────────────────────────────────────
  Widget _buildConnectionsTab() {
    if (_connections.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.device_hub_rounded,
                color: Color(0xFF64748B), size: 32),
            SizedBox(height: 8),
            Text('אין חיבורים מוגדרים',
                style: TextStyle(
                    color: Color(0xFF64748B),
                    fontFamily: 'Heebo', fontSize: 13)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _sectionLabel('${_connections.length} חיבורים'),
        ..._connections.map((c) {
          final name =
              (c['nameHe'] ?? c['name'] ?? c['agentId'] ?? '').toString();
          final dir = (c['direction'] ?? '').toString();
          final type = (c['type'] ?? '').toString();
          final arrow =
              dir == 'outgoing' ? '→' : dir == 'incoming' ? '←' : '↔';
          final arrowColor = dir == 'outgoing'
              ? const Color(0xFF38BDF8)
              : dir == 'incoming'
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFA78BFA);
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF1E3A5F), width: 0.7),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Text(arrow,
                    style: TextStyle(color: arrowColor, fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0), fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600, fontSize: 13,
                      )),
                ),
                if (type.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: arrowColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: arrowColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(type,
                        style: TextStyle(
                            color: arrowColor,
                            fontFamily: 'Heebo', fontSize: 10)),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ── Tab 4: דאשבורד ────────────────────────────────────────────────────────
  Widget _buildDashboardTab() {
    final hasMetrics = _callCount > 0 || _avgMs != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Health score card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0F1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E3A5F), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('ציון בריאות',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: Color(0xFF64748B),
                      fontFamily: 'Heebo', fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Text(
                    _healthScore?.toString() ?? '—',
                    style: TextStyle(
                      color: _healthColor(_healthScore),
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w800,
                      fontSize: 36, height: 1,
                    ),
                  ),
                  const Text('/100',
                      style: TextStyle(
                          color: Color(0xFF64748B),
                          fontFamily: 'Heebo', fontSize: 16)),
                  const Spacer(),
                  if (_healthScore != null)
                    SizedBox(
                      width: 80, height: 80,
                      child: _HealthGauge(score: _healthScore!),
                    ),
                ],
              ),
              if (_healthScore != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _healthScore! / 100.0,
                    color: _healthColor(_healthScore),
                    backgroundColor: const Color(0xFF1E3A5F),
                    minHeight: 6,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Metric cards
        Row(children: [
          Expanded(child: _metricCard(
              'קריאות', _callCount.toString(), const Color(0xFF38BDF8))),
          const SizedBox(width: 8),
          Expanded(child: _metricCard('ממוצע ms',
              _avgMs != null ? '${_avgMs!.toInt()}' : '—',
              _latencyColor(_avgMs))),
          const SizedBox(width: 8),
          Expanded(child: _metricCard('נקרא לאחרונה',
              _relativeDate(_lastCalledAt), const Color(0xFFA78BFA))),
        ]),
        const SizedBox(height: 12),

        // Latency bar or empty state
        if (hasMetrics) ...[
          _sectionLabel('זמן תגובה ממוצע'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF1E3A5F), width: 0.7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Text(
                      _avgMs != null ? '${_avgMs!.toInt()}ms' : '—',
                      style: TextStyle(
                        color: _latencyColor(_avgMs),
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w700, fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _latencyLabel(_avgMs),
                      style: TextStyle(
                          color: _latencyColor(_avgMs),
                          fontFamily: 'Heebo', fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _avgMs != null
                        ? (1 - (_avgMs! / 5000))
                            .clamp(0.0, 1.0)
                            .toDouble()
                        : 0,
                    color: _latencyColor(_avgMs),
                    backgroundColor: const Color(0xFF1E3A5F),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('5000ms',
                        style: TextStyle(
                            color: Color(0xFF64748B),
                            fontFamily: 'Heebo', fontSize: 10)),
                    Text('0ms',
                        style: TextStyle(
                            color: Color(0xFF64748B),
                            fontFamily: 'Heebo', fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF1E3A5F), width: 0.8),
            ),
            child: const Text(
              'עדיין אין נתוני שימוש לסוכן זה.',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: Color(0xFF64748B),
                  fontFamily: 'Heebo', fontSize: 13),
            ),
          ),
      ],
    );
  }

  Widget _metricCard(String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E3A5F), width: 0.7),
        ),
        child: Column(children: [
          Text(value,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700, fontSize: 17, height: 1.1)),
          const SizedBox(height: 3),
          Text(label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontFamily: 'Heebo', fontSize: 10)),
        ]),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF6366F1), fontFamily: 'Heebo',
              fontWeight: FontWeight.w700, fontSize: 11,
              letterSpacing: 0.5,
            )),
      );

  Widget _badge(String text, Color color, {String? icon}) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: color.withValues(alpha: 0.25), width: 0.7),
        ),
        child: Text(
          icon != null ? '$icon $text' : text,
          style: TextStyle(
              color: color, fontFamily: 'Heebo',
              fontSize: 10, fontWeight: FontWeight.w600),
        ),
      );
}

// ── Health gauge ──────────────────────────────────────────────────────────────

class _HealthGauge extends StatelessWidget {
  final int score;
  const _HealthGauge({required this.score});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? const Color(0xFF22C55E)
        : score >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    return CustomPaint(
        painter: _GaugePainter(value: score / 100.0, color: color));
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;
  const _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const startAngle = pi * 0.75;
    const sweepFull = pi * 1.5;
    final bg = Paint()
      ..color = const Color(0xFF1E3A5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepFull, false, bg);
    if (value > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle, sweepFull * value, false, fg);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.value != value || old.color != color;
}
