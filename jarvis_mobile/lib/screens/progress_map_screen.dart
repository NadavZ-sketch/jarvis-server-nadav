import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../app_settings.dart';

class ProgressMapScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback? onSwitchToChat;
  const ProgressMapScreen({super.key, required this.settings, this.onSwitchToChat});

  @override
  State<ProgressMapScreen> createState() => _ProgressMapScreenState();
}

class _ProgressMapScreenState extends State<ProgressMapScreen> {
  // Server
  bool? _serverOk;
  int _latencyMs = 0;

  // Stats
  Map<String, dynamic> _stats = {};
  bool _loadingStats = true;

  // Features
  List<Map<String, dynamic>> _done = [];
  List<Map<String, dynamic>> _building = [];
  List<Map<String, dynamic>> _planned = [];
  bool _loadingFeatures = true;
  String _featuresUpdated = '';

  // Proposals (AI backlog)
  List<Map<String, dynamic>> _proposals = [];
  String? _lastGenerated;
  bool _generatingProposals = false;

  // Manual items
  List<Map<String, dynamic>> _items = [];
  bool _loadingBacklog = true;

  // UI
  final Set<int> _expandedProposals = {};
  final _addCtrl    = TextEditingController();
  final _promptCtrl = TextEditingController();
  String? _generatedPrompt;
  bool _generatingPrompt = false;
  bool _promptCopied = false;

