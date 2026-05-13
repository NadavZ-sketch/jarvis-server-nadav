import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../app_settings.dart';

// ── Agent Galaxy Data ─────────────────────────────────────────────────────────

class _AgentNode {
  final String id;
  final String nameHe;
  final String icon;
  final String category;
  final List<String> connections;

  const _AgentNode({
    required this.id, required this.nameHe, required this.icon,
    required this.category, this.connections = const [],
  });

  factory _AgentNode.fromJson(Map<String, dynamic> j) => _AgentNode(
    id: j['id'] ?? '', nameHe: j['nameHe'] ?? j['name'] ?? '',
    icon: j['icon'] ?? '⚡', category: j['category'] ?? 'core',
    connections: List<String>.from(j['connections'] ?? []),
  );

  Color get color {
    switch (category) {
      case 'core':         return const Color(0xFF3B82F6);
      case 'storage':      return const Color(0xFF8B5CF6);
      case 'productivity': return const Color(0xFF22C55E);
      case 'external':     return const Color(0xFFF59E0B);
      case 'quality':      return const Color(0xFFEF4444);
      case 'analytics':    return const Color(0xFF06B6D4);
      case 'meta':         return const Color(0xFFA78BFA);
      case 'custom':       return const Color(0xFFF97316);
      default:             return const Color(0xFF94A3B8);
    }
  }
}

class _AgentGalaxyPainter extends CustomPainter {
  final List<_AgentNode> agents;
  final double animValue;

