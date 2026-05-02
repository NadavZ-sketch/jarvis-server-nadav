import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../app_settings.dart';

class ProgressMapScreen extends StatefulWidget {
  final AppSettings settings;
  const ProgressMapScreen({super.key, required this.settings});

  @override
  State<ProgressMapScreen> createState() => _ProgressMapScreenState();
}

class _ProgressMapScreenState extends State<ProgressMapScreen>
    with SingleTickerProviderStateMixin {
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

  late TabController _featureTabCtrl;

  @override
  void initState() {
    super.initState();
    _featureTabCtrl = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _featureTabCtrl.dispose();
    _addCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  String get _base => widget.settings.serverUrl;

  Future<void> _loadAll() async {
    await Future.wait([_checkHealth(), _loadStats(), _loadFeatures(), _loadBacklog()]);
  }

  Future<void> _checkHealth() async {
    try {
      final t0  = DateTime.now().millisecondsSinceEpoch;
      final res = await http.get(Uri.parse('$_base/health')).timeout(const Duration(seconds: 5));
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
    final statusColor = ok == null
        ? const Color(0xFFF59E0B)
        : ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
          const SizedBox(width: 8),
          Text(
            ok == null ? 'בודק שרת...' : ok ? '● שרת פעיל' : '● שרת לא זמין',
            style: const TextStyle(color: JC.textSecondary, fontSize: 13, fontFamily: 'Heebo'),
          ),
          if (ok == true) ...[
            const Spacer(),
            Text('${_latencyMs}ms',
                style: const TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
          ],
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
    return Column(
      children: [
        TabBar(
          controller: _featureTabCtrl,
          labelColor: JC.blue400,
          unselectedLabelColor: JC.textMuted,
          indicatorColor: JC.blue400,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: JC.border,
          labelStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 12),
          tabs: [
            Tab(text: '✅ ${_done.length}  הושלם'),
            Tab(text: '🔨 ${_building.length}  בבנייה'),
            Tab(text: '📋 ${_planned.length}  מתוכנן'),
          ],
        ),
        SizedBox(
          height: 220,
          child: TabBarView(
            controller: _featureTabCtrl,
            children: [
              _featureList(_done, const Color(0xFF22C55E)),
              _featureList(_building, const Color(0xFFF59E0B)),
              _featureList(_planned, JC.textMuted),
            ],
          ),
        ),
        if (_featuresUpdated.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('עודכן: $_featuresUpdated',
                style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _featureList(List<Map<String, dynamic>> features, Color color) {
    if (features.isEmpty) {
      return Center(child: Text('אין פריטים',
          style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: features.length,
      itemBuilder: (_, i) {
        final f = features[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border(right: BorderSide(color: color.withOpacity(0.5), width: 2.5),
                top: BorderSide(color: JC.border, width: 0.5),
                bottom: BorderSide(color: JC.border, width: 0.5),
                left: BorderSide(color: JC.border, width: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(f['name']?.toString() ?? '',
                  style: const TextStyle(color: JC.textPrimary,
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13),
                  textDirection: TextDirection.rtl),
              if ((f['desc']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(f['desc']?.toString() ?? '',
                    style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
                    textDirection: TextDirection.rtl),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── AI Backlog ────────────────────────────────────────────────────────────

  Widget _buildAIBacklog() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _lastGenerated != null ? 'נוצר: $_lastGenerated' : 'Jarvis ינתח ויציע משימות לפרויקט',
                style: const TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'),
              ),
            ),
            const SizedBox(width: 8),
            _outlineBtn(
              icon: _generatingProposals ? null : Icons.auto_awesome_rounded,
              label: _generatingProposals ? 'מנתח...' : 'צור הצעות',
              loading: _generatingProposals,
              onTap: _generatingProposals ? null : _generateProposals,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_generatingProposals)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              CircularProgressIndicator(color: JC.blue400, strokeWidth: 2),
              SizedBox(height: 10),
              Text('Jarvis מנתח את הפרויקט ויוצר הצעות...',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
                  textAlign: TextAlign.center),
            ]),
          )
        else if (_proposals.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: const Column(children: [
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

  Widget _buildProposalCard(Map<String, dynamic> p) {
    final id       = p['id'];
    final status   = p['status']?.toString() ?? 'proposal';
    final priority = p['priority']?.toString() ?? 'medium';
    final isActive = status == 'active';
    final isDone   = status == 'done';
    final expanded = id != null && _expandedProposals.contains(id);

    final priorityColor = priority == 'high'
        ? const Color(0xFFEF4444)
        : priority == 'low' ? JC.textMuted : const Color(0xFFF59E0B);
    final catMap = {'feature': "פיצ'ר", 'improvement': 'שיפור', 'bug': 'באג', 'ux': 'UX'};
    final catLabel = catMap[p['category']?.toString()] ?? (p['category']?.toString() ?? '');

    return Opacity(
      opacity: isDone ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            right: BorderSide(color: priorityColor, width: 3),
            left: BorderSide(color: isActive ? JC.blue400.withOpacity(0.35) : JC.border, width: 0.8),
            top: BorderSide(color: isActive ? JC.blue400.withOpacity(0.35) : JC.border, width: 0.8),
            bottom: BorderSide(color: isActive ? JC.blue400.withOpacity(0.35) : JC.border, width: 0.8),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Badges row
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  _badge(priority == 'high' ? '🔴 גבוה' : priority == 'low' ? '🟢 נמוך' : '🟡 בינוני', priorityColor),
                  if (catLabel.isNotEmpty) _badge(catLabel, JC.textMuted),
                  _badge(
                    status == 'active' ? '⚡ פעיל' : status == 'done' ? '✅ הושלם' : '💡 הצעה',
                    isActive ? JC.blue400 : isDone ? const Color(0xFF22C55E) : JC.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Title
              Text(p['title']?.toString() ?? '',
                  style: const TextStyle(color: JC.textPrimary,
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 14),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 6),
              // Plan text
              Text(
                p['plan']?.toString() ?? '',
                style: const TextStyle(color: JC.textSecondary,
                    fontFamily: 'Heebo', fontSize: 12, height: 1.5),
                textDirection: TextDirection.rtl,
                maxLines: expanded ? null : 2,
                overflow: expanded ? null : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Actions
              Row(
                children: [
                  // Delete
                  GestureDetector(
                    onTap: () { if (id != null) _deleteProposal(id); },
                    child: const Text('✕ הסר',
                        style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
                  ),
                  const Spacer(),
                  // Expand
                  GestureDetector(
                    onTap: () => setState(() {
                      if (expanded) _expandedProposals.remove(id);
                      else if (id != null) _expandedProposals.add(id as int);
                    }),
                    child: Text(expanded ? '▲ סגור' : '▼ תוכנית מלאה',
                        style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
                  ),
                  if (!isDone) ...[
                    const SizedBox(width: 10),
                    // Activate
                    GestureDetector(
                      onTap: () { if (id != null) _patchProposal(id, isActive ? 'proposal' : 'active'); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.transparent : JC.blue500.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: JC.blue400.withOpacity(0.35), width: 0.8),
                        ),
                        child: Text(
                          isActive ? '⏸ בטל' : '⚡ הפעל',
                          style: const TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                              fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    return Opacity(
      opacity: done ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () { if (id != null) _deleteItem(id); },
              child: const Icon(Icons.close_rounded, size: 16, color: JC.textMuted),
            ),
            const SizedBox(width: 8),
            Text(item['added']?.toString() ?? '',
                style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
            const Spacer(),
            Flexible(
              child: Text(
                item['text']?.toString() ?? '',
                style: TextStyle(
                  color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(width: 8),
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
          ],
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