  int _featureTabIndex = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _addCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 25), () {
      if (mounted) _loadAll();
    });
  }

  String get _base => widget.settings.serverUrl;

  Future<void> _loadAll() async {
    _retryTimer?.cancel();
    await Future.wait([_checkHealth(), _loadStats(), _loadFeatures(), _loadBacklog()]);
    // Auto-retry if server was unreachable — Render free tier cold-starts in 15-60s
    if (mounted && _serverOk != true) _scheduleRetry();
  }

  Future<void> _checkHealth() async {
    try {
      final t0  = DateTime.now().millisecondsSinceEpoch;
      final res = await http.get(Uri.parse('$_base/health')).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _serverOk  = res.statusCode == 200;
        _latencyMs = DateTime.now().millisecondsSinceEpoch - t0;
      });
    } catch (_) {
      if (mounted) setState(() => _serverOk = false);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final res = await http.get(Uri.parse('$_base/stats')).timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode == 200) {
        setState(() { _stats = jsonDecode(res.body); _loadingStats = false; });
      } else if (mounted) {
        setState(() => _loadingStats = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
  }

  Future<void> _loadFeatures() async {
    setState(() => _loadingFeatures = true);
    try {
      final res = await http.get(Uri.parse('$_base/dashboard/features')).timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() {
          _done     = List<Map<String, dynamic>>.from(d['features']?['done']     ?? []);
          _building = List<Map<String, dynamic>>.from(d['features']?['building'] ?? []);
          _planned  = List<Map<String, dynamic>>.from(d['features']?['planned']  ?? []);
          _featuresUpdated = d['lastUpdated']?.toString() ?? '';
          _loadingFeatures = false;
        });
      } else if (mounted) {
        setState(() => _loadingFeatures = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFeatures = false);
    }
  }

  Future<void> _loadBacklog() async {
    setState(() => _loadingBacklog = true);
    try {
      final res = await http.get(Uri.parse('$_base/dashboard/backlog')).timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() {
          _proposals     = List<Map<String, dynamic>>.from(d['proposals'] ?? []);
          _items         = List<Map<String, dynamic>>.from(d['items']     ?? []);
          _lastGenerated = d['_lastGenerated']?.toString();
          _loadingBacklog = false;
        });
      } else if (mounted) {
        setState(() => _loadingBacklog = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBacklog = false);
    }
  }

  Future<void> _generateProposals() async {
    setState(() => _generatingProposals = true);
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/backlog/generate'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 90));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() {
          _proposals     = List<Map<String, dynamic>>.from(d['proposals'] ?? []);
          _lastGenerated = d['generated_at']?.toString();
        });
      } else if (mounted) {
        _showSnack('שגיאה ביצירת הצעות');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת רשת — בדוק שהשרת פעיל');
    } finally {
      if (mounted) setState(() => _generatingProposals = false);
    }
  }

  Future<void> _patchProposal(dynamic id, String status) async {
    try {
      await http.patch(
        Uri.parse('$_base/dashboard/backlog/proposals/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      ).timeout(const Duration(seconds: 8));
      await _loadBacklog();
    } catch (_) {}
  }

  Future<void> _activateProposal(Map<String, dynamic> proposal) async {
    final id    = proposal['id'];
    final title = proposal['title']?.toString() ?? '';
    final plan  = proposal['plan']?.toString() ?? '';
    await _patchProposal(id, 'active');
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1929),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ActivateSheet(
        base: _base,
        title: title,
        plan: plan,
        onSwitchToChat: widget.onSwitchToChat,
      ),
    );
  }

  Future<void> _deleteProposal(dynamic id) async {
    try {
      await http.delete(Uri.parse('$_base/dashboard/backlog/proposals/$id'))
          .timeout(const Duration(seconds: 8));
      await _loadBacklog();
    } catch (_) {}
  }

  Future<void> _addItem() async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) return;
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/backlog'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode == 200) {
        _addCtrl.clear();
        await _loadBacklog();
      } else if (mounted) {
        _showSnack('שגיאה בהוספה');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת רשת');
    }
  }

  Future<void> _toggleItem(dynamic id) async {
    try {
      await http.patch(Uri.parse('$_base/dashboard/backlog/$id'))
          .timeout(const Duration(seconds: 8));
      await _loadBacklog();
    } catch (_) {}
  }

  Future<void> _deleteItem(dynamic id) async {
    try {
      await http.delete(Uri.parse('$_base/dashboard/backlog/$id'))
          .timeout(const Duration(seconds: 8));
      await _loadBacklog();
    } catch (_) {}
  }

  Future<void> _generatePrompt() async {
    final desc = _promptCtrl.text.trim();
    if (desc.isEmpty) return;
    setState(() { _generatingPrompt = true; _generatedPrompt = null; });
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/generate-prompt'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'description': desc}),
      ).timeout(const Duration(seconds: 90));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() => _generatedPrompt = d['prompt']?.toString());
      } else if (mounted) {
        _showSnack('שגיאה ביצירת הפרומפט');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת רשת');
    } finally {
      if (mounted) setState(() => _generatingPrompt = false);
    }
  }

  Future<void> _copyPrompt() async {
    if (_generatedPrompt == null) return;
    await Clipboard.setData(ClipboardData(text: _generatedPrompt!));
    setState(() => _promptCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _promptCopied = false);
    });
    if (mounted) _showSnack('הפרומפט הועתק ✓', duration: const Duration(seconds: 1));
  }

  void _showSnack(String msg, {Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
      duration: duration ?? const Duration(seconds: 3),
      backgroundColor: JC.surfaceAlt,
    ));
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('מפת התקדמות',
            style: TextStyle(color: JC.textPrimary, fontSize: 18,
                fontWeight: FontWeight.w600, fontFamily: 'Heebo')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: JC.textMuted, size: 20),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: JC.blue400,
        backgroundColor: JC.surface,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _buildStatusBar(),
            const SizedBox(height: 14),
            _buildMetrics(),
            const SizedBox(height: 14),
            if (!_loadingFeatures && _done.isNotEmpty) ...[
              _buildProgressBar(),
              const SizedBox(height: 20),
            ],
            _sectionTitle('🗂️ סטטוס יכולות'),
            const SizedBox(height: 8),
            _buildFeatureBoard(),
            const SizedBox(height: 24),
            _sectionTitle('🤖 Backlog AI'),
            const SizedBox(height: 8),
            _buildAIBacklog(),
            const SizedBox(height: 24),
            _sectionTitle('📌 פריטים ידניים'),
            const SizedBox(height: 10),
            _buildPromptGenerator(),
            const SizedBox(height: 10),
            _buildManualItems(),
          ],
        ),
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────

  Widget _buildStatusBar() {
    final ok = _serverOk;
    final isWaiting = ok == false && _retryTimer?.isActive == true;
    final statusColor = ok == null
        ? const Color(0xFFF59E0B)
        : ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final label = ok == null
        ? 'בודק שרת...'
        : ok
            ? 'שרת פעיל'
            : isWaiting
                ? 'מחכה לשרת להתעורר... (עד 25 שנ׳)'
                : 'שרת לא זמין';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Row(
        children: [
          if (isWaiting)
            const SizedBox(
              width: 8, height: 8,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFF59E0B)),
            )
          else
            Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: JC.textSecondary, fontSize: 13, fontFamily: 'Heebo')),
          ),
          if (ok == true)
            Text('${_latencyMs}ms',
                style: const TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'))
          else if (ok == false)
            GestureDetector(
              onTap: _loadAll,
              child: const Text('נסה עכשיו',
                  style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  Widget _buildMetrics() {
    final items = [
      ('שיחות',   _stats['chat']?['total'],      '${_stats['chat']?['today'] ?? 0} היום'),
      ('משימות',  _stats['tasks']?['total'],     '${(_stats['tasks']?['total'] ?? 0) - (_stats['tasks']?['done'] ?? 0)} פתוחות'),
      ('תזכורות', _stats['reminders']?['total'], '${_stats['reminders']?['active'] ?? 0} פעילות'),
      ('זיכרונות',_stats['memories']?['total'],  'long-term'),
      ('פתקים',   _stats['notes']?['total'],     'notes'),
    ];
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (label, num, sub) = items[i];
          return Container(
            width: 96,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JC.border, width: 0.8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(
                    color: JC.textSecondary, fontSize: 11,
                    fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _loadingStats ? '…' : (num?.toString() ?? '—'),
                  style: const TextStyle(
                      color: JC.blue400, fontSize: 22,
                      fontWeight: FontWeight.w700, height: 1.1),
                ),
                Text(sub, style: const TextStyle(
                    color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo'),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final total = _done.length + _building.length + _planned.length;
    if (total == 0) return const SizedBox.shrink();
    final pctDone     = _done.length / total;
    final pctBuilding = _building.length / total;
    final pctPlanned  = _planned.length / total;
    final pct = (_done.length / total * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _dot(const Color(0xFF22C55E), '${_done.length} הושלמו'),
              const SizedBox(width: 12),
              _dot(const Color(0xFFF59E0B), '${_building.length} בבנייה'),
              const SizedBox(width: 12),
              _dot(JC.textMuted, '${_planned.length} מתוכנן'),
              const Spacer(),
              Text('$pct% הושלם',
                  style: const TextStyle(color: JC.textPrimary,
                      fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                Expanded(flex: (pctDone * 1000).toInt(),
                    child: Container(color: const Color(0xFF22C55E))),
                Expanded(flex: (pctBuilding * 1000).toInt(),
                    child: Container(color: const Color(0xFFF59E0B))),
                Expanded(flex: (pctPlanned * 1000).toInt(),
                    child: Container(color: JC.border)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(color: color, fontFamily: 'Heebo', fontSize: 12)),
    ],
  );

  // ── Feature board ─────────────────────────────────────────────────────────

  Widget _buildFeatureBoard() {
    if (_loadingFeatures) {
      return const Padding(padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)));
    }
    // No features loaded — server was unavailable
    if (_done.isEmpty && _building.isEmpty && _planned.isEmpty && _serverOk != true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, color: JC.textMuted, size: 28),
            const SizedBox(height: 8),
            const Text('לא ניתן לטעון נתונים — השרת לא זמין',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _loadAll,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: JC.blue500.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JC.blue400.withOpacity(0.4)),
                ),
                child: const Text('טעון מחדש',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ]),
        ),
      );
    }
    final labels    = ['✅ ${_done.length} הושלם', '🔨 ${_building.length} בבנייה', '📋 ${_planned.length} מתוכנן'];
    final itemLists = [_done, _building, _planned];
    final colors    = [const Color(0xFF22C55E), const Color(0xFFF59E0B), JC.textSecondary];
    final currentItems = itemLists[_featureTabIndex];
    final currentColor = colors[_featureTabIndex];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: List.generate(3, (i) {
              final selected = i == _featureTabIndex;
              final color    = colors[i];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => setState(() => _featureTabIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? color.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? color.withOpacity(0.5) : JC.border,
                          width: selected ? 1.0 : 0.5,
                        ),
                      ),
                      child: Text(labels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected ? color : JC.textMuted,
                            fontFamily: 'Heebo',
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 11,
                          )),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          if (currentItems.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('אין פריטים',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
            )
          else
            ...currentItems.map((f) => _featureItem(f, currentColor)),
          if (_featuresUpdated.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('עודכן: $_featuresUpdated',
                  style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                  textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  Widget _featureItem(Map<String, dynamic> f, Color color) {
    final name = f['name']?.toString() ?? '';
    final desc = f['desc']?.toString() ?? '';
    final display = name.isNotEmpty ? name : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: JC.surface,
            border: Border(
              right: BorderSide(color: color.withOpacity(0.5), width: 2.5),
              top: BorderSide(color: JC.border, width: 0.5),
              bottom: BorderSide(color: JC.border, width: 0.5),
              left: BorderSide(color: JC.border, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(display,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  )),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(desc,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: JC.textSecondary,
                      fontFamily: 'Heebo',
                      fontSize: 11,
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── AI Backlog ────────────────────────────────────────────────────────────

  Widget _buildAIBacklog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Explanation + generate button
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: Row(
            children: [
              _outlineBtn(
                icon: _generatingProposals ? null : Icons.auto_awesome_rounded,
                label: _generatingProposals ? 'מנתח...' : 'צור הצעות',
                loading: _generatingProposals,
                onTap: _generatingProposals ? null : _generateProposals,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _lastGenerated != null
                      ? 'עדכון אחרון: $_lastGenerated'
                      : 'Jarvis ינתח את הפרויקט ויציע פריטי עבודה עם תוכנית מלאה',
                  style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Content
        if (_generatingProposals)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(children: [
              CircularProgressIndicator(color: JC.blue400, strokeWidth: 2),
              SizedBox(height: 10),
              Text('Jarvis מנתח את הפרויקט ויוצר הצעות...',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
                  textAlign: TextAlign.center),
            ]),
          )
        else if (_proposals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: const [
              Icon(Icons.auto_awesome_outlined, color: JC.textMuted, size: 32),
              SizedBox(height: 8),
              Text('לחץ "צור הצעות" כדי ש-Jarvis ינתח את הפרויקט',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                  textAlign: TextAlign.center),
            ]),
          )
        else
          ..._proposals.map(_buildProposalCard),
      ],
    );
  }

  void _showProposalDetail(Map<String, dynamic> p) {
    final idRaw    = p['id'];
    final idInt    = idRaw != null ? (idRaw as num).toInt() : null;
    final status   = p['status']?.toString() ?? 'proposal';
    final isActive = status == 'active';
    final priority = p['priority']?.toString() ?? 'medium';
    final priorityColor = priority == 'high'
        ? const Color(0xFFEF4444)
        : priority == 'low' ? JC.textMuted : const Color(0xFFF59E0B);
    final priorityLabel = priority == 'high' ? '🔴 גבוה' : priority == 'low' ? '🟢 נמוך' : '🟡 בינוני';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // Handle
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: JC.border, borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              // Badges
              Wrap(spacing: 6, children: [
                _badge(priorityLabel, priorityColor),
                _badge(isActive ? '⚡ עובד על זה' : '💡 הצעה', isActive ? JC.blue400 : JC.textMuted),
              ]),
              const SizedBox(height: 12),
              // Title
              Text(p['title']?.toString() ?? '',
                  style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 16),
              const Divider(color: JC.border, height: 1),
              const SizedBox(height: 16),
              // Plan label
              const Text('📋 תוכנית מפורטת',
                  style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 10),
              // Plan text
              Text(p['plan']?.toString() ?? '',
                  style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
                      fontSize: 14, height: 1.7)),
              const SizedBox(height: 24),
              // Explanation of "הפעל"
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: JC.blue500.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: JC.blue400.withOpacity(0.2)),
                ),
                child: const Text(
                  '⚡ "הפעל" = שולח את ההצעה לג׳רביס כמשימה פעילה — הוא יגיב עם הצעד הראשון לביצוע. ניתן להמשיך את השיחה בטאב הצ׳אט.',
                  style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontSize: 12, height: 1.5),
                ),
              ),
              const SizedBox(height: 20),
              // Activate / deactivate button
              if (status != 'done')
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (idInt != null) {
                      if (isActive) {
                        await _patchProposal(idInt, 'proposal');
                      } else {
                        await _activateProposal(p);
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isActive ? JC.surface : JC.blue500,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: JC.blue400.withOpacity(0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isActive ? '⏸ הפסק לעבוד על זה' : '⚡ הפעל — עובד על זה עכשיו',
                      style: TextStyle(
                          color: isActive ? JC.blue400 : Colors.white,
                          fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              // Delete
              GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  if (idInt != null) await _deleteProposal(idInt);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: JC.border),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🗑 הסר הצעה',
                      style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProposalCard(Map<String, dynamic> p) {
    final status   = p['status']?.toString() ?? 'proposal';
    final priority = p['priority']?.toString() ?? 'medium';
    final isActive = status == 'active';
    final isDone   = status == 'done';
    final title    = p['title']?.toString() ?? '';
    final plan     = p['plan']?.toString() ?? '';

    final priorityColor = priority == 'high'
        ? const Color(0xFFEF4444)
        : priority == 'low' ? JC.textMuted : const Color(0xFFF59E0B);
    final priorityLabel = priority == 'high' ? '🔴 גבוה' : priority == 'low' ? '🟢 נמוך' : '🟡 בינוני';
    final catMap    = {'feature': "פיצ'ר", 'improvement': 'שיפור', 'bug': 'באג', 'ux': 'UX'};
    final catLabel  = catMap[p['category']?.toString()] ?? (p['category']?.toString() ?? '');
    final statusLabel = isActive ? '⚡ עובד על זה' : isDone ? '✅ הושלם' : '💡 הצעה';
    final statusColor = isActive ? JC.blue400 : isDone ? const Color(0xFF22C55E) : JC.textMuted;

    final idRaw = p['id'];
    final idInt = idRaw != null ? (idRaw as num).toInt() : null;

    return Opacity(
      opacity: isDone ? 0.5 : 1,
      child: GestureDetector(
        onTap: () => _showProposalDetail(p),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            border: Border(
              right: BorderSide(color: priorityColor, width: 3),
              left:   BorderSide(color: isActive ? JC.blue400.withOpacity(0.4) : JC.border, width: 0.8),
              top:    BorderSide(color: isActive ? JC.blue400.withOpacity(0.4) : JC.border, width: 0.8),
              bottom: BorderSide(color: isActive ? JC.blue400.withOpacity(0.4) : JC.border, width: 0.8),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title.isNotEmpty ? title : '(כותרת ריקה)',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: title.isNotEmpty ? JC.textPrimary : JC.textMuted,
                    fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (plan.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    plan,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.45),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (!isDone)
                      GestureDetector(
                        onTap: () {
                          if (idInt != null) {
                            if (isActive) {
                              _patchProposal(idInt, 'proposal');
                            } else {
                              _activateProposal(p);
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive ? Colors.transparent : JC.blue500.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: JC.blue400.withOpacity(0.35), width: 0.8),
                          ),
                          child: Text(isActive ? '⏸ בטל' : '⚡ הפעל',
                              style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                  fontWeight: FontWeight.w600, fontSize: 11)),
                        ),
                      ),
                    const Spacer(),
                    _badge(statusLabel, statusColor),
                    if (catLabel.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      _badge(catLabel, JC.textMuted),
                    ],
                    const SizedBox(width: 4),
                    _badge(priorityLabel, priorityColor),
                  ],
                ),
              ],
            ),
          ),
        ),      // Container
          ),    // ClipRRect
        ),      // Padding(bottom: 8)
      ),        // GestureDetector
    );          // Opacity
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withOpacity(0.25), width: 0.7),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontFamily: 'Heebo',
            fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _outlineBtn({IconData? icon, required String label, bool loading = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: JC.blue500.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JC.blue400.withOpacity(0.4), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: JC.blue400))
            else if (icon != null)
              Icon(icon, size: 14, color: JC.blue400),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(
                color: JC.blue400, fontFamily: 'Heebo',
                fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── Prompt Generator ──────────────────────────────────────────────────────

  Widget _buildPromptGenerator() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Row(
            children: [
              Spacer(),
              Icon(Icons.auto_awesome_rounded, color: JC.blue400, size: 13),
              SizedBox(width: 5),
              Text("מחולל פרומפט לפיצ'ר חדש ב-Claude Code",
                  style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _promptCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
                decoration: InputDecoration(
                  hintText: "תאר את הפיצ'ר שאתה רוצה לפתח...",
                  hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: JC.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: JC.border, width: 0.8)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: JC.blue400)),
                  filled: true, fillColor: JC.surfaceAlt,
                ),
                onSubmitted: (_) => _generatePrompt(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _generatingPrompt ? null : _generatePrompt,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: _generatingPrompt ? JC.blue500.withOpacity(0.5) : JC.blue500,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _generatingPrompt
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('✨ צור',
                        style: TextStyle(color: Colors.white, fontFamily: 'Heebo',
                            fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ]),
          if (_generatedPrompt != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JC.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JC.border, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(children: [
                    GestureDetector(
                      onTap: _copyPrompt,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: JC.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: JC.border, width: 0.8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_promptCopied ? Icons.check_rounded : Icons.copy_rounded,
                              size: 12, color: JC.blue400),
                          const SizedBox(width: 4),
                          Text(_promptCopied ? 'הועתק!' : 'העתק',
                              style: const TextStyle(color: JC.blue400,
                                  fontFamily: 'Heebo', fontSize: 12)),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    const Text('📋 פרומפט מוכן ל-Claude Code',
                        style: TextStyle(color: JC.textSecondary,
                            fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  const Divider(color: JC.border, height: 1),
                  const SizedBox(height: 8),
                  SelectableText(
                    _generatedPrompt!,
                    style: const TextStyle(color: JC.textSecondary,
                        fontFamily: 'Heebo', fontSize: 12, height: 1.6),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      _addCtrl.text = _promptCtrl.text.trim();
                      _addItem();
                    },
                    child: const Text('+ שמור כפריט ב-Backlog',
                        style: TextStyle(color: JC.textMuted,
                            fontFamily: 'Heebo', fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Manual items ──────────────────────────────────────────────────────────

  Widget _buildManualItems() {
    return Column(
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _addCtrl,
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'הוסף פריט ידני מהיר...',
                hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: JC.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: JC.border, width: 0.8)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: JC.blue400)),
                filled: true, fillColor: JC.surface,
              ),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _addItem,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: JC.border, width: 0.8),
              ),
              child: const Text('הוסף',
                  style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (_loadingBacklog)
          const Padding(padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2))
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('אין פריטים ידניים',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
          )
        else
          ..._items.map(_buildManualItem),
      ],
    );
  }

  Widget _buildManualItem(Map<String, dynamic> item) {
    final id   = item['id'];
    final done = item['done'] == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Opacity(
        opacity: done ? 0.45 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () { if (id != null) _toggleItem(id); },
                child: Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: done ? const Color(0xFF22C55E) : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: done ? const Color(0xFF22C55E) : JC.border,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['text']?.toString() ?? '',
                  style: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 8),
              Text(item['added']?.toString() ?? '',
                  style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () { if (id != null) _deleteItem(id); },
                child: const Icon(Icons.close_rounded, size: 16, color: JC.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      const Expanded(child: Divider(color: JC.border, height: 1)),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
          color: JC.blue400, fontSize: 11, fontWeight: FontWeight.w700,
          fontFamily: 'Heebo', letterSpacing: 0.8)),
    ]),
  );
}