  const _AgentGalaxyPainter({required this.agents, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (agents.isEmpty) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final positions = _positions(cx, cy, size);
    _drawConnections(canvas, positions);
    for (int i = 0; i < agents.length; i++) {
      _drawNode(canvas, positions[i], agents[i], i == 0);
    }
  }

  List<Offset> _positions(double cx, double cy, Size size) {
    final n = agents.length;
    final out = <Offset>[];
    if (n == 0) return out;
    out.add(Offset(cx, cy));
    final rest = n - 1;
    final innerCount = math.min(rest, 6);
    final outerCount = rest - innerCount;
    final r1 = size.width * 0.30;
    final r2 = size.width * 0.46;
    for (int j = 0; j < innerCount; j++) {
      final a = 2 * math.pi * j / innerCount - math.pi / 2;
      out.add(Offset(cx + r1 * math.cos(a), cy + r1 * math.sin(a)));
    }
    for (int j = 0; j < outerCount; j++) {
      final a = 2 * math.pi * j / outerCount - math.pi / 2 + math.pi / outerCount;
      out.add(Offset(cx + r2 * math.cos(a), cy + r2 * math.sin(a)));
    }
    return out;
  }

  void _drawConnections(Canvas canvas, List<Offset> pos) {
    for (int i = 0; i < agents.length; i++) {
      for (final connId in agents[i].connections) {
        final j = agents.indexWhere((a) => a.id == connId);
        if (j < 0 || j >= pos.length) continue;
        final paint = Paint()
          ..color = agents[i].color.withValues(alpha: 0.18)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(pos[i], pos[j], paint);
      }
    }
  }

  void _drawNode(Canvas canvas, Offset pos, _AgentNode agent, bool isCenter) {
    final pulse = 0.82 + 0.18 * math.sin(animValue * 2 * math.pi +
        agent.id.codeUnits.fold(0, (a, b) => a + b) * 0.4);
    final r = (isCenter ? 22.0 : 15.0) * pulse;
    final color = agent.color;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.12 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(pos, r * 1.6, glowPaint);

    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: 0.75), color.withValues(alpha: 0.25)],
      ).createShader(Rect.fromCircle(center: pos, radius: r));
    canvas.drawCircle(pos, r, fillPaint);

    canvas.drawCircle(pos, r, Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke);

    final tp = TextPainter(
      text: TextSpan(text: agent.icon, style: TextStyle(fontSize: isCenter ? 14 : 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_AgentGalaxyPainter old) =>
      old.animValue != animValue || old.agents.length != agents.length;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ProgressMapScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(String)? onSwitchToChat;
  const ProgressMapScreen({super.key, required this.settings, this.onSwitchToChat});

  @override
  State<ProgressMapScreen> createState() => _ProgressMapScreenState();
}

abstract final class _PS {
  static const proposal = 'proposal';
  static const active   = 'active';
  static const done     = 'done';
}

Color _priorityColor(String p) => p == 'high'
    ? const Color(0xFFEF4444)
    : p == 'low' ? JC.textMuted : const Color(0xFFF59E0B);

String _priorityLabel(String p) =>
    p == 'high' ? '🔴 גבוה' : p == 'low' ? '🟢 נמוך' : '🟡 בינוני';

class _ProgressMapScreenState extends State<ProgressMapScreen>
    with TickerProviderStateMixin {
  static const _kCatMap = {
    'feature': "פיצ'ר", 'improvement': 'שיפור', 'bug': 'באג', 'ux': 'UX',
  };

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

  // Filter / inline-activation state
  String _filterStatus   = 'all';
  String _filterPriority = 'all';
  bool   _showDoneProposals = false;
  final Map<String, String> _proposalResponses = {};
  final Set<String>         _activatingIds     = {};

  // Manual items
  List<Map<String, dynamic>> _items = [];
  bool _loadingBacklog = true;

  // UI
  final _addCtrl    = TextEditingController();
  final _promptCtrl = TextEditingController();
  String? _generatedPrompt;
  bool _generatingPrompt = false;
  bool _promptCopied     = false;

  int    _featureTabIndex = 0;
  Timer? _retryTimer;
  Timer? _copyTimer;
  bool   _isRefreshing = false;

  // Intelligence
  List<_AgentNode> _agents = [];
  int              _systemHealth = 0;
  List<String>     _strengths  = [];
  List<String>     _gaps       = [];
  List<Map<String, dynamic>> _nextActions = [];
  String?          _analysis;
  bool             _loadingIntelligence = true;
  bool             _analyzingNow = false;

  // Animation
  late AnimationController _galaxyAnim;
  late AnimationController _pulseAnim;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _galaxyAnim = AnimationController(
      duration: const Duration(seconds: 4), vsync: this)..repeat();
    _pulseAnim = AnimationController(
      duration: const Duration(milliseconds: 1600), vsync: this)..repeat(reverse: true);
    _loadAll();
  }

  @override
  void dispose() {
    _galaxyAnim.dispose();
    _pulseAnim.dispose();
    _retryTimer?.cancel();
    _copyTimer?.cancel();
    _addCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  // ── Computed ──────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filteredProposals {
    var list = List<Map<String, dynamic>>.from(_proposals);
    if (_filterStatus != 'all') {
      list = list.where((p) => p['status'] == _filterStatus).toList();
      // When explicitly filtering to 'done', show them regardless of toggle
    } else if (!_showDoneProposals) {
      list = list.where((p) => p['status'] != _PS.done).toList();
    }
    if (_filterPriority != 'all') {
      list = list.where((p) => p['priority'] == _filterPriority).toList();
    }
    const statusOrder = {'active': 0, 'proposal': 1, 'done': 2};
    list.sort((a, b) {
      final aO = statusOrder[a['status']] ?? 9;
      final bO = statusOrder[b['status']] ?? 9;
      if (aO != bO) return aO - bO;
      return (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? '');
    });
    return list;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _relativeDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'היום';
    if (diff.inDays == 1) return 'אתמול';
    if (diff.inDays < 7)  return 'לפני ${diff.inDays} ימים';
    if (diff.inDays < 30) return 'לפני ${(diff.inDays / 7).floor()} שבועות';
    return 'לפני ${(diff.inDays / 30).floor()} חודשים';
  }

  String _statusFilterLabel(String s) =>
      const {'all': 'הכל', 'proposal': 'הצעה', 'active': 'פעיל', 'done': 'בוצע'}[s] ?? s;

  String _priorityFilterLabel(String p) =>
      const {'all': 'הכל', 'high': 'גבוה', 'medium': 'בינוני', 'low': 'נמוך'}[p] ?? p;

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 25), () {
      if (mounted) _loadAll();
    });
  }

  String get _base => widget.settings.serverUrl;

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadAll() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    _retryTimer?.cancel();
    await Future.wait([_checkHealth(), _loadStats(), _loadFeatures(), _loadBacklog(), _loadIntelligence()]);
    _isRefreshing = false;
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
          _proposals      = List<Map<String, dynamic>>.from(d['proposals'] ?? []);
          _items          = List<Map<String, dynamic>>.from(d['items']     ?? []);
          _lastGenerated  = d['_lastGenerated']?.toString();
          _loadingBacklog = false;
        });
      } else if (mounted) {
        setState(() => _loadingBacklog = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBacklog = false);
    }
  }

  Future<void> _loadIntelligence() async {
    setState(() => _loadingIntelligence = true);
    try {
      final res = await http.get(Uri.parse('$_base/intelligence/snapshot'))
          .timeout(const Duration(seconds: 20));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _agents       = (d['agents'] as List? ?? []).map((a) => _AgentNode.fromJson(a as Map<String, dynamic>)).toList();
          _systemHealth = (d['systemHealth'] as num?)?.toInt() ?? 0;
          final ins     = d['insights'] as Map<String, dynamic>? ?? {};
          _strengths    = List<String>.from(ins['strengths'] ?? []);
          _gaps         = List<String>.from(ins['gaps']      ?? []);
          _nextActions  = List<Map<String, dynamic>>.from(ins['nextActions'] ?? []);
          _loadingIntelligence = false;
        });
      } else if (mounted) {
        setState(() => _loadingIntelligence = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingIntelligence = false);
    }
  }

  Future<void> _analyzeNow() async {
    setState(() => _analyzingNow = true);
    try {
      final res = await http.post(
        Uri.parse('$_base/intelligence/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 30));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _analysis = d['analysis']?.toString());
        await _loadIntelligence();
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאה בניתוח');
    } finally {
      if (mounted) setState(() => _analyzingNow = false);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _generateProposals() async {
    setState(() {
      _generatingProposals = true;
      _proposalResponses.clear();
      _activatingIds.clear();
    });
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

  Future<void> _activateProposal(Map<String, dynamic> proposal) async {
    final idRaw = proposal['id'];
    final idStr = idRaw?.toString() ?? '';
    if (idStr.isEmpty || _activatingIds.contains(idStr)) return;

    final title = proposal['title']?.toString() ?? '';
    final plan  = proposal['plan']?.toString()  ?? '';

    setState(() => _activatingIds.add(idStr));

    try {
      final results = await Future.wait([
        http.patch(
          Uri.parse('$_base/dashboard/backlog/proposals/$idRaw'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'status': _PS.active}),
        ).timeout(const Duration(seconds: 8)),
        http.post(
          Uri.parse('$_base/ask-jarvis'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'command':
                'קבלת משימה חדשה מה-Backlog:\n\nכותרת: $title\n\nתוכנית: $plan\n\n'
                'אנא הגיב בקצרה: מה הצעד הראשון הקונקרטי שתעשה כדי להתחיל לממש את זה?',
          }),
        ).timeout(const Duration(seconds: 30)),
      ]);

      if (!mounted) return;

      final jarvisAnswer = results[1].statusCode == 200
          ? (jsonDecode(results[1].body) as Map<String, dynamic>)['answer']?.toString() ?? ''
          : 'ג׳רביס לא הגיב';

      setState(() {
        _proposalResponses[idStr] = jarvisAnswer;
        final idx = _proposals.indexWhere((p) => p['id']?.toString() == idStr);
        if (idx != -1) {
          _proposals[idx] = Map<String, dynamic>.from(_proposals[idx])
            ..['status'] = _PS.active;
        }
        _activatingIds.remove(idStr);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _activatingIds.remove(idStr));
      _showSnack('שגיאה בהפעלת ההצעה');
    }
  }

  Future<void> _deactivateProposal(dynamic idRaw) async {
    final idStr = idRaw?.toString() ?? '';
    try {
      await http.patch(
        Uri.parse('$_base/dashboard/backlog/proposals/$idRaw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': _PS.proposal}),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        final idx = _proposals.indexWhere((p) => p['id']?.toString() == idStr);
        if (idx != -1) {
          _proposals[idx] = Map<String, dynamic>.from(_proposals[idx])
            ..['status'] = _PS.proposal;
        }
        _proposalResponses.remove(idStr);
      });
    } catch (_) {}
  }

  Future<void> _deleteProposal(dynamic idRaw) async {
    final idStr = idRaw?.toString() ?? '';
    setState(() {
      _proposals.removeWhere((p) => p['id']?.toString() == idStr);
      _proposalResponses.remove(idStr);
      _activatingIds.remove(idStr);
    });
    try {
      await http.delete(Uri.parse('$_base/dashboard/backlog/proposals/$idRaw'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _addItem() => _addItemWithText(_addCtrl.text.trim());

  Future<void> _addItemWithText(String text) async {
    if (text.isEmpty) return;
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/backlog'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode == 200) {
        if (text == _addCtrl.text.trim()) _addCtrl.clear();
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
    if (!mounted) return;
    setState(() => _promptCopied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _promptCopied = false);
    });
    _showSnack('הפרומפט הועתק ✓', duration: const Duration(seconds: 1));
  }

  void _switchToChatWithProposal(Map<String, dynamic> p) {
    final title = p['title']?.toString() ?? '';
    final plan  = p['plan']?.toString()  ?? '';
    final cmd =
        '[PROPOSAL_TITLE:$title]\n\n'
        'קיבלתי הצעת פיתוח חדשה ואני רוצה לפתח אותה:\n\n'
        '**$title**\n\n'
        'תוכנית ראשונית: $plan\n\n'
        'בבקשה שאל אותי לפחות 10 שאלות ממוקדות (שאלה אחת בכל פעם) כדי להבין לעומק:\n'
        '- מה בדיוק הפיצ׳רים והיכולות הנדרשים\n'
        '- קהל היעד ומטרות המוצר\n'
        '- דרישות טכניות, אינטגרציות, הגבלות\n'
        '- חווית משתמש ועיצוב\n'
        '- עדיפויות ו-MVP\n\n'
        'אחרי שסיימנו את כל השאלות, נסח פרומפט פיתוח מפורט ומוכן לשימוש בכלי AI '
        '(Claude Code, Codex, Gemini וכו׳).\n'
        'את הפרומפט הסופי כתוב בדיוק בפורמט הזה (חשוב!):\n'
        '<<<PROMPT_START>>>\n'
        '[הפרומפט המלא כאן]\n'
        '<<<PROMPT_END>>>';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSwitchToChat!(cmd);
    });
  }

  void _showSnack(String msg, {Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
      duration: duration ?? const Duration(seconds: 3),
      backgroundColor: JC.surfaceAlt,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: const Text('מרכז שליטה',
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
            const SizedBox(height: 16),
            _sectionTitle('🌐 גלקסיית סוכנים'),
            const SizedBox(height: 10),
            _buildAgentGalaxy(),
            const SizedBox(height: 16),
            _sectionTitle('🧠 ניתוח חכם'),
            const SizedBox(height: 8),
            _buildIntelligencePanel(),
            const SizedBox(height: 16),
            _buildActivityTimeline(),
            const SizedBox(height: 16),
            if (!_loadingFeatures && _done.isNotEmpty) ...[
              _buildProgressBar(),
              const SizedBox(height: 20),
            ],
            _sectionTitle('🗂️ סטטוס יכולות'),
            const SizedBox(height: 8),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0008)
                ..rotateX(-0.018),
              child: _buildFeatureBoard(),
            ),
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

  // ── Agent Galaxy ──────────────────────────────────────────────────────────

  Widget _buildAgentGalaxy() {
    if (_loadingIntelligence && _agents.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: const Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)),
      );
    }
    if (_agents.isEmpty) {
      return Container(
        height: 80,
        decoration: BoxDecoration(
          color: JC.surface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: const Center(child: Text('לא ניתן לטעון — בדוק חיבור לשרת',
            style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JC.border.withValues(alpha: 0.6), width: 0.8),
        boxShadow: [BoxShadow(color: JC.blue500.withValues(alpha: 0.05), blurRadius: 20, spreadRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(children: [
              const Spacer(),
              Text('${_agents.length} סוכנים פעילים',
                  style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
              const SizedBox(width: 6),
              _healthBadge(_systemHealth),
            ]),
          ),
          AnimatedBuilder(
            animation: _galaxyAnim,
            builder: (_, __) => CustomPaint(
              size: const Size(double.infinity, 230),
              painter: _AgentGalaxyPainter(
                agents: _agents, animValue: _galaxyAnim.value),
            ),
          ),
          _buildCategoryLegend(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _healthBadge(int score) {
    final color = score >= 80
        ? const Color(0xFF22C55E)
        : score >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12 + _pulseAnim.value * 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: color.withValues(alpha: 0.7 + _pulseAnim.value * 0.3))),
          const SizedBox(width: 5),
          Text('בריאות $score%',
              style: TextStyle(color: color, fontFamily: 'Heebo',
                  fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _buildCategoryLegend() {
    final categories = <String, Color>{
      'core': const Color(0xFF3B82F6), 'storage': const Color(0xFF8B5CF6),
      'productivity': const Color(0xFF22C55E), 'external': const Color(0xFFF59E0B),
      'quality': const Color(0xFFEF4444), 'analytics': const Color(0xFF06B6D4),
      'meta': const Color(0xFFA78BFA), 'custom': const Color(0xFFF97316),
    };
    final labels = <String, String>{
      'core': 'ליבה', 'storage': 'אחסון', 'productivity': 'פרודוקטיביות',
      'external': 'חיצוני', 'quality': 'איכות', 'analytics': 'ניתוח',
      'meta': 'מטא', 'custom': 'מותאם',
    };
    final present = _agents.map((a) => a.category).toSet();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Wrap(
        spacing: 8, runSpacing: 4,
        alignment: WrapAlignment.center,
        children: categories.entries
          .where((e) => present.contains(e.key))
          .map((e) => Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 7, height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: e.value)),
            const SizedBox(width: 4),
            Text(labels[e.key] ?? e.key,
                style: const TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
          ]))
          .toList(),
      ),
    );
  }

  // ── Intelligence Panel ────────────────────────────────────────────────────

  Widget _buildIntelligencePanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JC.blue500.withValues(alpha: 0.2), width: 0.8),
        gradient: LinearGradient(
          begin: Alignment.topRight, end: Alignment.bottomLeft,
          colors: [JC.blue500.withValues(alpha: 0.04), JC.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Spacer(),
            GestureDetector(
              onTap: _analyzingNow ? null : _analyzeNow,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: JC.blue500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JC.blue400.withValues(alpha: 0.35)),
                ),
                child: _analyzingNow
                    ? const SizedBox(width: 13, height: 13,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: JC.blue400))
                    : const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.refresh_rounded, size: 12, color: JC.blue400),
                        SizedBox(width: 4),
                        Text('נרענן', style: TextStyle(color: JC.blue400,
                            fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
          ]),

          if (_loadingIntelligence && _strengths.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)),
            )
          else if (_strengths.isEmpty && _gaps.isEmpty && _nextActions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('לחץ "נרענן" לקבלת ניתוח AI',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
            )
          else ...[
            if (_strengths.isNotEmpty) ...[
              const SizedBox(height: 8),
              _insightSection('💪 חוזקות', _strengths, const Color(0xFF22C55E)),
            ],
            if (_gaps.isNotEmpty) ...[
              const SizedBox(height: 10),
              _insightSection('🎯 הזדמנויות שיפור', _gaps, const Color(0xFFF59E0B)),
            ],
            if (_nextActions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('⚡ פעולות מומלצות',
                  textAlign: TextAlign.right,
                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
                      fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ..._nextActions.map(_buildNextActionCard),
            ],
          ],

          if (_analysis != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JC.blue500.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JC.blue400.withValues(alpha: 0.15)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('🤖 ניתוח עדכני',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                        fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(_analysis!, textDirection: TextDirection.rtl,
                    style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
                        fontSize: 13, height: 1.55)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _insightSection(String title, List<String> items, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, textAlign: TextAlign.right,
          style: TextStyle(color: color, fontFamily: 'Heebo',
              fontSize: 12, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      ...items.map((s) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          const Spacer(),
          Flexible(child: Text(s, textDirection: TextDirection.rtl,
              style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.4))),
          const SizedBox(width: 6),
          Container(width: 4, height: 4,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.6))),
        ]),
      )),
    ]);
  }

  Widget _buildNextActionCard(Map<String, dynamic> action) {
    final title    = action['title']?.toString() ?? '';
    final prompt   = action['prompt']?.toString() ?? '';
    final priority = action['priority']?.toString() ?? 'medium';
    final prColor  = _priorityColor(priority);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border(right: BorderSide(color: prColor, width: 2.5),
            left: BorderSide(color: JC.border, width: 0.7),
            top: BorderSide(color: JC.border, width: 0.7),
            bottom: BorderSide(color: JC.border, width: 0.7)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(title, textDirection: TextDirection.rtl,
                  style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600, fontSize: 13)),
              if (prompt.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(prompt, textDirection: TextDirection.rtl,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11)),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          if (widget.onSwitchToChat != null)
            GestureDetector(
              onTap: () {
                final cmd = 'משימה חדשה מה-Intelligence Hub:\n\n**$title**\n\n$prompt\n\nבבקשה עזור לי לממש את זה צעד אחר צעד.';
                WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSwitchToChat!(cmd));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: JC.blue500.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JC.blue400.withValues(alpha: 0.4)),
                ),
                child: const Text('התחל →',
                    style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                        fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
        ]),
      ),
    );
  }

  // ── Activity Timeline ─────────────────────────────────────────────────────

  Widget _buildActivityTimeline() {
    if (_loadingStats && _stats.isEmpty) return const SizedBox.shrink();
    final chatsToday  = _stats['chat']?['today']      ?? 0;
    final tasksOpen   = (_stats['tasks']?['total']    ?? 0) - (_stats['tasks']?['done'] ?? 0);
    final memories    = _stats['memories']?['total']  ?? 0;
    final remindersAc = _stats['reminders']?['active'] ?? 0;

    final events = <(String, String, Color)>[
      ('💬', '$chatsToday שיחות היום',       const Color(0xFF3B82F6)),
      ('✅', '$tasksOpen משימות פתוחות',     const Color(0xFF22C55E)),
      if (remindersAc > 0)
        ('⏰', '$remindersAc תזכורות פעילות', const Color(0xFFF59E0B)),
      ('🧠', '$memories זיכרונות שמורים',    const Color(0xFF8B5CF6)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: events.map((e) {
          final (icon, label, color) = e;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontFamily: 'Heebo',
                fontSize: 11, fontWeight: FontWeight.w600)),
          ]);
        }).toList(),
      ),
    );
  }

  // ── Metrics ───────────────────────────────────────────────────────────────

  Widget _buildMetrics() {
    final pendingProposals = _proposals.where((p) => p['status'] == _PS.proposal).length;
    final activeProposals  = _proposals.where((p) => p['status'] == _PS.active).length;
    final items = [
      ('שיחות',   _stats['chat']?['total'],      '${_stats['chat']?['today'] ?? 0} היום'),
      ('משימות',  _stats['tasks']?['total'],     '${(_stats['tasks']?['total'] ?? 0) - (_stats['tasks']?['done'] ?? 0)} פתוחות'),
      ('תזכורות', _stats['reminders']?['total'], '${_stats['reminders']?['active'] ?? 0} פעילות'),
      ('זיכרונות',_stats['memories']?['total'],  'long-term'),
      ('פתקים',   _stats['notes']?['total'],     'notes'),
      ('הצעות',   pendingProposals,              '$activeProposals פעילות'),
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
                  _loadingStats && i < 5 ? '…' : (num?.toString() ?? '—'),
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
              height: 12,
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
                  color: JC.blue500.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: JC.blue400.withValues(alpha: 0.4)),
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
                        color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? color.withValues(alpha: 0.5) : JC.border,
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_featureTabIndex),
              child: currentItems.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('אין פריטים',
                          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
                    )
                  : Column(
                      children: currentItems.map((f) => _featureItem(f, currentColor)).toList(),
                    ),
            ),
          ),
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
    final name    = f['name']?.toString() ?? '';
    final desc    = f['desc']?.toString() ?? '';
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
              right: BorderSide(color: color.withValues(alpha: 0.5), width: 2.5),
              top:    BorderSide(color: JC.border, width: 0.5),
              bottom: BorderSide(color: JC.border, width: 0.5),
              left:   BorderSide(color: JC.border, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(display,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600, fontSize: 13)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(desc,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── AI Backlog ────────────────────────────────────────────────────────────

  Widget _buildAIBacklog() {
    final filtered = _filteredProposals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Generate button + last-generated label
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
                      ? 'עדכון: ${_relativeDate(_lastGenerated)}'
                      : 'Jarvis ינתח את הפרויקט ויציע פריטי עבודה עם תוכנית מלאה',
                  style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Filter chips
        if (_proposals.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  for (final s in ['all', _PS.proposal, _PS.active, _PS.done])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _filterChip(
                        _statusFilterLabel(s),
                        _filterStatus == s,
                        () => setState(() {
                          _filterStatus = s;
                          if (s == _PS.done) _showDoneProposals = true;
                        }),
                      ),
                    ),
                  const SizedBox(width: 8),
                  for (final p in ['all', 'high', 'medium', 'low'])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _filterChip(
                        _priorityFilterLabel(p),
                        _filterPriority == p,
                        () => setState(() => _filterPriority = p),
                      ),
                    ),
                  const SizedBox(width: 8),
                  _filterChip(
                    'הצג בוצע',
                    _showDoneProposals,
                    () => setState(() => _showDoneProposals = !_showDoneProposals),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

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
        else if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('אין הצעות תואמות לפילטר הנוכחי',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
          )
        else
          ...filtered.map(_buildProposalCard),
      ],
    );
  }

  Widget _buildProposalCard(Map<String, dynamic> p) {
    final idRaw   = p['id'];
    final idStr   = idRaw?.toString() ?? '';
    final status  = p['status']?.toString() ?? _PS.proposal;
    final priority = p['priority']?.toString() ?? 'medium';
    final isActive = status == _PS.active;
    final isDone   = status == _PS.done;
    final title    = p['title']?.toString() ?? '';
    final plan     = p['plan']?.toString()  ?? '';
    final dateLabel = _relativeDate(p['createdAt']?.toString());

    final priorityColor = _priorityColor(priority);
    final priorityLbl   = _priorityLabel(priority);
    final catLabel      = _kCatMap[p['category']?.toString()] ?? (p['category']?.toString() ?? '');
    final statusLabel   = isActive ? '⚡ עובד על זה' : isDone ? '✅ הושלם' : '💡 הצעה';
    final statusColor   = isActive ? JC.blue400 : isDone ? const Color(0xFF22C55E) : JC.textMuted;

    final activating = _activatingIds.contains(idStr);
    final response   = _proposalResponses[idStr];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Card ──────────────────────────────────────────────────────────
          Opacity(
            opacity: isDone ? 0.55 : 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: JC.surfaceAlt,
                  border: Border(
                    right: BorderSide(color: priorityColor, width: 3),
                    left:   BorderSide(color: isActive ? JC.blue400.withValues(alpha: 0.4) : JC.border, width: 0.8),
                    top:    BorderSide(color: isActive ? JC.blue400.withValues(alpha: 0.4) : JC.border, width: 0.8),
                    bottom: BorderSide(color: isActive ? JC.blue400.withValues(alpha: 0.4) : JC.border, width: 0.8),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title + date
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title.isNotEmpty ? title : '(כותרת ריקה)',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: title.isNotEmpty ? JC.textPrimary : JC.textMuted,
                                fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (dateLabel.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            _badge(dateLabel, JC.textMuted),
                          ],
                        ],
                      ),
                      // Plan preview
                      if (plan.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          plan,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
                              fontSize: 12, height: 1.45),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Badges + activate button
                      Row(
                        children: [
                          if (!isDone)
                            GestureDetector(
                              onTap: activating
                                  ? null
                                  : () {
                                      if (isActive) {
                                        _deactivateProposal(idRaw);
                                      } else {
                                        _activateProposal(p);
                                      }
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.transparent : JC.blue500.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: JC.blue400.withValues(alpha: 0.35), width: 0.8),
                                ),
                                child: activating
                                    ? const SizedBox(
                                        width: 13, height: 13,
                                        child: CircularProgressIndicator(strokeWidth: 1.8, color: JC.blue400),
                                      )
                                    : Text(isActive ? '⏸ בטל' : '⚡ הפעל',
                                        style: const TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                            fontWeight: FontWeight.w600, fontSize: 11)),
                              ),
                            ),
                          if (!isDone && widget.onSwitchToChat != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _switchToChatWithProposal(p),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4), width: 0.8),
                                ),
                                child: const Text('עבוד עכשיו →',
                                    style: TextStyle(color: Color(0xFF22C55E), fontFamily: 'Heebo',
                                        fontWeight: FontWeight.w600, fontSize: 11)),
                              ),
                            ),
                          ],
                          const Spacer(),
                          _badge(statusLabel, statusColor),
                          if (catLabel.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            _badge(catLabel, JC.textMuted),
                          ],
                          const SizedBox(width: 4),
                          _badge(priorityLbl, priorityColor),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _deleteProposal(idRaw),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, size: 14, color: JC.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Inline Jarvis response ─────────────────────────────────────────
          if (response != null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JC.blue500.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JC.blue400.withValues(alpha: 0.2)),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text('🤖 ג׳רביס:',
                            style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        const Spacer(),
                        if (widget.onSwitchToChat != null)
                          GestureDetector(
                            onTap: () => _switchToChatWithProposal(p),
                            child: const Text('המשך בצ׳אט ←',
                                style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(response,
                        style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
                            fontSize: 13, height: 1.55)),
                  ],
                ),
              ),
            ),
        ],
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
                decoration: _backlogInputDecoration(
                  hint: "תאר את הפיצ'ר שאתה רוצה לפתח...",
                  fill: JC.surfaceAlt,
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
                  color: _generatingPrompt ? JC.blue500.withValues(alpha: 0.5) : JC.blue500,
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
                    onTap: () => _addItemWithText(_promptCtrl.text.trim()),
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
              decoration: _backlogInputDecoration(hint: 'הוסף פריט ידני מהיר...'),
              onSubmitted: (_) => _addItem(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _addItem,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: JC.blue500,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('הוסף',
                  style: TextStyle(color: Colors.white, fontFamily: 'Heebo',
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
    final id         = item['id'];
    final done       = item['done'] == true;
    final dateLabel  = _relativeDate(item['added']?.toString());

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dismissible(
        key: ValueKey(id ?? item['text']),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 16),
          child: const Icon(Icons.delete_rounded, color: Colors.white, size: 20),
        ),
        onDismissed: (_) {
          final text = item['text']?.toString() ?? '';
          setState(() => _items.removeWhere((i) => i['id'] == id));
          if (id != null) _deleteItem(id);
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('פריט נמחק', style: TextStyle(fontFamily: 'Heebo')),
            backgroundColor: JC.surfaceAlt,
            action: SnackBarAction(
              label: 'בטל',
              textColor: JC.blue400,
              onPressed: () => _addItemWithText(text),
            ),
          ));
        },
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
                if (dateLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(dateLabel,
                      style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? JC.blue500.withValues(alpha: 0.15) : JC.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? JC.blue400.withValues(alpha: 0.6) : JC.border,
            width: selected ? 1.0 : 0.7,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? JC.blue400 : JC.textMuted,
              fontFamily: 'Heebo',
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: 0.25), width: 0.7),
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
          color: JC.blue500.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JC.blue400.withValues(alpha: 0.4), width: 0.8),
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

  InputDecoration _backlogInputDecoration({required String hint, Color? fill}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: fill ?? JC.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: JC.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: JC.border, width: 0.8)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: JC.blue400)),
      );

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
