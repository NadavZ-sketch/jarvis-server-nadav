import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/proposal_scoring.dart';
import '../services/telemetry_policy.dart';
import 'user_profile_screen.dart';
import 'e2e_reports_screen.dart';
import 'survey_screen.dart';

enum ControlCenterTab { overview, development, agents, insights, surveys }

class ProgressMapScreen extends StatefulWidget {
  final AppSettings settings;
  final void Function(String)? onSwitchToChat;
  final ControlCenterTab initialTab;
  const ProgressMapScreen({
    super.key,
    required this.settings,
    this.onSwitchToChat,
    this.initialTab = ControlCenterTab.overview,
  });

  @override
  State<ProgressMapScreen> createState() => _ProgressMapScreenState();
}

class _GraphNode {
  final String nodeId;
  final String label;
  final String type;
  final double impact;
  final double score;
  final String whyNow;
  const _GraphNode({
    required this.label,
    this.nodeId = '',
    required this.type,
    required this.impact,
    required this.score,
    this.whyNow = 'נבחר בגלל עדיפות נוכחית',
  });
}

class _GraphEdge {
  final int from;
  final int to;
  final String relationshipType; // dependency | similarity | user-goal
  const _GraphEdge({
    required this.from,
    required this.to,
    required this.relationshipType,
  });
}

String _ensureStableNodeId({
  required String rawNodeId,
  required String label,
  required String type,
  required String fallbackSeed,
}) {
  final trimmed = rawNodeId.trim();
  if (trimmed.isNotEmpty) return trimmed;
  final seed = '${type.trim()}|${label.trim()}|${fallbackSeed.trim()}';
  return 'auto-${_stableHash(seed)}';
}

int _stableHash(String input) {
  // FNV-1a 32-bit hash: deterministic across app runs/devices.
  var hash = 0x811C9DC5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

List<Offset> _buildStableGraphPoints({
  required List<_GraphNode> nodes,
  required double width,
  required double height,
}) {
  if (nodes.isEmpty) return const <Offset>[];
  final safeWidth = width < 120 ? 120.0 : width;
  final safeHeight = height < 120 ? 120.0 : height;
  const marginX = 24.0;
  const marginY = 28.0;
  final usableW = safeWidth - (marginX * 2);
  final usableH = safeHeight - (marginY * 2);
  final points = <Offset>[];

  for (final node in nodes) {
    final baseHash = _stableHash(node.nodeId);
    final mixHash = _stableHash('${node.nodeId}|${node.type}|${node.label}');
    final x = marginX + (baseHash % 10000) / 10000.0 * usableW;
    final y = marginY + (mixHash % 10000) / 10000.0 * usableH;
    points.add(Offset(x, y));
  }

  // Basic collision mitigation: small deterministic push when nodes are too close.
  const minDistance = 30.0;
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      final delta = points[j] - points[i];
      final distance = delta.distance;
      if (distance >= minDistance) continue;
      final angleSeed = _stableHash('${nodes[i].nodeId}|${nodes[j].nodeId}');
      final angle = (angleSeed % 360) * 3.1415926535 / 180.0;
      final shift = (minDistance - distance) / 2 + 2;
      final push = Offset(shift * cos(angle), shift * sin(angle));
      points[i] = _clampPoint(points[i] - push, marginX, safeWidth - marginX, marginY, safeHeight - marginY);
      points[j] = _clampPoint(points[j] + push, marginX, safeWidth - marginX, marginY, safeHeight - marginY);
    }
  }
  return points;
}

Offset _clampPoint(Offset p, double minX, double maxX, double minY, double maxY) {
  return Offset(
    p.dx.clamp(minX, maxX).toDouble(),
    p.dy.clamp(minY, maxY).toDouble(),
  );
}

