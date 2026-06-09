import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../widgets/agent_detail_sheet.dart';
import '../app_settings.dart';
import '../settings_screen.dart';
import '../services/proposal_scoring.dart';
import '../services/telemetry_policy.dart';
import '../transitions/slide_fade_route.dart';
import 'e2e_reports_screen.dart';

/// Unified Control Center tabs. Order drives both the TabBar and the per-tab
/// badge mapping from /control-center/events.
///   overview     → סקירה ובריאות
///   agents       → סוכנים
///   development  → פיתוח / Roadmap
///   testsSurveys → בדיקות וסקרים (E2E reports + read-only survey summary)
///   settings     → הגדרות
enum ControlCenterTab { overview, agents, development, testsSurveys, settings }

class _CcAlert {
  final String id;
  final String type;
  final String severity; // info | warning | urgent
  final String title;
  final String message;
  final String? tabHint;
  final String? actionHint;
  final Map<String, dynamic> actionPayload;
  final String createdAt;
  const _CcAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.message,
    this.tabHint,
    this.actionHint,
    this.actionPayload = const {},
    required this.createdAt,
  });
  factory _CcAlert.fromJson(Map<String, dynamic> j) => _CcAlert(
        id: j['id']?.toString() ?? '',
        type: j['type']?.toString() ?? 'info',
        severity: j['severity']?.toString() ?? 'info',
        title: j['title']?.toString() ?? '',
        message: j['message']?.toString() ?? '',
        tabHint: j['tabHint']?.toString(),
        actionHint: j['actionHint']?.toString(),
        actionPayload: Map<String, dynamic>.from(j['actionPayload'] ?? const {}),
        createdAt: j['createdAt']?.toString() ?? '',
      );
}

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