// ─── Activate Sheet ────────────────────────────────────────────────────────────

class _ActivateSheet extends StatefulWidget {
  final String base, title, plan;
  final VoidCallback? onSwitchToChat;
  const _ActivateSheet({
    required this.base,
    required this.title,
    required this.plan,
    this.onSwitchToChat,
  });

  @override
  State<_ActivateSheet> createState() => _ActivateSheetState();
}

class _ActivateSheetState extends State<_ActivateSheet> {
  String? _response;
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dispatch();
  }

  Future<void> _dispatch() async {
    final msg = 'קבלת משימה חדשה מה-Backlog:\n\nכותרת: ${widget.title}\n\nתוכנית: ${widget.plan}\n\nאנא הגיב בקצרה: מה הצעד הראשון הקונקרטי שתעשה כדי להתחיל לממש את זה?';
    try {
      final resp = await http.post(
        Uri.parse('${widget.base}/ask-jarvis'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': msg}),
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _response = data['answer']?.toString() ?? '';
          _loading  = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF1A2E4A),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            Row(children: [
              const Text('⚡', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                widget.title,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700, fontSize: 15),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              )),
            ]),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Color(0xFF6366F1), strokeWidth: 2),
                  SizedBox(height: 12),
                  Text('ג׳רביס מקבל את המשימה...', style: TextStyle(
                      color: Color(0xFF475569), fontFamily: 'Heebo', fontSize: 13)),
                ])),
              )
            else if (_error != null)
              Text('שגיאה: $_error', style: const TextStyle(
                  color: Color(0xFFEF4444), fontFamily: 'Heebo', fontSize: 13))
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1422),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A2E4A), width: 0.8),
                ),
                child: Text(
                  _response ?? '',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'Heebo',
                      fontSize: 13, height: 1.6),
                ),
              ),
            const SizedBox(height: 16),
            Row(children: [
              if (widget.onSwitchToChat != null && !_loading)
                GestureDetector(
                  onTap: () { widget.onSwitchToChat!(); Navigator.pop(context); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('המשך בצ׳אט ←', style: TextStyle(
                        color: Colors.white, fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text('סגור', style: TextStyle(
                    color: Color(0xFF475569), fontFamily: 'Heebo', fontSize: 13)),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