class _InnovationGraphPainter extends CustomPainter {
  final List<_GraphNode> nodes;
  final List<_GraphEdge> edges;
  final double width;
  final double height;
  const _InnovationGraphPainter({required this.nodes, required this.edges, required this.width, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    // Stable layout by nodeId improves long-term user learning:
    // the same concept appears in (almost) the same visual area between sessions,
    // so users build spatial memory and understand graph changes faster.
    final points = _buildStableGraphPoints(nodes: nodes, width: width, height: height);
    for (final e in edges) {
      if (e.from >= points.length || e.to >= points.length) continue;
      final edgePaint = Paint()
        ..color = switch (e.relationshipType) {
          'dependency' => const Color(0x88F59E0B),
          'user-goal' => const Color(0x8834D399),
          _ => const Color(0x8894A3B8),
        }
        ..strokeWidth = e.relationshipType == 'dependency' ? 1.8 : 1.2;
      canvas.drawLine(points[e.from], points[e.to], edgePaint);
    }
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final p = points[i];
      final color = n.type == 'proposal' ? const Color(0xFFA78BFA) : n.type == 'agent' ? const Color(0xFF34D399) : const Color(0xFF38BDF8);
      final r = 6 + (n.impact / 2.4);
      canvas.drawCircle(p, r + 2, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(p, r, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _InnovationGraphPainter oldDelegate) => oldDelegate.nodes != nodes || oldDelegate.edges != edges;
}

abstract final class _PS {
  static const proposal = 'proposal';
  static const draftPlan = 'draft_plan';
  static const active   = 'active';
  static const validation = 'validation';
  static const done     = 'done';
}

Color _priorityColor(String p) => p == 'high'
    ? const Color(0xFFEF4444)
    : p == 'low' ? JC.textMuted : const Color(0xFFF59E0B);

String _priorityLabel(String p) =>
    p == 'high' ? '🔴 גבוה' : p == 'low' ? '🟢 נמוך' : '🟡 בינוני';

class _ProgressMapScreenState extends State<ProgressMapScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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
  String? _selectedChipKey;

  // Proposals (AI backlog)
  List<Map<String, dynamic>> _proposals = [];
  String? _lastGenerated;
  List<String> _learnedInsights = [];
  bool _generatingProposals = false;

  // Filter / inline-activation state
  String _filterStatus   = 'all';
  String _filterPriority = 'all';
  bool   _showDoneProposals = false;
  bool   _sortByScore = true;
  List<String> _statusFilters = const ['all', _PS.proposal, _PS.draftPlan, _PS.active, _PS.validation, _PS.done];
  List<String> _priorityFilters = const ['all', 'high', 'medium', 'low'];
  Map<String, String> _statusLabels = const {'all':'הכל','proposal':'הצעה','draft_plan':'תכנון','active':'פעיל','validation':'ולידציה','done':'בוצע'};
  Map<String, String> _priorityLabels = const {'all':'הכל','high':'גבוה','medium':'בינוני','low':'נמוך'};
  bool   _quickWinsOnly = false;
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
  bool _smartCompactMode = true;
  _GraphNode? _selectedGraphNode;
  final Map<String, int> _smartTelemetry = {
    'action_start_first': 0,
    'action_sprint_prompt': 0,
    'action_sprint_prompt_mvp': 0,
    'action_sprint_prompt_full': 0,
    'action_memory_focus': 0,
    'confirm_yes': 0,
    'confirm_no': 0,
  };

  int    _featureTabIndex = 0;
  Timer? _retryTimer;
  Timer? _copyTimer;
  bool   _isRefreshing = false;

  // Agent center
  List<Map<String, dynamic>> _agents = [];
  bool _loadingAgents = true;

  // Surveys
  List<Map<String, dynamic>> _surveyHistory = [];
  List<String> _surveyInsights = [];
  bool _loadingSurveys = true;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: ControlCenterTab.values.length,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _retryTimer?.cancel();
    _copyTimer?.cancel();
    _addCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  // ── Computed ──────────────────────────────────────────────────────────────
  UserContext get _userContext => UserContext(
    memoryCount: ((_stats['memories']?['total'] ?? 0) as num).toInt(),
    activeProposals: _proposals.where((p) => p['status'] == _PS.active).length,
    pendingProposals: _proposals.where((p) => p['status'] == _PS.proposal).length,
  );

  ProposalScoreResult _scoreProposal(Map<String, dynamic> proposal, UserContext context) =>
      scoreProposal(proposal, context);

  List<Map<String, dynamic>> get _filteredProposals {
    final context = _userContext;
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
    if (_quickWinsOnly) {
      list = list.where((p) => isQuickWin(_scoreProposal(p, context))).toList();
    }
    const statusOrder = {'active': 0, 'validation': 1, 'draft_plan': 2, 'proposal': 3, 'done': 4};
    list.sort((a, b) {
      final aScore = _scoreProposal(a, context);
      final bScore = _scoreProposal(b, context);
      if (_sortByScore) {
        final byScore = bScore.score.compareTo(aScore.score);
        if (byScore != 0) return byScore;
      }
      final aO = statusOrder[a['status']] ?? 9;
      final bO = statusOrder[b['status']] ?? 9;
      if (aO != bO) return aO - bO;
      if (!_sortByScore) {
        final byScore = bScore.score.compareTo(aScore.score);
        if (byScore != 0) return byScore;
      }
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

  String _statusFilterLabel(String s) => _statusLabels[s] ?? s;

  String _priorityFilterLabel(String p) => _priorityLabels[p] ?? p;

  void _showScoreExplainer(Map<String, dynamic> data) {
    final score = data['weighted_score']?.toString() ?? '—';
    final impact = data['impact']?.toString() ?? '—';
    final effort = data['effort']?.toString() ?? '—';
    final risk   = data['risk']?.toString()   ?? '—';
    _showSnack('Score $score | Impact $impact | Effort $effort | Risk $risk');
  }

  bool get _hasTelemetryConsent => widget.settings.telemetryConsent;

  String _pseudoUserId() {
    final raw = widget.settings.userName.trim().isEmpty ? 'anonymous' : widget.settings.userName.trim();
    final hash = _stableHash(raw).toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return 'u-$hash';
  }

  Map<String, dynamic> _redactMetadata(Map<String, dynamic>? metadata) {
    final source = metadata ?? const <String, dynamic>{};
    final allowedActions = {'start_first', 'sprint_prompt', 'memory_focus'};
    return {
      if (source['compactMode'] is bool) 'compactMode': source['compactMode'],
      if (allowedActions.contains(source['action'])) 'action': source['action'],
    };
  }

  // Compatibility shim for legacy telemetry calls in merge commits.
  Future<void> _trackProposalOutcome(String proposalId, String outcome) async {
    if (!_hasTelemetryConsent) return;
    try {
      await http.post(
        Uri.parse('$_base/dashboard/smart-telemetry'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _pseudoUserId(),
          'eventName': 'proposal_outcome',
          'eventValue': outcome == 'proposal_activated' ? 1 : 0,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'ttl': TelemetryPolicy.ttlForEvent('proposal_outcome'),
          'metadata': {'proposalOutcomeType': outcome},
        }),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

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
    await Future.wait([
      _checkHealth(),
      _loadStats(),
      _loadFeatures(),
      _loadBacklog(),
      _loadAgents(),
      _loadSurveys(),
    ]);
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

  Future<void> _loadSurveys() async {
    setState(() => _loadingSurveys = true);
    final userName = widget.settings.userName.trim().isEmpty ? 'anonymous' : widget.settings.userName.trim();
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$_base/survey-history?userName=${Uri.encodeQueryComponent(userName)}'))
            .timeout(const Duration(seconds: 8)),
        http.get(Uri.parse('$_base/survey-insights?userName=${Uri.encodeQueryComponent(userName)}'))
            .timeout(const Duration(seconds: 12)),
      ]);
      if (!mounted) return;
      if (results[0].statusCode == 200) {
        final d = jsonDecode(results[0].body);
        _surveyHistory = List<Map<String, dynamic>>.from(d['surveys'] ?? []);
      }
      if (results[1].statusCode == 200) {
        final d = jsonDecode(results[1].body);
        _surveyInsights = List<String>.from(d['insights'] ?? []);
      }
      setState(() => _loadingSurveys = false);
    } catch (_) {
      if (mounted) setState(() => _loadingSurveys = false);
    }
  }

  Future<void> _startSurveyNow() async {
    final userName = widget.settings.userName.trim();
    if (userName.isEmpty) {
      _showSnack('צריך להגדיר שם משתמש בהגדרות לפני סקר');
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$_base/survey-check?force=true&userName=${Uri.encodeQueryComponent(userName)}'),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode != 200) {
        _showSnack('לא ניתן להתחיל סקר עכשיו');
        return;
      }
      final d = jsonDecode(res.body);
      if (d['showSurvey'] != true) {
        _showSnack('אין סקר זמין');
        return;
      }
      final questions = List<Map<String, dynamic>>.from(d['questions'] ?? []);
      if (questions.isEmpty) {
        _showSnack('אין סקר זמין');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: JC.surface,
        builder: (ctx) => SurveyModal(
          questions: questions,
          settings: widget.settings,
          onDismiss: () => Navigator.of(ctx).pop(),
        ),
      );
      if (mounted) await _loadSurveys();
    } catch (_) {
      if (mounted) _showSnack('שגיאת רשת');
    }
  }

  Future<void> _loadAgents() async {
    setState(() => _loadingAgents = true);
    try {
      final res = await http.get(Uri.parse('$_base/progress-map/agents')).timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() {
          _agents = List<Map<String, dynamic>>.from(d['agents'] ?? []);
          _loadingAgents = false;
        });
      } else if (mounted) {
        setState(() => _loadingAgents = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAgents = false);
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
          _learnedInsights = List<String>.from(d['learned_insights'] ?? []);
          final config = Map<String, dynamic>.from(d['config'] ?? const {});
          _statusFilters = List<String>.from(config['statusFilters'] ?? _statusFilters);
          _priorityFilters = List<String>.from(config['priorityFilters'] ?? _priorityFilters);
          _statusLabels = Map<String, String>.from(config['labels']?['status'] ?? _statusLabels);
          _priorityLabels = Map<String, String>.from(config['labels']?['priority'] ?? _priorityLabels);
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


  String _proposalSensitivity(Map<String, dynamic> proposal) {
    final policyGate = Map<String, dynamic>.from(proposal['policyGate'] ?? {});
    final sensitivity = policyGate['sensitivity']?.toString() ?? '';
    if (sensitivity == 'high' || sensitivity == 'medium' || sensitivity == 'low') return sensitivity;
    return 'low';
  }

  Future<Map<String, dynamic>?> _collectConsentForSensitivity(String sensitivity) async {
    bool second = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: JC.surface,
          title: const Text('נדרש אישור פרטיות', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Heebo')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (sensitivity != 'low') const Text('תיעוד אנליטי מוגבל (ללא טקסט חופשי).', textAlign: TextAlign.right),
            if (sensitivity == 'high') CheckboxListTile(value: second, onChanged: (v)=>setLocal(()=>second=v??false), title: const Text('אני מאשר/ת שוב (אישור כפול)', style: TextStyle(fontSize: 13)), controlAffinity: ListTileControlAffinity.leading),
          ]),
          actions: [TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('ביטול')), ElevatedButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('אישור'))],
        ),
      ),
    );
    if (ok != true) return null;
    return {
      'explicitApproval': true,
      if (sensitivity != 'low') 'consentLevel': 'explicit',
      if (sensitivity == 'high') 'doubleApproval': second,
      if (sensitivity == 'high') 'ttlMinutes': 15,
    };
  }


  Future<void> _retryProposalAction(Map<String, dynamic> proposal, String actionType) async {
    await _runProposalAction(proposal, actionType, allowRetry: false);
  }

  void _showProposalActionError(String message, Map<String, dynamic> proposal, String actionType) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'נסה שוב',
          onPressed: () => _retryProposalAction(proposal, actionType),
        ),
      ),
    );
  }

  Future<void> _runProposalAction(Map<String, dynamic> proposal, String actionType, {bool allowRetry = true}) async {
    final idRaw = proposal['id'];
    final idStr = idRaw?.toString() ?? '';
    if (idStr.isEmpty || _activatingIds.contains(idStr)) return;

    final current = _proposals.firstWhere((p) => p['id']?.toString() == idStr, orElse: () => proposal);
    final currentStatus = current['status']?.toString() ?? _PS.proposal;

    if (actionType == 'activate') {
      final sensitivity = _proposalSensitivity(current);
      final consent = await _collectConsentForSensitivity(sensitivity);
      if (consent == null) return;
    }

    setState(() => _activatingIds.add(idStr));

    try {
      late http.Response statusRes;
      String nextStatus = currentStatus;
      String? jarvisAnswer;

      if (actionType == 'activate') {
        final shouldCreateDraft = currentStatus == _PS.proposal;
        nextStatus = shouldCreateDraft ? _PS.draftPlan : _PS.active;
        final title = current['title']?.toString() ?? '';
        final plan = current['plan']?.toString() ?? '';

        final statusReq = shouldCreateDraft
            ? http.post(
                Uri.parse('$_base/dashboard/backlog/proposals/$idRaw/draft-plan'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'actor': 'mobile_user', 'reason': 'created draft plan from progress map'}),
              )
            : http.patch(
                Uri.parse('$_base/dashboard/backlog/proposals/$idRaw'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'status': _PS.active, 'actor': 'mobile_user', 'reason': 'activated from progress map'}),
              );

        final results = await Future.wait([
          statusReq.timeout(const Duration(seconds: 8)),
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
        statusRes = results[0] as http.Response;
        final askJarvisRes = results[1] as http.Response;
        jarvisAnswer = askJarvisRes.statusCode == 200
            ? (jsonDecode(askJarvisRes.body) as Map<String, dynamic>)['answer']?.toString() ?? ''
            : 'ג׳רביס לא הגיב';
      } else if (actionType == 'deactivate') {
        nextStatus = currentStatus == _PS.active ? _PS.draftPlan : _PS.proposal;
        statusRes = await http.patch(
          Uri.parse('$_base/dashboard/backlog/proposals/$idRaw'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'status': nextStatus, 'actor': 'mobile_user', 'reason': 'deactivated from progress map'}),
        ).timeout(const Duration(seconds: 8));
      } else if (actionType == 'confirm') {
        nextStatus = currentStatus == _PS.active ? _PS.validation : _PS.done;
        statusRes = await http.patch(
          Uri.parse('$_base/dashboard/backlog/proposals/$idRaw'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'status': nextStatus, 'actor': 'mobile_user', 'reason': 'advanced from progress map'}),
        ).timeout(const Duration(seconds: 8));
      } else {
        throw Exception('unknown action type: $actionType');
      }

      if (statusRes.statusCode < 200 || statusRes.statusCode >= 300) {
        throw Exception('status update failed');
      }

      if (!mounted) return;
      setState(() {
        final idx = _proposals.indexWhere((p) => p['id']?.toString() == idStr);
        if (idx != -1) {
          final payload = jsonDecode(statusRes.body) as Map<String, dynamic>;
          final serverItem = payload['item'];
          if (serverItem is Map<String, dynamic>) {
            _proposals[idx] = Map<String, dynamic>.from(serverItem);
          } else {
            _proposals[idx] = Map<String, dynamic>.from(_proposals[idx])
              ..['status'] = nextStatus;
          }
          _proposals[idx]['lastActionAt'] = DateTime.now().toIso8601String();
          if (actionType == 'deactivate') {
            _proposals[idx]['response'] = '';
          } else {
            _proposals[idx]['response'] = jarvisAnswer ?? _proposalResponses[idStr] ?? '';
          }
        }

        if (jarvisAnswer != null && jarvisAnswer!.isNotEmpty) {
          _proposalResponses[idStr] = jarvisAnswer!;
        }
        if (actionType == 'deactivate') {
          _proposalResponses.remove(idStr);
        }
        _activatingIds.remove(idStr);
      });

      if (actionType == 'activate') {
        await _trackProposalOutcome(idStr, 'proposal_activated');
      } else if (actionType == 'confirm') {
        await _loadBacklog();
      }
      _showSnack(actionType == 'activate'
          ? 'ההצעה עודכנה בהצלחה'
          : actionType == 'deactivate'
              ? 'ההצעה הוחזרה לתכנון'
              : nextStatus == _PS.done
                  ? 'ההצעה סומנה כהושלמה'
                  : 'ההצעה עברה לולידציה');
    } catch (_) {
      if (!mounted) return;
      setState(() => _activatingIds.remove(idStr));
      final message = actionType == 'activate'
          ? 'שגיאה בהפעלת ההצעה'
          : actionType == 'deactivate'
              ? 'לא ניתן להחזיר סטטוס בשלב זה'
              : 'שגיאה בעדכון סטטוס';
      if (allowRetry) {
        _showProposalActionError(message, proposal, actionType);
      } else {
        _showSnack(message);
      }
    }
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
    widget.onSwitchToChat!(cmd);
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: JC.blue400,
            labelColor: JC.blue400,
            unselectedLabelColor: JC.textMuted,
            labelStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
            tabs: const [
              Tab(text: 'סקירה'),
              Tab(text: 'פיתוח'),
              Tab(text: 'סוכנים'),
              Tab(text: 'מידע'),
              Tab(text: 'סקרים'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(),
            _buildDevelopmentTab(),
            _buildAgentsTab(),
            _buildInsightsTab(),
            _buildSurveysTab(),
          ],
        ),
      ),
    );
  }

  Widget _tabListView(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: _loadAll,
      color: JC.blue400,
      backgroundColor: JC.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: children,
      ),
    );
  }

  Widget _buildOverviewTab() => _tabListView([
        _buildStatusBar(),
        const SizedBox(height: 14),
        _buildMetrics(),
        const SizedBox(height: 14),
        _buildSmartRoadmapLab(),
        const SizedBox(height: 14),
        _sectionTitle('🧠 מפת חדשנות'),
        const SizedBox(height: 8),
        _buildInnovationGraphCard(),
      ]);

  Widget _buildDevelopmentTab() => _tabListView([
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
      ]);

  Widget _buildAgentsTab() => _tabListView([
        _sectionTitle('🤖 מרכז סוכנים'),
        const SizedBox(height: 8),
        _buildAgentCenter(),
      ]);

  Widget _buildInsightsTab() => _tabListView([
        _sectionTitle('👤 מה למדנו עליך'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: UserProfilePanel(settings: widget.settings),
        ),
        const SizedBox(height: 24),
        _sectionTitle('🧪 דוחות בדיקות E2E'),
        const SizedBox(height: 8),
        SizedBox(
          height: 480,
          child: E2eReportsPanel(settings: widget.settings),
        ),
      ]);

  Widget _buildSurveysTab() => _tabListView([
        _sectionTitle('📊 תובנות מצטברות'),
        const SizedBox(height: 8),
        _buildSurveyInsightsCard(),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _startSurveyNow,
              icon: const Icon(Icons.poll_outlined, size: 18),
              label: const Text('התחל סקר עכשיו', style: TextStyle(fontFamily: 'Heebo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: JC.blue500,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        _sectionTitle('📋 היסטוריית סקרים'),
        const SizedBox(height: 8),
        _buildSurveyHistory(),
      ]);

  Widget _buildSurveyInsightsCard() {
    if (_loadingSurveys && _surveyInsights.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)),
      );
    }
    if (_surveyInsights.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: const Text(
          'אין עדיין מספיק סקרים לתובנות. השב על כמה סקרים כדי לראות תובנות מצטברות.',
          textAlign: TextAlign.right,
          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _surveyInsights
            .map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $s',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13, height: 1.5)),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildSurveyHistory() {
    if (_loadingSurveys && _surveyHistory.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)),
      );
    }
    if (_surveyHistory.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: const Text(
          'עדיין לא ענית על סקרים.',
          textAlign: TextAlign.right,
          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
        ),
      );
    }
    return Column(
      children: _surveyHistory.map((s) {
        final created = (s['createdAt'] ?? '').toString();
        final summary = (s['summary'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_relativeDate(created),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
              const SizedBox(height: 4),
              Text(summary,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13, height: 1.5)),
            ],
          ),
        );
      }).toList(),
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

  // ── Smart lab (visual + actionable) ─────────────────────────────────────

  Widget _buildSmartRoadmapLab() {
    final doneCount = _done.length;
    final buildingCount = _building.length;
    final plannedCount = _planned.length;
    final total = (doneCount + buildingCount + plannedCount).clamp(1, 99999);
    final maturity = (doneCount / total).clamp(0.0, 1.0);
    final delivery = ((doneCount + (buildingCount * 0.6)) / total).clamp(0.0, 1.0);
    final innovation = ((_proposals.where((p) => p['status'] != _PS.done).length) / 8).clamp(0.2, 1.0);
    final stability = ((_serverOk == true ? 0.9 : 0.55) - ((_latencyMs / 1000).clamp(0.0, 0.2))).clamp(0.2, 1.0);
    final scale = ((_stats['memories']?['total'] ?? 0) / 80).clamp(0.2, 1.0);

    final smartSuggestions = _buildSmartSuggestions();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Switch.adaptive(
              value: _smartCompactMode,
              onChanged: (v) => setState(() => _smartCompactMode = v),
              activeColor: JC.blue400,
            ),
            const Text('MVP', style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
            const Spacer(),
            const Text('מעבדת התפתחות חכמה',
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 6),
          const Text('מנוע תעדוף חי: מציג כיווני שיפור ועוזר להתחיל ביצוע עכשיו. מצב MVP פעיל כברירת מחדל.',
              textAlign: TextAlign.right,
              style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
          const SizedBox(height: 12),
          _build3DSignalCard(maturity, delivery, innovation, stability, scale),
          const SizedBox(height: 12),
          ...smartSuggestions.map((s) => _buildSmartSuggestionTile(s)).toList(),
          const SizedBox(height: 6),
          _buildLearnedInsights(),
          const SizedBox(height: 6),
          _buildSmartTelemetryPanel(),
          if (!_smartCompactMode) _buildSmartExplainPanel(),
        ],
      ),
    );
  }

  Widget _buildLearnedInsights() {
    if (_learnedInsights.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.border, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('למדנו ש...',
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final line in _learnedInsights.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $line',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  List<Map<String, String>> _buildSmartSuggestions() {
    final suggestions = <Map<String, String>>[];
    if (_proposals.where((p) => p['status'] == _PS.active).isEmpty) {
      suggestions.add({
        'title': 'להפעיל הצעה אחת עכשיו',
        'reason': 'אין כרגע הצעה פעילה, לכן הלמידה בפועל תקועה.',
        'action': 'start_first',
      });
    }
    if ((_stats['memories']?['total'] ?? 0) < 10) {
      suggestions.add({
        'title': 'לחזק זיכרון אישי',
        'reason': 'פחות מ-10 זיכרונות מורידים איכות פרסונליזציה.',
        'action': 'memory_focus',
      });
    }
    suggestions.add({
      'title': _smartCompactMode ? 'לנסח ספרינט MVP' : 'לנסח ספרינט שיפורים',
      'reason': 'ממפה שינויים, סוכנים ופיצ׳רים לפורמט אחד שניתן להריץ.',
      'action': 'sprint_prompt',
    });
    return suggestions.take(3).toList();
  }

  Widget _build3DSignalCard(double m, double d, double i, double s, double sc) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF0F172A)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX(0.2)
            ..rotateY(-0.28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _signalBar('בשלות', m),
              _signalBar('מסירה', d),
              _signalBar('חדשנות', i),
              _signalBar('יציבות', s),
              _signalBar('סקייל', sc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signalBar(String label, double value) {
    final h = 24 + (90 * value);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 10)),
        const SizedBox(height: 4),
        Container(
          width: 22,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: const LinearGradient(
              colors: [Color(0xFF38BDF8), Color(0xFF22D3EE), Color(0xFF34D399)],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            boxShadow: const [BoxShadow(color: Color(0x5538BDF8), blurRadius: 8, offset: Offset(0, 3))],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 52,
          child: Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontFamily: 'Heebo', fontSize: 10)),
        ),
      ],
    );
  }

  Widget _buildSmartSuggestionTile(Map<String, String> suggestion) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JC.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.border, width: 0.7),
      ),
      child: ListTile(
        dense: true,
        title: Text(suggestion['title'] ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(suggestion['reason'] ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
        trailing: TextButton(
          onPressed: () => _confirmSmartAction(suggestion),
          child: const Text('הפעל', style: TextStyle(fontFamily: 'Heebo')),
        ),
      ),
    );
  }

  Widget _buildSmartExplainPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.border, width: 0.7),
      ),
      child: const Text(
        'פרטיות והרשאות: פעולות המעבדה משתמשות רק בנתונים שכבר נטענו למסך. מומלץ להוסיף בהמשך פרופיל הרשאות פר-משתמש לפני אוטומציה מלאה.',
        textAlign: TextAlign.right,
        style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
      ),
    );
  }

  Widget _buildSmartTelemetryPanel() {
    int v(String k) => _smartTelemetry[k] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: JC.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.border, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('מדדי שימוש (MVP מקומי)',
              textAlign: TextAlign.right,
              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('אישורים: ${v('confirm_yes')} | ביטולים: ${v('confirm_no')}',
              style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
          Text('הפעל הצעה: ${v('action_start_first')} | חיזוק זיכרון: ${v('action_memory_focus')}',
              style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
          Text('Sprint MVP: ${v('action_sprint_prompt_mvp')} | Sprint מורחב: ${v('action_sprint_prompt_full')}',
              style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildInnovationGraphCard() {
    final nodes = _buildGraphNodes();
    final edges = _buildGraphEdges(nodes);
    final weakMode = MediaQuery.of(context).size.width < 390;
    if (weakMode) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('מצב 2D פשוט · ${nodes.length} ישויות', style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
          const SizedBox(height: 8),
          ...nodes.take(8).map((n) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: JC.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: JC.border, width: .7)),
            child: Text('${n.label} · ${n.type} · score ${n.score}', textAlign: TextAlign.right, style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12)),
          )),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('גרף חי · ${nodes.length} ישויות · ${edges.length} קשרים', style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
        const SizedBox(height: 8),
        SizedBox(
          height: 250,
          child: LayoutBuilder(builder: (_, c) {
            return GestureDetector(
              onTapUp: (d) => _onGraphTap(d.localPosition, c.maxWidth, 250, nodes),
              child: CustomPaint(
                painter: _InnovationGraphPainter(nodes: nodes, edges: edges, width: c.maxWidth, height: 250),
                child: Container(),
              ),
            );
          }),
        ),
        if (_selectedGraphNode != null) ...[
          const SizedBox(height: 8),
          Text(
            'נבחר: ${_selectedGraphNode!.label}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11),
          ),
        ]
      ]),
    );
  }

  void _onGraphTap(Offset tap, double width, double height, List<_GraphNode> nodes) {
    final points = _buildStableGraphPoints(nodes: nodes, width: width, height: height);
    int nearest = -1;
    double best = 999999;
    for (var i = 0; i < points.length; i++) {
      final d = (points[i] - tap).distance;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    if (nearest < 0 || best > 26) return;
    final node = nodes[nearest];
    setState(() => _selectedGraphNode = node);
    _showGraphNodeActions(node);
  }

  Future<void> _showGraphNodeActions(_GraphNode node) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(node.label, textAlign: TextAlign.right, style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'why_now: ${node.whyNow}\nscore: ${node.score.toStringAsFixed(0)} · impact: ${node.impact.toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  _graphActionBtn('⚡ activate', () => _runGraphAction('activate', node)),
                  _graphActionBtn('🕒 defer', () => _runGraphAction('defer', node)),
                  _graphActionBtn('✂️ split', () => _runGraphAction('split', node)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _graphActionBtn(String label, VoidCallback onTap) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(side: const BorderSide(color: JC.border), foregroundColor: JC.textPrimary),
    child: Text(label, style: const TextStyle(fontFamily: 'Heebo')),
  );

  void _runGraphAction(String action, _GraphNode node) {
    Navigator.pop(context);
    _trackSmartEvent('graph_action_$action', metadata: {'node': node.label, 'type': node.type});
    _applyGraphAction(action, node);
  }

  Future<void> _applyGraphAction(String action, _GraphNode node) async {
    try {
      final resp = await http.post(
        Uri.parse('$_base/dashboard/graph/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nodeId': node.nodeId,
          'nodeLabel': node.label,
          'nodeType': node.type,
          'action': action,
          'source': 'mobile',
          'actor': widget.settings.userName.trim().isEmpty ? 'anonymous' : widget.settings.userName.trim(),
        }),
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _showSnack('בוצע: $action עבור ${node.label}');
        await _loadBacklog();
      } else {
        _showSnack('הפעולה נכשלה (${resp.statusCode})');
      }
    } catch (_) {
      _showSnack('שגיאת רשת בזמן ביצוע פעולה');
    }
  }

  List<_GraphNode> _buildGraphNodes() {
    final out = <_GraphNode>[];
    final features = [..._done, ..._building, ..._planned];
    for (var i = 0; i < features.length; i++) {
      final f = features[i];
      final label = (f['name'] ?? 'Feature').toString();
      final fallbackSeed = (f['createdAt'] ?? f['updatedAt'] ?? i).toString();
      out.add(_GraphNode(nodeId: _ensureStableNodeId(rawNodeId: (f['id'] ?? '').toString(), label: label, type: 'feature', fallbackSeed: fallbackSeed), label: label, type: 'feature', impact: ((f['impact'] ?? 6) as num).toDouble(), score: ((f['score'] ?? 72) as num).toDouble(), whyNow: (f['why_now'] ?? f['desc'] ?? 'משפיע על תפקוד ליבה').toString()));
    }
    final context = _userContext;
    final proposals = _proposals.take(12).toList();
    for (var i = 0; i < proposals.length; i++) {
      final p = proposals[i];
      final computed = _scoreProposal(p, context);
      final label = (p['title'] ?? 'Proposal').toString();
      final fallbackSeed = (p['createdAt'] ?? p['updatedAt'] ?? i).toString();
      out.add(_GraphNode(nodeId: _ensureStableNodeId(rawNodeId: (p['id'] ?? '').toString(), label: label, type: 'proposal', fallbackSeed: fallbackSeed), label: label, type: 'proposal', impact: computed.impact, score: computed.score, whyNow: computed.whyNow));
    }
    out.add(const _GraphNode(nodeId: 'agent-jarvis', label: 'Jarvis Agent', type: 'agent', impact: 8, score: 88, whyNow: 'מרכז תיאום בין יכולות להצעות'));
    return out;
  }

  List<_GraphEdge> _buildGraphEdges(List<_GraphNode> nodes) {
    final edges = <_GraphEdge>[];
    if (nodes.length < 2) return edges;
    for (var i = 0; i < nodes.length - 1; i++) {
      final type = i % 3 == 0 ? 'dependency' : i % 3 == 1 ? 'similarity' : 'user-goal';
      edges.add(_GraphEdge(from: i, to: i + 1, relationshipType: type));
    }
    return edges;
  }

  Future<void> _confirmSmartAction(Map<String, String> suggestion) async {
    final action = suggestion['action'] ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JC.surface,
        title: Text(suggestion['title'] ?? 'הפעלת פעולה',
            textAlign: TextAlign.right,
            style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo')),
        content: const Text('לבצע עכשיו את הפעולה הזו?',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ביטול')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('הפעל')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _smartTelemetry['confirm_yes'] = (_smartTelemetry['confirm_yes'] ?? 0) + 1);
      _trackSmartEvent('confirm_yes', metadata: {
        'action': action,
        'compactMode': _smartCompactMode,
      });
      await _runSmartAction(action);
    } else {
      setState(() => _smartTelemetry['confirm_no'] = (_smartTelemetry['confirm_no'] ?? 0) + 1);
      _trackSmartEvent('confirm_no', metadata: {
        'action': action,
        'compactMode': _smartCompactMode,
      });
    }
  }

  Future<void> _runSmartAction(String action) async {
    if (action == 'start_first') {
      setState(() => _smartTelemetry['action_start_first'] = (_smartTelemetry['action_start_first'] ?? 0) + 1);
      _trackSmartEvent('action_start_first', metadata: {'compactMode': _smartCompactMode});
      final firstProposal = _proposals.firstWhere(
        (p) => p['status'] == _PS.proposal,
        orElse: () => <String, dynamic>{},
      );
      if (firstProposal.isNotEmpty) {
        await _runProposalAction(firstProposal, 'activate');
        return;
      }
    }
    if (action == 'sprint_prompt') {
      setState(() => _smartTelemetry['action_sprint_prompt'] = (_smartTelemetry['action_sprint_prompt'] ?? 0) + 1);
      setState(() {
        final key = _smartCompactMode ? 'action_sprint_prompt_mvp' : 'action_sprint_prompt_full';
        _smartTelemetry[key] = (_smartTelemetry[key] ?? 0) + 1;
      });
      _trackSmartEvent(
        _smartCompactMode ? 'action_sprint_prompt_mvp' : 'action_sprint_prompt_full',
        metadata: {'compactMode': _smartCompactMode},
      );
      _promptCtrl.text =
          _smartCompactMode
              ? 'בנה ספרינט MVP לשבוע הקרוב במערכת Jarvis: 3 משימות בלבד, בסדר עדיפויות ברור, כולל פרטיות והרשאות.'
              : 'בנה ספרינט שבועי חכם למערכת Jarvis: שינויים בארכיטקטורה, שדרוג סוכנים, פיצ׳רים חדשים, '
                    'שיפורי UI/UX, פרטיות והרשאות. הוסף סדר עדיפויות + משימות MVP.';
      await _generatePrompt();
      return;
    }
    setState(() => _smartTelemetry['action_memory_focus'] = (_smartTelemetry['action_memory_focus'] ?? 0) + 1);
    _trackSmartEvent('action_memory_focus', metadata: {'compactMode': _smartCompactMode});
    widget.onSwitchToChat?.call('בוא נבנה תכנית ממוקדת לשיפור זיכרון אישי ולמידת משתמש בצורה פרטית ובטוחה.');
  }

  Future<void> _trackSmartEvent(String eventName, {Map<String, dynamic>? metadata}) async {
    if (!_hasTelemetryConsent) return;
    try {
      await http.post(
        Uri.parse('$_base/dashboard/smart-telemetry'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _pseudoUserId(),
          'eventName': eventName,
          'eventValue': 1,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'ttl': TelemetryPolicy.ttlForEvent(eventName),
          'metadata': _redactMetadata(metadata),
        }),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      // Telemetry must never block UX.
    }
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
                style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab selector
        Row(
          children: List.generate(3, (i) {
            final selected = i == _featureTabIndex;
            final color    = colors[i];
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _featureTabIndex = i;
                    _selectedChipKey = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? color.withValues(alpha: 0.6) : JC.border,
                        width: selected ? 1.2 : 0.5,
                      ),
                    ),
                    child: Text(labels[i],
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? color : JC.textSecondary,
                          fontFamily: 'Heebo',
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 12,
                          height: 1.2,
                        )),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // Chips
        if (currentItems.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('אין פריטים',
                style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13))),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: currentItems.map((f) => _featureChip(f, currentColor)).toList(),
          ),
        // Detail panel for selected chip
        Builder(builder: (context) {
          if (_selectedChipKey == null) return const SizedBox.shrink();
          final sel = currentItems.cast<Map<String, dynamic>?>().firstWhere(
            (f) => 'feature_${f!['name']?.hashCode}' == _selectedChipKey,
            orElse: () => null,
          );
          if (sel == null) return const SizedBox.shrink();
          final name = sel['name']?.toString() ?? '';
          final desc = sel['desc']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: currentColor.withValues(alpha: 0.35), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: currentColor,
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(desc,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            color: JC.textSecondary,
                            fontFamily: 'Heebo',
                            fontSize: 12,
                            height: 1.5)),
                  ],
                ],
              ),
            ),
          );
        }),
        if (_featuresUpdated.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('עודכן: $_featuresUpdated',
                style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _featureChip(Map<String, dynamic> f, Color color) {
    final name = f['name']?.toString() ?? '—';
    final key  = 'feature_${name.hashCode}';
    final isSelected = _selectedChipKey == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedChipKey = isSelected ? null : key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : JC.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected ? color : JC.border,
              width: isSelected ? 1.2 : 0.5),
        ),
        child: Text(name,
            style: TextStyle(
                color: isSelected ? color : JC.textSecondary,
                fontFamily: 'Heebo',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
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
                  for (final s in _statusFilters)
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
                  for (final p in _priorityFilters)
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
                  const SizedBox(width: 8),
                  _filterChip(
                    'Quick Wins',
                    _quickWinsOnly,
                    () => setState(() => _quickWinsOnly = !_quickWinsOnly),
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    _sortByScore ? 'מיון: ציון' : 'מיון: סטטוס',
                    _sortByScore,
                    () => setState(() => _sortByScore = !_sortByScore),
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
    final computed = _scoreProposal(p, _userContext);
    final scores = <String, dynamic>{
      'impact': computed.impact.toStringAsFixed(1),
      'effort': computed.effort.toStringAsFixed(1),
      'risk': computed.privacyRisk.toStringAsFixed(1),
      'confidence': computed.confidence.toStringAsFixed(1),
      'weighted_score': computed.score.toStringAsFixed(0),
    };
    final whyNow = computed.whyNow;
    final idRaw   = p['id'];
    final idStr   = idRaw?.toString() ?? '';
    final status  = p['status']?.toString() ?? _PS.proposal;
    final priority = p['priority']?.toString() ?? 'medium';
    final isActive = status == _PS.active;
    final isDraftPlan = status == _PS.draftPlan;
    final isValidation = status == _PS.validation;
    final isDone   = status == _PS.done;
    final title    = p['title']?.toString() ?? '';
    final plan     = p['plan']?.toString()  ?? '';
    final dateLabel = _relativeDate(p['createdAt']?.toString());

    final priorityColor = _priorityColor(priority);
    final priorityLbl   = _priorityLabel(priority);
    final catLabel      = _kCatMap[p['category']?.toString()] ?? (p['category']?.toString() ?? '');
    final statusLabel = status == _PS.proposal
        ? '💡 הצעה'
        : status == _PS.draftPlan
            ? '🧭 תכנון'
            : status == _PS.active
                ? '⚡ בביצוע'
                : status == _PS.validation
                    ? '🧪 ולידציה'
                    : '✅ הושלם';
    final statusColor = status == _PS.active
        ? JC.blue400
        : status == _PS.validation
            ? const Color(0xFFF59E0B)
            : isDone ? const Color(0xFF22C55E) : JC.textMuted;

    final activating = _activatingIds.contains(idStr);
    final response   = _proposalResponses[idStr];
    final checklist = List<Map<String, dynamic>>.from(p['checklist'] ?? []);
    final blockers = List<dynamic>.from(p['blockers'] ?? []);
    final doneCount = checklist.where((c) => c['done'] == true).length;
    final auditTrail = List<Map<String, dynamic>>.from(p['auditTrail'] ?? []);

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
                      if (scores.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _showScoreExplainer(scores),
                              child: const Icon(Icons.info_outline_rounded, color: JC.textMuted, size: 16),
                            ),
                            const SizedBox(width: 6),
                            const Text('הסבר ציון',
                                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _badge('Impact ${scores['impact'] ?? '—'}/5', const Color(0xFF22C55E)),
                            _badge('Effort ${scores['effort'] ?? '—'}/5', const Color(0xFFF59E0B)),
                            _badge('Risk ${scores['risk'] ?? '—'}/5', const Color(0xFFEF4444)),
                            _badge('Conf ${scores['confidence'] ?? '—'}/5', JC.blue400),
                            _badge('Score ${scores['weighted_score'] ?? '—'}', const Color(0xFFA78BFA)),
                          ],
                        ),
                      ],
                      if (whyNow.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: JC.blue500.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: JC.blue400.withValues(alpha: 0.22), width: 0.8),
                          ),
                          child: Text(
                            'למה עכשיו: $whyNow',
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              color: JC.textSecondary,
                              fontFamily: 'Heebo',
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (isActive && checklist.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text('תתי-שלבים: $doneCount/${checklist.length}',
                              style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11)),
                        ),
                        const SizedBox(height: 4),
                        ...checklist.take(4).map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Icon(c['done'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 14, color: c['done'] == true ? const Color(0xFF22C55E) : JC.textMuted),
                              const SizedBox(width: 6),
                              Expanded(child: Text(c['text']?.toString() ?? '',
                                  style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12))),
                            ],
                          ),
                        )),
                        if (blockers.isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text('חסימות: ${blockers.join(' | ')}',
                                style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo', fontSize: 11)),
                          ),
                        const SizedBox(height: 8),
                      ],
                      if (auditTrail.isNotEmpty && (isActive || isValidation || isDone)) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Audit: ${auditTrail.first['by'] ?? 'system'} · ${_relativeDate(auditTrail.first['at']?.toString())} · ${auditTrail.first['reason'] ?? ''}',
                            style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Badges + activate button
                      if (!isDone)
                        Align(
                          alignment: Alignment.centerRight,
                          child: const Text('נדרש אישור פרטיות', style: TextStyle(color: Color(0xFFF59E0B), fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      if (!isDone) const SizedBox(height: 6),
                      Row(
                        children: [
                          if (!isDone)
                            GestureDetector(
                              onTap: activating
                                  ? null
                                  : () {
                                      if (isActive) {
                                        _runProposalAction(p, 'deactivate');
                                      } else {
                                        _runProposalAction(p, 'activate');
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
                                    : Text(isActive ? '⏸ חזרה לתכנון' : isDraftPlan ? '⚡ התחל ביצוע' : isValidation ? '⚡ חזרה לביצוע' : '🧭 צור תכנית',
                                        style: const TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                            fontWeight: FontWeight.w600, fontSize: 11)),
                              ),
                            ),
                          if (!isDone && (isActive || isValidation)) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () async {
                                await _runProposalAction(p, 'confirm');
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.35), width: 0.8),
                                ),
                                child: Text(isActive ? '🧪 לולידציה' : '✅ סיום',
                                    style: const TextStyle(color: Color(0xFF22C55E), fontFamily: 'Heebo',
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                crossAxisAlignment: CrossAxisAlignment.start,
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

  // ── Agent Center ──────────────────────────────────────────────────────────

  Color _riskColor(String risk) => switch (risk) {
        'high' => const Color(0xFFEF4444),
        'medium' => const Color(0xFFF59E0B),
        'low' => const Color(0xFF22C55E),
        _ => JC.textMuted,
      };

  String _riskLabel(String risk) => switch (risk) {
        'high' => 'סיכון גבוה',
        'medium' => 'סיכון בינוני',
        'low' => 'סיכון נמוך',
        _ => risk,
      };

  Widget _buildAgentCenter() {
    if (_loadingAgents && _agents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)),
      );
    }
    if (_agents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: const Text(
          'לא נטענו סוכנים. בדוק חיבור לשרת.',
          textAlign: TextAlign.right,
          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              '${_agents.length} סוכנים פעילים · הקש לפרטים',
              textAlign: TextAlign.right,
              style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          ..._agents.map(_buildAgentTile),
        ],
      ),
    );
  }

  Widget _buildAgentTile(Map<String, dynamic> agent) {
    final nameHe = (agent['nameHe'] ?? agent['name'] ?? agent['id'] ?? '').toString();
    final role = (agent['role'] ?? '').toString();
    final risk = (agent['risk'] ?? 'low').toString();
    final mode = (agent['mode'] ?? '').toString();
    final autonomy = (agent['autonomy'] ?? 0) as num;
    final status = (agent['status'] ?? 'active').toString();
    return GestureDetector(
      onTap: () => _showAgentDetails(agent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: JC.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: JC.border, width: 0.7),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status == 'active' ? const Color(0xFF22C55E) : JC.textMuted,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nameHe,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13)),
                  if (role.isNotEmpty)
                    Text(role,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 4,
              children: [
                _badge(_riskLabel(risk), _riskColor(risk)),
                if (mode.isNotEmpty) _badge(mode, JC.blue400),
                _badge('${autonomy.toInt()}%', JC.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAgentDetails(Map<String, dynamic> agent) {
    final nameHe = (agent['nameHe'] ?? agent['name'] ?? agent['id'] ?? '').toString();
    final mission = (agent['mission'] ?? '').toString();
    final prompt = (agent['prompt'] ?? '').toString();
    final responsibilities = List<String>.from(agent['responsibilities'] ?? const []);
    final tools = List<String>.from(agent['tools'] ?? const []);
    final permissions = List<String>.from(agent['permissions'] ?? const []);
    final connections = List<Map<String, dynamic>>.from(
        (agent['connections'] ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nameHe,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 18)),
                const SizedBox(height: 4),
                if ((agent['role'] ?? '').toString().isNotEmpty)
                  Text(agent['role'].toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
                const SizedBox(height: 10),
                if (mission.isNotEmpty) ...[
                  _agentSectionLabel('משימה'),
                  _agentBodyText(mission),
                  const SizedBox(height: 10),
                ],
                if (prompt.isNotEmpty) ...[
                  _agentSectionLabel('פרומפט'),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: JC.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: JC.border, width: 0.7),
                    ),
                    child: Text(prompt,
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.4)),
                  ),
                  const SizedBox(height: 10),
                ],
                if (responsibilities.isNotEmpty) ...[
                  _agentSectionLabel('אחריות'),
                  ...responsibilities.map((r) => _agentBodyText('• $r')),
                  const SizedBox(height: 10),
                ],
                if (tools.isNotEmpty) ...[
                  _agentSectionLabel('כלים'),
                  _agentBodyText(tools.join(' · ')),
                  const SizedBox(height: 10),
                ],
                if (permissions.isNotEmpty) ...[
                  _agentSectionLabel('הרשאות'),
                  _agentBodyText(permissions.join(' · ')),
                  const SizedBox(height: 10),
                ],
                if (connections.isNotEmpty) ...[
                  _agentSectionLabel('קשרים'),
                  ...connections.map((c) {
                    final name = (c['nameHe'] ?? c['name'] ?? c['agentId'] ?? '').toString();
                    final dir = (c['direction'] ?? '').toString();
                    final type = (c['type'] ?? '').toString();
                    final arrow = dir == 'outgoing' ? '→' : dir == 'incoming' ? '←' : '↔';
                    return _agentBodyText('$arrow $name · $type');
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _agentSectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            textAlign: TextAlign.right,
            style: const TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5)),
      );

  Widget _agentBodyText(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            textAlign: TextAlign.right,
            style: const TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.4)),
      );

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