int _stableHash(String input) {
  // FNV-1a 32-bit hash: deterministic across app runs/devices.
  var hash = 0x811C9DC5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

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

  // NL command bar (POST /progress-map/command)
  final _cmdCtrl = TextEditingController();
  bool _runningCmd = false;
  String? _cmdAnswer;

  // Proactive insights (POST /dashboard/analytics/insights — server-cached)
  List<Map<String, dynamic>> _insights = const [];
  bool _loadingInsights = true;
  String _insightsSource = '';

  // Surveys
  List<Map<String, dynamic>> _surveyHistory = [];
  List<String> _surveyInsights = [];
  bool _loadingSurveys = true;
  String? _surveyError;

  // Live control-center events (alerts + per-tab badges)
  List<_CcAlert> _alerts = const [];
  Map<ControlCenterTab, int> _tabBadges = const {};
  final Set<String> _dismissedAlertIds = <String>{};
  String? _eventsCursorIso;            // last seen alert createdAt
  Timer? _pollTimer;
  Duration _pollInterval = const Duration(seconds: 15);
  int _pollNoChangeStreak = 0;         // adaptive backoff signal
  bool _pollInFlight = false;
  bool _isForeground = true;
  // Per-tile in-flight set for the agent enable/disable quick action.
  final Set<String> _togglingAgents = <String>{};
  bool _triggeringE2e = false;
  bool _scanningErrors = false;

  // Adaptive polling cadence — keeps the UI feeling live while idle
  // sessions ease off to save battery and server load.
  static const Duration _kPollMin = Duration(seconds: 15);
  static const Duration _kPollIdle = Duration(seconds: 30);
  static const Duration _kPollMax = Duration(seconds: 60);
  static const int _kIdleStreakStep1 = 3;  // after 3 no-change polls → idle
  static const int _kIdleStreakStep2 = 6;  // after 6 → max backoff

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  // True while a role-switch POST is in flight (disables the role chips).
  bool _settingRole = false;

  // Regular users see only the personal tabs (overview + settings); admins see
  // all five. Mirrors the role gating in the web control center (progress-map.html).
  bool get _isAdmin => widget.settings.role == 'admin';
  List<ControlCenterTab> get _visibleTabs => _isAdmin
      ? ControlCenterTab.values.toList()
      : const [ControlCenterTab.overview, ControlCenterTab.settings];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initIdx = _visibleTabs.indexOf(widget.initialTab);
    _tabController = TabController(
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: initIdx >= 0 ? initIdx : 0,
    );
    _loadAll().whenComplete(() {
      // Kick off the live poller after the initial load so the first
      // events fetch carries a real `since` cursor.
      _schedulePoll(initial: true);
    });
  }

  // Navigate to a logical tab by mapping it to its position in the currently
  // visible set (the TabController index != enum index once tabs are gated).
  void _goToTab(ControlCenterTab tab) {
    final i = _visibleTabs.indexOf(tab);
    if (i >= 0) _tabController.animateTo(i);
  }

  // Role is server-driven: pull it from the profile and, if it changed, rebuild
  // the TabController so the visible-tab count matches. One-time on most launches.
  Future<void> _loadRole() async {
    try {
      final res = await http.get(Uri.parse('$_base/user-profile')).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted) return;
      final profile = (jsonDecode(res.body) as Map<String, dynamic>)['profile'];
      if (profile is! Map) return;
      final prefs = profile['preferences'];
      final role = (prefs is Map && prefs['role'] is String) ? prefs['role'] as String : 'user';
      if (role == widget.settings.role) return;
      // Capture the current tab from the OLD visible set before flipping role.
      final oldVisible = _visibleTabs;
      final oldTab = oldVisible[_tabController.index.clamp(0, oldVisible.length - 1).toInt()];
      widget.settings.role = role;
      await widget.settings.save();
      if (!mounted) return;
      _tabController.dispose();
      final newIdx = _visibleTabs.indexOf(oldTab); // _visibleTabs now reflects new role
      _tabController = TabController(
        length: _visibleTabs.length,
        vsync: this,
        initialIndex: newIdx >= 0 ? newIdx : 0,
      );
      setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _tabController.dispose();
    _retryTimer?.cancel();
    _copyTimer?.cancel();
    _addCtrl.dispose();
    _promptCtrl.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    if (isForeground == _isForeground) return;
    _isForeground = isForeground;
    if (isForeground) {
      // Reset cadence on resume — the user is engaged again.
      _pollNoChangeStreak = 0;
      _pollInterval = _kPollMin;
      _schedulePoll(immediate: true);
    } else {
      _pollTimer?.cancel();
    }
  }

  // ── Adaptive polling ──────────────────────────────────────────────────────

  void _schedulePoll({bool initial = false, bool immediate = false}) {
    _pollTimer?.cancel();
    if (!mounted || !_isForeground) return;
    final delay = immediate
        ? const Duration(milliseconds: 100)
        : (initial ? _kPollMin : _pollInterval);
    _pollTimer = Timer(delay, _pollEvents);
  }

  Future<void> _pollEvents() async {
    if (!mounted || _pollInFlight) {
      _schedulePoll();
      return;
    }
    _pollInFlight = true;
    try {
      final qp = <String, String>{};
      if (_eventsCursorIso != null) qp['since'] = _eventsCursorIso!;
      final userName = widget.settings.userName.trim();
      if (userName.isNotEmpty) qp['userName'] = userName;
      final uri = Uri.parse('$_base/control-center/events')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode != 200) {
        _bumpNoChangeStreak();
        _schedulePoll();
        return;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rawAlerts = List<Map<String, dynamic>>.from(body['alerts'] ?? const []);
      final newAlerts = rawAlerts.map(_CcAlert.fromJson).toList();
      final newBadges = _decodeBadges(body['badges']);
      final newCursor = body['generatedAt']?.toString();

      // Detect whether anything actually changed since last poll.
      final changed = !_alertsListEquals(_alerts, newAlerts) || !_badgesEqual(_tabBadges, newBadges);
      // Surface a snackbar for newly-arrived urgent alerts.
      final urgentNew = newAlerts.where((a) =>
          a.severity == 'urgent' &&
          !_dismissedAlertIds.contains(a.id) &&
          !_alerts.any((p) => p.id == a.id));
      for (final a in urgentNew) {
        _showSnack('⚠️ ${a.title}: ${a.message}', duration: const Duration(seconds: 5));
      }

      setState(() {
        _alerts = newAlerts;
        _tabBadges = newBadges;
        if (newCursor != null) _eventsCursorIso = newCursor;
      });

      if (changed) {
        _pollNoChangeStreak = 0;
        _pollInterval = _kPollMin;
      } else {
        _bumpNoChangeStreak();
      }
    } catch (_) {
      _bumpNoChangeStreak();
    } finally {
      _pollInFlight = false;
      _schedulePoll();
    }
  }

  void _bumpNoChangeStreak() {
    _pollNoChangeStreak++;
    if (_pollNoChangeStreak >= _kIdleStreakStep2) {
      _pollInterval = _kPollMax;
    } else if (_pollNoChangeStreak >= _kIdleStreakStep1) {
      _pollInterval = _kPollIdle;
    }
  }

  Map<ControlCenterTab, int> _decodeBadges(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <ControlCenterTab, int>{};
    raw.forEach((k, v) {
      if (v is! num) return;
      final key = k.toString();
      // Legacy server keys (insights / surveys) now both fold into the merged
      // "בדיקות וסקרים" tab so existing event payloads keep working.
      final tab = switch (key) {
        'insights' || 'surveys' => ControlCenterTab.testsSurveys,
        _ => ControlCenterTab.values.firstWhere(
              (t) => t.name == key,
              orElse: () => ControlCenterTab.overview,
            ),
      };
      if (key == 'insights' || key == 'surveys' || tab.name == key) {
        out[tab] = (out[tab] ?? 0) + v.toInt();
      }
    });
    return out;
  }

  bool _alertsListEquals(List<_CcAlert> a, List<_CcAlert> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  bool _badgesEqual(Map<ControlCenterTab, int> a, Map<ControlCenterTab, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  List<_CcAlert> get _visibleAlerts =>
      _alerts.where((a) => !_dismissedAlertIds.contains(a.id)).toList();

  void _dismissAlert(String id) {
    setState(() => _dismissedAlertIds.add(id));
  }

  Future<void> _runAlertAction(_CcAlert alert) async {
    switch (alert.actionHint) {
      case 'rerun_e2e':
        await _triggerE2eRun();
        _dismissAlert(alert.id);
        break;
      case 'open_e2e_report':
        _goToTab(ControlCenterTab.testsSurveys);
        _dismissAlert(alert.id);
        break;
      case 'promote_proposal':
        final pid = alert.actionPayload['proposalId']?.toString();
        if (pid != null && pid.isNotEmpty) {
          final p = _proposals.firstWhere(
            (x) => x['id']?.toString() == pid,
            orElse: () => const <String, dynamic>{},
          );
          if (p.isNotEmpty) {
            _goToTab(ControlCenterTab.development);
            await _promoteProposalQuick(p);
            _dismissAlert(alert.id);
            break;
          }
        }
        _goToTab(ControlCenterTab.development);
        _dismissAlert(alert.id);
        break;
      case 'start_survey':
        _goToTab(ControlCenterTab.testsSurveys);
        _dismissAlert(alert.id);
        break;
      case 'open_chat':
        widget.onSwitchToChat?.call('');
        _dismissAlert(alert.id);
        break;
      default:
        if (alert.tabHint != null) {
          final tab = ControlCenterTab.values.firstWhere(
            (t) => t.name == alert.tabHint,
            orElse: () => ControlCenterTab.overview,
          );
          _goToTab(tab);
        }
        _dismissAlert(alert.id);
    }
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
      _loadProviderTelemetry(),
      _loadRole(),
      _loadInsights(),
    ]);
    _isRefreshing = false;
    if (mounted && _serverOk != true) _scheduleRetry();
  }

  /// Fetch per-provider LLM usage counters from server smart-telemetry and
  /// merge into the local map so the dashboard can render the breakdown.
  Future<void> _loadProviderTelemetry() async {
    try {
      final userId = _pseudoUserId();
      final res = await http
          .get(Uri.parse('$_base/dashboard/smart-telemetry?userId=$userId'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final counters = (data['counters'] as Map?) ?? {};
      setState(() {
        counters.forEach((k, v) {
          final key = k.toString();
          if (key.startsWith('llm_provider:')) {
            _smartTelemetry[key] = (v is num ? v.toInt() : 0);
          }
        });
      });
    } catch (_) {}
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
    final trimmedName = widget.settings.userName.trim();
    if (trimmedName.isEmpty) {
      if (mounted) setState(() {
        _loadingSurveys = false;
        _surveyHistory = const [];
        _surveyInsights = const [];
        _surveyError = null;
      });
      return;
    }
    setState(() { _loadingSurveys = true; _surveyError = null; });
    final userName = Uri.encodeQueryComponent(trimmedName);
    final histFut = http.get(Uri.parse('$_base/survey-history?userName=$userName'))
        .timeout(const Duration(seconds: 8));
    final insFut = http.get(Uri.parse('$_base/survey-insights?userName=$userName'))
        .timeout(const Duration(seconds: 15));
    final results = await Future.wait([
      histFut.then<dynamic>((r) => r).catchError((e) => e),
      insFut.then<dynamic>((r) => r).catchError((e) => e),
    ]);
    if (!mounted) return;
    var failures = 0;
    if (results[0] is http.Response && (results[0] as http.Response).statusCode == 200) {
      try {
        final d = jsonDecode((results[0] as http.Response).body);
        _surveyHistory = List<Map<String, dynamic>>.from(d['surveys'] ?? []);
      } catch (_) { failures++; }
    } else { failures++; }
    if (results[1] is http.Response && (results[1] as http.Response).statusCode == 200) {
      try {
        final d = jsonDecode((results[1] as http.Response).body);
        _surveyInsights = List<String>.from(d['insights'] ?? []);
      } catch (_) { failures++; }
    } else { failures++; }
    setState(() {
      _loadingSurveys = false;
      _surveyError = failures == 2 ? 'שגיאת רשת — לא ניתן לטעון סקרים' : null;
    });
  }

  // ── Quick actions ─────────────────────────────────────────────────────────

  Future<void> _toggleAgent(Map<String, dynamic> agent) async {
    final id = agent['id']?.toString() ?? '';
    if (id.isEmpty || _togglingAgents.contains(id)) return;

    final idx = _agents.indexWhere((a) => a['id']?.toString() == id);
    final oldStatus = agent['status']?.toString() ?? 'active';
    final optimisticStatus = oldStatus == 'disabled' ? 'active' : 'disabled';

    // Optimistic update — immediately reflect change in UI
    setState(() {
      _togglingAgents.add(id);
      if (idx != -1) _agents[idx] = {..._agents[idx], 'status': optimisticStatus};
    });
    try {
      final res = await http.post(
        Uri.parse('$_base/progress-map/agents/$id/toggle'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      ).timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (res.statusCode != 200) {
        // Revert optimistic update on failure
        setState(() {
          if (idx != -1) _agents[idx] = {..._agents[idx], 'status': oldStatus};
        });
        _showSnack('שגיאה בשינוי סטטוס סוכן');
        return;
      }
      final d = jsonDecode(res.body);
      final serverStatus = d['status']?.toString() ?? optimisticStatus;
      // Sync with server-confirmed status
      setState(() {
        if (idx != -1) _agents[idx] = {..._agents[idx], 'status': serverStatus};
      });
      _showSnack(serverStatus == 'disabled' ? 'הסוכן הושבת' : 'הסוכן הופעל');
    } catch (_) {
      if (mounted) {
        // Revert optimistic update on network error
        setState(() {
          if (idx != -1) _agents[idx] = {..._agents[idx], 'status': oldStatus};
        });
        _showSnack('שגיאת רשת');
      }
    } finally {
      if (mounted) setState(() => _togglingAgents.remove(id));
    }
  }

  Future<void> _triggerE2eRun() async {
    if (_triggeringE2e) return;
    setState(() => _triggeringE2e = true);
    try {
      final res = await http
          .post(Uri.parse('$_base/e2e/trigger'), headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        _showSnack('בדיקות e2e יצאו לדרך — התוצאות יופיעו בטאב "מידע"');
        // Reset polling cadence so the new report shows up quickly.
        _pollNoChangeStreak = 0;
        _pollInterval = _kPollMin;
        _schedulePoll(immediate: true);
      } else {
        _showSnack('שגיאה בהפעלת בדיקות e2e');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת רשת');
    } finally {
      if (mounted) setState(() => _triggeringE2e = false);
    }
  }

  Future<void> _scanErrorsNow() async {
    if (_scanningErrors) return;
    setState(() => _scanningErrors = true);
    try {
      final res = await http
          .get(Uri.parse('$_base/scan/errors'))
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final findings = (d['findings'] is List) ? (d['findings'] as List).length : 0;
        _showSnack(findings == 0
            ? 'הסריקה הושלמה — לא נמצאו שגיאות'
            : 'הסריקה הושלמה — $findings ממצאים');
      } else if (res.statusCode == 429) {
        _showSnack('יותר מדי סריקות. נסה שוב בעוד דקה.');
      } else {
        _showSnack('סריקה נכשלה');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת רשת');
    } finally {
      if (mounted) setState(() => _scanningErrors = false);
    }
  }

  Future<void> _promoteProposalQuick(Map<String, dynamic> proposal) async {
    final status = proposal['status']?.toString() ?? _PS.proposal;
    final next = status == _PS.proposal
        ? 'activate'
        : status == _PS.draftPlan
            ? 'activate'
            : status == _PS.active
                ? 'confirm'
                : status == _PS.validation
                    ? 'confirm'
                    : null;
    if (next == null) {
      _showSnack('ההצעה כבר הושלמה');
      return;
    }
    await _runProposalAction(proposal, next);
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
      final res = await http.delete(Uri.parse('$_base/dashboard/backlog/$id'))
          .timeout(const Duration(seconds: 8));
      if (mounted && res.statusCode != 200 && res.statusCode != 204) {
        _showSnack('שגיאה במחיקה — טוען מחדש');
        await _loadBacklog();
      }
    } catch (_) {
      if (mounted) {
        _showSnack('שגיאת רשת — טוען מחדש');
        await _loadBacklog();
      }
    }
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
    return Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface.withOpacity(0.92),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          centerTitle: true,
          title: Text('מרכז שליטה',
              style: TextStyle(color: JC.blue400, fontSize: 18,
                  fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: JC.textSecondary, size: 20),
              onPressed: _loadAll,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: JC.border.withOpacity(0.5), width: 0.6),
                ),
              ),
              child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: JC.blue400,
            unselectedLabelColor: JC.textMuted,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: JC.blue500.withOpacity(0.15),
              border: Border.all(color: JC.blue400.withOpacity(0.45), width: 0.8),
              boxShadow: [
                BoxShadow(color: JC.blue500.withOpacity(0.2), blurRadius: 10, spreadRadius: 0),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 12.5),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 12.5),
            tabs: _visibleTabs.map((t) => _tabWithBadge(_tabLabel(t), t)).toList(),
          ),
        ),
          ),
        ),
        body: Column(
          children: [
            _buildAlertsBanner(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _visibleTabs.map(_buildTabBody).toList(),
              ),
            ),
          ],
        ),
    );
  }

  String _tabLabel(ControlCenterTab t) => switch (t) {
        ControlCenterTab.overview => 'סקירה ובריאות',
        ControlCenterTab.agents => 'סוכנים',
        ControlCenterTab.development => 'פיתוח',
        ControlCenterTab.testsSurveys => 'בדיקות וסקרים',
        ControlCenterTab.settings => 'הגדרות',
      };

  Widget _buildTabBody(ControlCenterTab t) => switch (t) {
        ControlCenterTab.overview => _buildOverviewTab(),
        ControlCenterTab.agents => _buildAgentsTab(),
        ControlCenterTab.development => _buildDevelopmentTab(),
        ControlCenterTab.testsSurveys => _buildTestsSurveysTab(),
        ControlCenterTab.settings => _buildSettingsTab(),
      };

  Widget _tabWithBadge(String label, ControlCenterTab tab) {
    final count = _tabBadges[tab] ?? 0;
    if (count <= 0) return Tab(text: label);
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 18),
            child: Text(
              count > 9 ? '9+' : count.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Heebo', fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsBanner() {
    final visible = _visibleAlerts;
    if (visible.isEmpty) return const SizedBox.shrink();
    final alert = visible.first;
    final color = alert.severity == 'urgent'
        ? const Color(0xFFEF4444)
        : alert.severity == 'warning'
            ? const Color(0xFFF59E0B)
            : JC.blue400;
    final icon = alert.severity == 'urgent'
        ? Icons.error_outline
        : alert.severity == 'warning'
            ? Icons.warning_amber_rounded
            : Icons.notifications_active_outlined;
    final actionLabel = switch (alert.actionHint) {
      'rerun_e2e' => 'הרץ שוב',
      'open_e2e_report' => 'פתח דוח',
      'promote_proposal' => 'קדם',
      'start_survey' => 'פתח סקר',
      'open_chat' => 'פתח שיחה',
      _ => 'פתח',
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _runAlertAction(alert),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(alert.title,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: color, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(alert.message,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.35)),
                  if (visible.length > 1) ...[
                    const SizedBox(height: 2),
                    Text('עוד ${visible.length - 1} התראות',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: () => _runAlertAction(alert),
              style: TextButton.styleFrom(
                minimumSize: const Size(40, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: color,
              ),
              child: Text(actionLabel, style: const TextStyle(fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'הסתר',
              onPressed: () => _dismissAlert(alert.id),
              icon: Icon(Icons.close_rounded, size: 16, color: JC.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ]),
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
        _buildCommandBar(),
        const SizedBox(height: 14),
        _buildStatusBar(),
        const SizedBox(height: 10),
        _buildOverviewQuickActions(),
        const SizedBox(height: 14),
        _buildMetrics(),
        const SizedBox(height: 14),
        _sectionTitle('💡 תובנות פרואקטיביות'),
        const SizedBox(height: 8),
        _buildInsightsCard(),
        const SizedBox(height: 14),
        _sectionTitle('📊 שימוש מודלים (מהשרת)'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: _buildProviderBreakdown(),
        ),
      ]);

  Widget _buildOverviewQuickActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _triggeringE2e ? null : _triggerE2eRun,
            icon: _triggeringE2e
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: JC.blue400))
                : const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('הרץ e2e עכשיו', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: JC.blue400,
              side: BorderSide(color: JC.blue400, width: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _scanningErrors ? null : _scanErrorsNow,
            icon: _scanningErrors
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)))
                : const Icon(Icons.bug_report_outlined, size: 18),
            label: const Text('סרוק שגיאות', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF59E0B),
              side: const BorderSide(color: Color(0xFFF59E0B), width: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ── NL command bar (POST /progress-map/command) ───────────────────────────
  Widget _buildCommandBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [JC.blue500.withValues(alpha: 0.16), JC.blue500.withValues(alpha: 0.04)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JC.blue400.withValues(alpha: 0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.bolt_rounded, size: 18, color: JC.blue400),
            const SizedBox(width: 6),
            Text('שורת פקודה', style: TextStyle(color: JC.blue400, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cmdCtrl,
                textDirection: TextDirection.rtl,
                onSubmitted: (_) => _runCommand(),
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'למשל: כבה את סוכן החדשות',
                  hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12.5),
                  filled: true,
                  fillColor: JC.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: JC.border, width: 0.8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: JC.border, width: 0.8)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: JC.blue400, width: 1.2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _runningCmd ? null : _runCommand,
                style: ElevatedButton.styleFrom(
                  backgroundColor: JC.blue500,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: _runningCmd
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('הפעל', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ]),
          if (_cmdAnswer != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: JC.border, width: 0.8)),
              child: Text(_cmdAnswer!, textAlign: TextAlign.right, style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12.5, height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runCommand() async {
    final text = _cmdCtrl.text.trim();
    if (text.isEmpty || _runningCmd) return;
    setState(() { _runningCmd = true; _cmdAnswer = null; });
    try {
      final res = await http.post(
        Uri.parse('$_base/progress-map/command'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      ).timeout(const Duration(seconds: 20));
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final action = d['action']?.toString() ?? 'answer';
      final answer = d['answer']?.toString() ?? '';
      final params = Map<String, dynamic>.from(d['params'] ?? const {});
      if (!mounted) return;
      setState(() => _cmdAnswer = answer.isEmpty ? null : answer);
      _execCommandAction(action, params);
      if (action != 'answer') _cmdCtrl.clear();
    } catch (_) {
      if (mounted) setState(() => _cmdAnswer = 'שגיאה בעיבוד הפקודה.');
    } finally {
      if (mounted) setState(() => _runningCmd = false);
    }
  }

  void _execCommandAction(String action, Map<String, dynamic> params) {
    switch (action) {
      case 'navigate':
        final tab = _serverTabToCc(params['tab']?.toString());
        if (tab != null) _goToTab(tab);
        break;
      case 'run_scan':
        _goToTab(ControlCenterTab.overview);
        _scanErrorsNow();
        break;
      case 'run_e2e':
        _triggerE2eRun();
        break;
      case 'toggle_agent':
        _loadAgents();
        break;
    }
  }

  // Map the server's tab ids (overview/agents/analytics/dev/qa/settings) onto the
  // mobile control-center tabs. The web has a dedicated analytics tab; on mobile
  // those charts live under overview.
  ControlCenterTab? _serverTabToCc(String? id) {
    switch (id) {
      case 'overview':
      case 'analytics':
        return ControlCenterTab.overview;
      case 'agents':
        return ControlCenterTab.agents;
      case 'dev':
        return ControlCenterTab.development;
      case 'qa':
        return ControlCenterTab.testsSurveys;
      case 'settings':
        return ControlCenterTab.settings;
    }
    return null;
  }

  // ── Proactive insights (POST /dashboard/analytics/insights) ────────────────
  Future<void> _loadInsights() async {
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/analytics/insights'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'range': '7d'}),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode != 200) { setState(() => _loadingInsights = false); return; }
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (d['insights'] as List?) ?? const [];
      setState(() {
        _insights = list.map((e) => Map<String, dynamic>.from(e as Map)).take(4).toList();
        _insightsSource = d['cached'] == true
            ? 'מהמטמון'
            : (d['source'] == 'ai' ? 'נותח ע״י AI' : 'חישוב ישיר');
        _loadingInsights = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingInsights = false);
    }
  }

  Widget _buildInsightsCard() {
    if (_loadingInsights && _insights.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2),
      );
    }
    if (_insights.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
        child: Text('אין מספיק נתונים לתובנות עדיין', textAlign: TextAlign.right, style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12.5)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._insights.map((t) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t['icon']?.toString() ?? '💡', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['title']?.toString() ?? '', textAlign: TextAlign.right, style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text(t['detail']?.toString() ?? '', textAlign: TextAlign.right, style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.5)),
                  ]),
                ),
              ]),
            )),
        if (_insightsSource.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('· $_insightsSource', style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10.5)),
          ),
      ],
    );
  }

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

  // ── בדיקות וסקרים: E2E reports (live) + read-only survey summary ───────────
  Widget _buildTestsSurveysTab() {
    final hasUserName = widget.settings.userName.trim().isNotEmpty;
    return _tabListView([
      _sectionTitle('⚡ פעולות מהירות'),
      const SizedBox(height: 8),
      _buildOverviewQuickActions(),
      const SizedBox(height: 18),
      _sectionTitle('🧪 דוחות בדיקות E2E'),
      const SizedBox(height: 8),
      E2eReportsPanel(settings: widget.settings),
      const SizedBox(height: 24),
      _sectionTitle('📋 סקרים (לקריאה בלבד)'),
      const SizedBox(height: 8),
      if (!hasUserName)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JC.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 0.8),
          ),
          child: Text(
            'צריך להגדיר שם משתמש בהגדרות כדי לצפות בסיכום הסקרים.',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13),
          ),
        )
      else ...[
        if (_surveyError != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JC.cancelRed.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: JC.cancelRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_surveyError!,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13)),
              ),
              TextButton(onPressed: _loadSurveys, child: const Text('נסה שוב', style: TextStyle(fontFamily: 'Heebo'))),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        _buildSurveyInsightsCard(),
        const SizedBox(height: 18),
        _sectionTitle('📜 היסטוריית סקרים'),
        const SizedBox(height: 8),
        _buildSurveyHistory(),
      ],
    ]);
  }

  // ── הגדרות: role switch (dev) + launcher to the full settings screen ───────
  Widget _buildSettingsTab() => _tabListView([
        _sectionTitle('🛡 רמת גישה'),
        const SizedBox(height: 8),
        _buildRoleSwitchCard(),
        const SizedBox(height: 24),
        _sectionTitle('⚙️ הגדרות עוזר'),
        const SizedBox(height: 8),
        _buildSettingsLauncher(),
      ]);

  // Dedicated, always-visible role toggle (user ⇄ admin). During development this
  // lets you flip access level without editing the DB. Persists to /user-profile
  // (preferences.role) and rebuilds the visible tab set immediately.
  Widget _buildRoleSwitchCard() {
    final isAdmin = _isAdmin;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAdmin
                ? 'אדמין — רואה את כל הכרטיסיות (סוכנים, אנליטיקה, פיתוח, בדיקות).'
                : 'משתמש — רואה תצוגה אישית (סקירה + הגדרות).',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _roleChip('👤 משתמש', !isAdmin, () => _setRole('user')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _roleChip('🛡 אדמין', isAdmin, () => _setRole('admin')),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _roleChip(String label, bool active, VoidCallback onTap) {
    return Material(
      color: active ? JC.blue500 : JC.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _settingRole ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? JC.blue500 : JC.border, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? JC.onAccent : JC.textSecondary,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setRole(String role) async {
    if (_settingRole || role == widget.settings.role) return;
    setState(() => _settingRole = true);
    final oldVisible = _visibleTabs;
    final oldTab = oldVisible[_tabController.index.clamp(0, oldVisible.length - 1).toInt()];
    try {
      final res = await http
          .post(
            Uri.parse('$_base/user-profile'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'role': role}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      widget.settings.role = role;
      await widget.settings.save();
      if (!mounted) return;
      // Rebuild the TabController for the new visible tab set, preserving the tab.
      _tabController.dispose();
      final newIdx = _visibleTabs.indexOf(oldTab);
      _tabController = TabController(
        length: _visibleTabs.length,
        vsync: this,
        initialIndex: newIdx >= 0 ? newIdx : 0,
      );
      setState(() => _settingRole = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(role == 'admin' ? 'הופעל מצב אדמין 🛡' : 'הוחזר למצב משתמש 👤',
            style: const TextStyle(fontFamily: 'Heebo')),
        duration: const Duration(seconds: 2),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _settingRole = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('שגיאה בשינוי רמת גישה', style: TextStyle(fontFamily: 'Heebo')),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Widget _buildSettingsLauncher() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'שם העוזר, אישיות, מצב קול, TTS, מודל מקומי, כתובת שרת ועוד.',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openFullSettings,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('פתח הגדרות מלאות', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: JC.blue500,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFullSettings() async {
    await Navigator.of(context).push(
      SlideFadeRoute(
        page: SettingsScreen(
          settings: widget.settings,
          onSave: (updated) async {
            await updated.save();
          },
        ),
      ),
    );
  }

  Widget _buildSurveyInsightsCard() {
    if (_loadingSurveys && _surveyInsights.isEmpty && _surveyHistory.isEmpty) {
      return Padding(
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
        child: Text(
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
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _surveyInsights
            .map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $s',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13, height: 1.5)),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildSurveyHistory() {
    if (_loadingSurveys && _surveyHistory.isEmpty && _surveyInsights.isEmpty) {
      return const SizedBox.shrink();
    }
    if (_loadingSurveys && _surveyHistory.isEmpty) {
      return Padding(
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
        child: Text(
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_relativeDate(created),
                  textAlign: TextAlign.right,
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
              const SizedBox(height: 4),
              Text(summary,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13, height: 1.5)),
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
        border: Border.all(color: statusColor.withOpacity(0.35), width: 0.9),
        boxShadow: [
          BoxShadow(color: statusColor.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 3)),
          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2)),
        ],
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
                style: TextStyle(color: JC.textSecondary, fontSize: 13, fontFamily: 'Heebo')),
          ),
          if (ok == true)
            Text('${_latencyMs}ms',
                style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'))
          else if (ok == false)
            GestureDetector(
              onTap: _loadAll,
              child: Text('נסה עכשיו',
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
              boxShadow: [
                BoxShadow(color: JC.blue500.withOpacity(0.07), blurRadius: 14, offset: const Offset(0, 3)),
                BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(
                    color: JC.textSecondary, fontSize: 11,
                    fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  _loadingStats ? '…' : (num?.toString() ?? '—'),
                  style: TextStyle(
                      color: JC.blue400, fontSize: 22,
                      fontWeight: FontWeight.w700, height: 1.1),
                ),
                Text(sub, style: TextStyle(
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
                  style: TextStyle(color: JC.textPrimary,
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


  /// Show a per-provider usage breakdown sourced from smart_telemetry counters
  /// where event_name follows the pattern "llm_provider:<name>".
  Widget _buildProviderBreakdown() {
    const meta = <String, ({IconData icon, String label, Color color})>{
      'groq':       (icon: Icons.bolt,                label: 'Groq',       color: Color(0xFFF97316)),
      'deepseek':   (icon: Icons.psychology_outlined, label: 'DeepSeek',   color: Color(0xFF6366F1)),
      'openrouter': (icon: Icons.alt_route,           label: 'OpenRouter', color: Color(0xFF14B8A6)),
      'gemini':     (icon: Icons.auto_awesome,        label: 'Gemini',     color: Color(0xFF3B82F6)),
      'ollama':     (icon: Icons.computer,            label: 'מקומי',      color: Color(0xFF22C55E)),
    };
    final counts = <String, int>{};
    int total = 0;
    _smartTelemetry.forEach((k, v) {
      if (k.startsWith('llm_provider:')) {
        final name = k.substring('llm_provider:'.length);
        counts[name] = (counts[name] ?? 0) + v;
        total += v;
      }
    });
    if (total == 0) {
      return Text('פילוח מודלים: עדיין אין נתונים',
          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11));
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('פילוח לפי מודל ($total תשובות)',
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        ...entries.map((e) {
          final m = meta[e.key] ??
              (icon: Icons.smart_toy_outlined, label: e.key, color: JC.textMuted);
          final pct = (e.value / total * 100).toStringAsFixed(0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Text('${e.value} ($pct%)',
                    style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: e.value / total,
                      minHeight: 5,
                      backgroundColor: m.color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation(m.color),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(m.icon, size: 12, color: m.color),
                const SizedBox(width: 3),
                Text(m.label,
                    style: TextStyle(color: m.color, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }),
      ],
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
      return Padding(padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2)));
    }
    if (_done.isEmpty && _building.isEmpty && _planned.isEmpty && _serverOk != true) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, color: JC.textMuted, size: 28),
            const SizedBox(height: 8),
            Text('לא ניתן לטעון נתונים — השרת לא זמין',
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
                child: Text('טעון מחדש',
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
          Padding(
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
                crossAxisAlignment: CrossAxisAlignment.end,
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
                        style: TextStyle(
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
                style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
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
                  style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
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
          Padding(
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
            child: Column(children: [
              Icon(Icons.auto_awesome_outlined, color: JC.textMuted, size: 32),
              SizedBox(height: 8),
              Text('לחץ "צור הצעות" כדי ש-Jarvis ינתח את הפרויקט',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
                  textAlign: TextAlign.center),
            ]),
          )
        else if (filtered.isEmpty)
          Padding(
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
                          style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
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
                              child: Icon(Icons.info_outline_rounded, color: JC.textMuted, size: 16),
                            ),
                            const SizedBox(width: 6),
                            Text('הסבר ציון',
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
                            style: TextStyle(
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
                              style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11)),
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
                                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12))),
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
                            style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Badges + activate button
                      if (!isDone && p['requiresPrivacy'] == true)
                        Align(
                          alignment: Alignment.centerRight,
                          child: const Text('נדרש אישור פרטיות', style: TextStyle(color: Color(0xFFF59E0B), fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      if (!isDone && p['requiresPrivacy'] == true) const SizedBox(height: 6),
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
                                    ? SizedBox(
                                        width: 13, height: 13,
                                        child: CircularProgressIndicator(strokeWidth: 1.8, color: JC.blue400),
                                      )
                                    : Text(isActive ? '⏸ חזרה לתכנון' : isDraftPlan ? '⚡ התחל ביצוע' : isValidation ? '⚡ חזרה לביצוע' : '🧭 צור תכנית',
                                        style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
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
                            child: Padding(
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
                        Text('🤖 ג׳רביס:',
                            style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        const Spacer(),
                        if (widget.onSwitchToChat != null)
                          GestureDetector(
                            onTap: () => _switchToChatWithProposal(p),
                            child: Text('המשך בצ׳אט ←',
                                style: TextStyle(color: JC.blue400, fontFamily: 'Heebo',
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(response,
                        style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
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
          Row(
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
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
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
                              style: TextStyle(color: JC.blue400,
                                  fontFamily: 'Heebo', fontSize: 12)),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    Text('📋 פרומפט מוכן ל-Claude Code',
                        style: TextStyle(color: JC.textSecondary,
                            fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  Divider(color: JC.border, height: 1),
                  const SizedBox(height: 8),
                  SelectableText(
                    _generatedPrompt!,
                    style: TextStyle(color: JC.textSecondary,
                        fontFamily: 'Heebo', fontSize: 12, height: 1.6),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _addItemWithText(_promptCtrl.text.trim()),
                    child: Text('+ שמור כפריט ב-Backlog',
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
              style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 13),
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
          Padding(padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: JC.blue400, strokeWidth: 2))
        else if (_items.isEmpty)
          Padding(
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
                      style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
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
      return Padding(
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
        child: Text(
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
              style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          ..._agents.map(_buildAgentTile),
        ],
      ),
    );
  }

  Widget _buildAgentTile(Map<String, dynamic> agent) {
    final id = (agent['id'] ?? '').toString();
    final nameHe = (agent['nameHe'] ?? agent['name'] ?? agent['id'] ?? '').toString();
    final role = (agent['role'] ?? '').toString();
    final risk = (agent['risk'] ?? 'low').toString();
    final mode = (agent['mode'] ?? '').toString();
    final autonomy = (agent['autonomy'] ?? 0) as num;
    final status = (agent['status'] ?? 'active').toString();
    final isDisabled = status == 'disabled';
    final isToggling = _togglingAgents.contains(id);

    // P1: Metrics from server
    final metrics = agent['metrics'] as Map<String, dynamic>?;
    final avgMs = metrics?['avgMs'] as num?;
    final callCount = (metrics?['count'] as num?)?.toInt() ?? 0;
    final healthScore = (agent['healthScore'] as num?)?.toInt();

    Color _healthColor(int? score) {
      if (score == null) return JC.textMuted;
      if (score >= 80) return const Color(0xFF22C55E);
      if (score >= 50) return const Color(0xFFF59E0B);
      return const Color(0xFFEF4444);
    }

    return Opacity(
      opacity: isDisabled ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: () => _showAgentDetails(agent),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: JC.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDisabled ? JC.textMuted.withValues(alpha: 0.4) : JC.border,
              width: 0.7,
            ),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDisabled
                      ? JC.textMuted
                      : status == 'active'
                          ? const Color(0xFF22C55E)
                          : JC.blue400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(nameHe,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: isDisabled ? TextDecoration.lineThrough : null,
                        )),
                    if (role.isNotEmpty)
                      Text(role,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    // P1: Show live metrics below name
                    if (callCount > 0 || avgMs != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (avgMs != null)
                              Text('${avgMs.toInt()}ms',
                                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                            if (avgMs != null && callCount > 0)
                              Text(' · ', style: TextStyle(color: JC.textMuted, fontSize: 10)),
                            if (callCount > 0)
                              Text('$callCount קריאות',
                                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 4,
                    children: [
                      _badge(_riskLabel(risk), _riskColor(risk)),
                      if (mode.isNotEmpty) _badge(mode, JC.blue400),
                      _badge('${autonomy.toInt()}%', JC.textMuted),
                    ],
                  ),
                  // P2: Health score badge
                  if (healthScore != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: _badge('❤️ $healthScore', _healthColor(healthScore)),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 28, height: 28,
                child: isToggling
                    ? Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2, color: JC.blue400))
                    : IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: isDisabled ? 'הפעל סוכן' : 'השבת סוכן',
                        onPressed: () => _toggleAgent(agent),
                        icon: Icon(
                          isDisabled ? Icons.play_circle_outline : Icons.pause_circle_outline,
                          size: 20,
                          color: isDisabled ? const Color(0xFF22C55E) : JC.textMuted,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAgentDetails(Map<String, dynamic> agent) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JC.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => AgentDetailSheet(agent: agent, base: _base),
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
              SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: JC.blue400))
            else if (icon != null)
              Icon(icon, size: 14, color: JC.blue400),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
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
        hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: fill ?? JC.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: JC.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: JC.border, width: 0.8)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: JC.blue400)),
      );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      Expanded(child: Divider(color: JC.border, height: 1)),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(
          color: JC.blue400, fontSize: 11, fontWeight: FontWeight.w700,
          fontFamily: 'Heebo', letterSpacing: 0.8)),
    ]),
  );
}
