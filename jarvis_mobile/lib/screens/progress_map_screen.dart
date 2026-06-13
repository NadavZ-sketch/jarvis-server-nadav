import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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
///   overview     → סקירה
///   agents       → סוכנים
///   analytics    → אנליטיקה
///   development  → פיתוח / Roadmap
///   testsSurveys → בדיקות וסקרים (E2E reports + read-only survey summary)
///   settings     → הגדרות
enum ControlCenterTab { overview, agents, analytics, development, testsSurveys, settings }

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

  // ── Control-centre gold palette (matches the web progress-map.html) ────────
  static const Color _kGold    = Color(0xFFC9A84C);
  static const Color _kGoldDim = Color(0xFF8B7035);

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
  String _agentSearch = '';

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

  // Smart survey
  List<Map<String, dynamic>> _smartSurveyQuestions = [];
  final Map<String, String> _smartSurveyResponses = {};
  bool _showSmartSurvey = false;
  bool _loadingSmartSurvey = false;
  bool _submittingSmartSurvey = false;

  // Conversation insights + feedback pipeline (dev tab)
  Map<String, dynamic> _convInsights = {};
  List<Map<String, dynamic>> _feedbackConcerns = [];
  bool _loadingConvInsights = false;

  // Smart proposals (AI-generated from survey + usage data)
  List<Map<String, dynamic>> _smartProposals = [];
  bool _loadingSmartProposals = false;
  bool _smartProposalsGenerated = false;
  final Set<String> _dismissedSmartProposals = {};
  final Map<String, TextEditingController> _proposalFeedbackCtrl = {};

  // Feature description generation
  bool _generatingFeatureDescriptions = false;

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

  @override
  void didUpdateWidget(covariant ProgressMapScreen old) {
    super.didUpdateWidget(old);
    // The parent (main_shell) may rebuild us with new settings carrying a
    // different role — e.g. the user flips user⇄admin from the main settings
    // screen. The visible-tab set then changes (2⇄5) but our TabController is
    // built once in initState. A TabController whose length ≠ the number of
    // TabBar tabs / TabBarView children silently collapses the layout in
    // release builds (asserts off) — the symptom is an empty tab strip and a
    // "BOTTOM OVERFLOWED BY 99899 PIXELS" banner in admin mode. Keep them in sync.
    if (_tabController.length != _visibleTabs.length) {
      final keepIdx = _tabController.index.clamp(0, _visibleTabs.length - 1);
      _tabController.dispose();
      _tabController = TabController(
        length: _visibleTabs.length,
        vsync: this,
        initialIndex: keepIdx,
      );
    }
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
      if (!mounted) return;
      // Capture the current tab from the OLD visible set before flipping role.
      final oldVisible = _visibleTabs;
      final oldTab = oldVisible[_tabController.index.clamp(0, oldVisible.length - 1).toInt()];
      // Update role and rebuild TabController atomically — same race-condition
      // guard as _setRole: no await between role assignment and setState.
      widget.settings.role = role;
      _tabController.dispose();
      final newIdx = _visibleTabs.indexOf(oldTab); // _visibleTabs now reflects new role
      _tabController = TabController(
        length: _visibleTabs.length,
        vsync: this,
        initialIndex: newIdx >= 0 ? newIdx : 0,
      );
      widget.settings.save(); // fire-and-forget
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
    for (final ctrl in _proposalFeedbackCtrl.values) {
      ctrl.dispose();
    }
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
      // Legacy server keys fold into the nearest equivalent tab.
      final tab = switch (key) {
        'insights' => ControlCenterTab.analytics,
        'surveys'  => ControlCenterTab.testsSurveys,
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
      _loadConvInsights(),
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

  Future<void> _loadConvInsights() async {
    setState(() => _loadingConvInsights = true);
    try {
      final resFut = http.get(Uri.parse('$_base/dashboard/conversation-insights'))
          .timeout(const Duration(seconds: 10));
      final impactFut = http.get(Uri.parse('$_base/survey-impact'))
          .timeout(const Duration(seconds: 10));
      final results = await Future.wait([
        resFut.then<dynamic>((r) => r).catchError((e) => e),
        impactFut.then<dynamic>((r) => r).catchError((e) => e),
      ]);
      if (!mounted) return;
      if (results[0] is http.Response && (results[0] as http.Response).statusCode == 200) {
        try {
          _convInsights = Map<String, dynamic>.from(
              jsonDecode((results[0] as http.Response).body));
        } catch (_) {}
      }
      if (results[1] is http.Response && (results[1] as http.Response).statusCode == 200) {
        try {
          final d = jsonDecode((results[1] as http.Response).body);
          _feedbackConcerns = List<Map<String, dynamic>>.from(d['concerns'] ?? []);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingConvInsights = false);
  }

  Future<void> _loadSmartProposals() async {
    if (_loadingSmartProposals) return;
    if (mounted) setState(() => _loadingSmartProposals = true);
    try {
      final userName = widget.settings.userName;
      final res = await http.post(
        Uri.parse('$_base/dashboard/smart-proposals/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userName': userName}),
      ).timeout(const Duration(seconds: 35));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final all = List<Map<String, dynamic>>.from(d['proposals'] ?? []);
        setState(() {
          _smartProposals = all.where((p) => !_dismissedSmartProposals.contains(p['id']?.toString())).toList();
          _smartProposalsGenerated = true;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingSmartProposals = false);
    }
  }

  Future<void> _approveSmartProposal(Map<String, dynamic> p, {String? feedback}) async {
    final id = p['id']?.toString() ?? '';
    try {
      final body = {
        'title': p['title'] ?? '',
        'plan': [p['description'] ?? '', if (feedback != null && feedback.isNotEmpty) 'פידבק: $feedback'].join('\n\n'),
        'priority': (p['priority_score'] ?? 5) >= 8 ? 'high' : (p['priority_score'] ?? 5) >= 5 ? 'medium' : 'low',
        'category': p['category'] ?? 'improvement',
      };
      final res = await http.post(
        Uri.parse('$_base/dashboard/backlog'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 201) {
        setState(() {
          _dismissedSmartProposals.add(id);
          _smartProposals.removeWhere((x) => x['id']?.toString() == id);
          _proposalFeedbackCtrl[id]?.dispose();
          _proposalFeedbackCtrl.remove(id);
        });
        await _loadBacklog();
      }
    } catch (_) {}
  }

  void _dismissSmartProposal(String id) {
    setState(() {
      _dismissedSmartProposals.add(id);
      _smartProposals.removeWhere((p) => p['id']?.toString() == id);
      _proposalFeedbackCtrl[id]?.dispose();
      _proposalFeedbackCtrl.remove(id);
    });
  }

  // Build the dev prompt string for a smart proposal (title + rationale + description)
  String _smartProposalDevPrompt(Map<String, dynamic> p) {
    final title       = p['title']?.toString() ?? '';
    final description = p['description']?.toString() ?? '';
    final rationale   = p['rationale']?.toString() ?? '';
    final category    = p['category']?.toString() ?? 'improvement';
    final catHe = switch (category) {
      'bug_fix'     => 'תיקון באג',
      'ux'          => 'שיפור חוויית משתמש',
      'performance' => 'שיפור ביצועים',
      'feature'     => 'פיצ\'ר חדש',
      _             => 'שיפור',
    };
    return '''📋 הצעת פיתוח: $title
סוג: $catHe

תיאור:
$description
${rationale.isNotEmpty ? '\nרציונל:\n$rationale' : ''}

בקשה לקלוד:
1. תכנן את השלבים לממש את זה ב-Jarvis (Flutter + Node.js)
2. פרט אילו קבצים לשנות/ליצור
3. הצע קוד לדוגמה לחלקים המורכבים
4. מה לבדוק לאחר הפיתוח''';
  }

  Future<void> _sendProposalAsTask(Map<String, dynamic> p, {String? refinedPrompt}) async {
    final defaultTitle = p['title']?.toString() ?? 'הצעת פיתוח';
    final prompt = refinedPrompt ?? _smartProposalDevPrompt(p);
    final titleCtrl = TextEditingController(text: defaultTitle);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('שלח כמשימה', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('כותרת המשימה:', style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: titleCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: JC.border, width: 0.8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: JC.border, width: 0.8)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _kGold, width: 1.0)),
                ),
              ),
              const SizedBox(height: 10),
              Text('הפרומפט יישמר כתוכן המשימה בקטגוריה "ג\'רביס".',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('ביטול', style: TextStyle(fontFamily: 'Heebo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('שלח', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final taskTitle = titleCtrl.text.trim().isEmpty ? defaultTitle : titleCtrl.text.trim();
    try {
      final res = await http.post(
        Uri.parse('$_base/tasks'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'content': '$taskTitle\n\n$prompt', 'category': 'ג\'רביס'}),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.statusCode == 200 || res.statusCode == 201 ? '✅ המשימה נוצרה בהצלחה' : '⚠️ שגיאה ביצירת המשימה',
              style: const TextStyle(fontFamily: 'Heebo')),
          backgroundColor: res.statusCode == 200 || res.statusCode == 201 ? _kGold : const Color(0xFFEF4444),
        ));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('שגיאת חיבור', style: TextStyle(fontFamily: 'Heebo'))));
    }
  }

  // Open the 2-step clarify sheet for a smart proposal.
  // mode = 'claude' | 'task'
  void _showProposalClarifyFlow(Map<String, dynamic> p, {required String mode}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProposalClarifySheet(
        proposal: p,
        mode: mode,
        base: _base,
        onSendToClaud: (prompt) => _showSendToClaudeMenu(context, prompt, title: p['title']?.toString() ?? ''),
        onSendAsTask: _sendProposalAsTask,
      ),
    );
  }

  // ── Feature CRUD ─────────────────────────────────────────────────────────

  Future<bool> _patchFeature({
    required String name,
    required String oldStatus,
    required String newStatus,
    String? desc,
  }) async {
    try {
      final res = await http.patch(
        Uri.parse('$_base/dashboard/features'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'oldStatus': oldStatus, 'newStatus': newStatus, if (desc != null) 'desc': desc}),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) { await _loadFeatures(); return true; }
    } catch (_) {}
    return false;
  }

  Future<bool> _addFeature({required String name, required String desc, required String status}) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/features'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'desc': desc, 'status': status}),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) { await _loadFeatures(); return true; }
      if (res.statusCode == 409) return false; // duplicate
    } catch (_) {}
    return false;
  }

  Future<bool> _deleteFeature({required String name, required String status}) async {
    try {
      final res = await http.delete(
        Uri.parse('$_base/dashboard/features'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'status': status}),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) { await _loadFeatures(); return true; }
    } catch (_) {}
    return false;
  }

  // Returns AI-suggested description for a single feature (used inside the sheet)
  Future<String?> _suggestFeatureDescription(String name, String status) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/dashboard/features/suggest-description'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'status': status}),
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        return d['description']?.toString();
      }
    } catch (_) {}
    return null;
  }

  // Batch-generates descriptions for all features that have no description yet
  Future<void> _generateFeatureDescriptions() async {
    if (_generatingFeatureDescriptions) return;
    setState(() => _generatingFeatureDescriptions = true);
    try {
      final all = [
        ..._done.map((f) => {...f, 'status': 'done'}),
        ..._building.map((f) => {...f, 'status': 'building'}),
        ..._planned.map((f) => {...f, 'status': 'planned'}),
      ];
      final res = await http.post(
        Uri.parse('$_base/dashboard/features/generate-descriptions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'features': all}),
      ).timeout(const Duration(seconds: 40));
      if (res.statusCode != 200 || !mounted) return;

      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final descriptions = List<Map<String, dynamic>>.from(d['descriptions'] ?? []);
      if (descriptions.isEmpty) return;

      // Apply descriptions to local lists and save each to server
      final byName = {for (final d in descriptions) d['name'].toString(): d['description'].toString()};
      for (final list in [_done, _building, _planned]) {
        for (final f in list) {
          final name = f['name']?.toString() ?? '';
          if ((f['desc'] ?? '').toString().isEmpty && byName.containsKey(name)) {
            final status = list == _done ? 'done' : list == _building ? 'building' : 'planned';
            f['desc'] = byName[name];
            // Persist to server (fire-and-forget per feature)
            http.patch(
              Uri.parse('$_base/dashboard/features'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'name': name, 'oldStatus': status, 'newStatus': status, 'desc': byName[name]}),
            ).timeout(const Duration(seconds: 8)).catchError((_) => http.Response('', 500));
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {} finally {
      if (mounted) setState(() => _generatingFeatureDescriptions = false);
    }
  }


  // ── "Send to Claude" ──────────────────────────────────────────────────────

  void _showSendToClaudeMenu(BuildContext ctx, String prompt, {String title = ''}) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _SendToClaudeSheet(prompt: prompt, title: title, base: _base),
    );
  }

  String _featureToPrompt(Map<String, dynamic> f, String status) {
    final name = f['name']?.toString() ?? '';
    final desc = f['desc']?.toString() ?? '';
    final statusHe = switch (status) {
      'done'     => 'הושלם',
      'building' => 'בבנייה',
      _          => 'מתוכנן',
    };
    return '''פיצ'ר ב-Jarvis: $name
סטטוס: $statusHe
${desc.isNotEmpty ? 'תיאור: $desc' : ''}

אנא עזור לי לתכנן את הפיתוח של הפיצ'ר הזה:
1. מה בדיוק צריך לממש
2. אילו קבצים/מודולים לשנות
3. סדר עבודה מומלץ עם אבני דרך
4. מה עלול להיות מסובך ואיך להתמודד''';
  }

  String _proposalToPrompt(Map<String, dynamic> p) {
    final title = p['title']?.toString() ?? '';
    final plan  = p['plan']?.toString()  ?? '';
    final prio  = p['priority']?.toString() ?? 'medium';
    return '''פריט Backlog ב-Jarvis: $title
עדיפות: $prio
תוכנית: $plan

אנא עזור לי לממש את הפריט הזה:
1. תוכנית עבודה מפורטת עם שלבים
2. קוד לדוגמה לחלקים המורכבים
3. מה לבדוק לאחר הפיתוח''';
  }

  // ── Add feature dialog ────────────────────────────────────────────────────

  void _showAddFeatureDialog(BuildContext ctx) {
    final nameCtrl   = TextEditingController();
    final descCtrl   = TextEditingController();
    String selStatus = 'planned';
    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setSt) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('הוסף יכולת חדשה', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                decoration: _inputDeco('שם הפיצ\'ר'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                maxLines: 2,
                decoration: _inputDeco('תיאור קצר (אופציונלי)'),
              ),
              const SizedBox(height: 12),
              // Status selector
              Row(
                children: [
                  for (final (s, label) in [('planned', '📋 מתוכנן'), ('building', '🔨 בבנייה'), ('done', '✅ הושלם')])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onTap: () => setSt(() => selStatus = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            decoration: BoxDecoration(
                              color: selStatus == s ? _kGold.withOpacity(0.15) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: selStatus == s ? _kGold : JC.border, width: selStatus == s ? 1.2 : 0.6),
                            ),
                            child: Text(label, textAlign: TextAlign.center,
                                style: TextStyle(color: selStatus == s ? _kGold : JC.textMuted, fontFamily: 'Heebo', fontSize: 10.5)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('ביטול', style: TextStyle(fontFamily: 'Heebo'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                Navigator.pop(dCtx);
                final ok = await _addFeature(name: n, desc: descCtrl.text.trim(), status: selStatus);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'הפיצ\'ר נוסף ✓' : 'שם כבר קיים', style: const TextStyle(fontFamily: 'Heebo')),
                    backgroundColor: ok ? _kGold : const Color(0xFFEF4444),
                  ));
                }
              },
              child: const Text('הוסף', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      )),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: JC.border, width: 0.8)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: JC.border, width: 0.8)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _kGold, width: 1.0)),
  );

  // ── Feature detail bottom sheet ───────────────────────────────────────────

  void _showFeatureDetailSheet(BuildContext ctx, Map<String, dynamic> feature, String currentStatus) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeatureDetailSheet(
        feature: feature,
        currentStatus: currentStatus,
        base: _base,
        onPatch: _patchFeature,
        onDelete: _deleteFeature,
        onSendToClaud: (prompt) => _showSendToClaudeMenu(ctx, prompt, title: feature['name']?.toString() ?? ''),
        featureToPrompt: _featureToPrompt,
        onSuggestDesc: _suggestFeatureDescription,
      ),
    );
  }

  Future<void> _loadSmartSurvey() async {
    setState(() { _loadingSmartSurvey = true; _showSmartSurvey = false; });
    try {
      final userName = widget.settings.userName.trim();
      final uri = Uri.parse('$_base/survey-smart-check')
          .replace(queryParameters: userName.isNotEmpty ? {'userName': userName} : null);
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final questions = List<Map<String, dynamic>>.from(d['survey'] ?? []);
        if (questions.isNotEmpty) {
          setState(() {
            _smartSurveyQuestions = questions;
            _smartSurveyResponses.clear();
            _showSmartSurvey = true;
          });
        } else {
          _showSnack('אין שאלות סקר כרגע');
        }
      } else {
        _showSnack('שגיאה בטעינת הסקר');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת חיבור');
    } finally {
      if (mounted) setState(() => _loadingSmartSurvey = false);
    }
  }

  Future<void> _submitSmartSurvey() async {
    if (_smartSurveyResponses.isEmpty || _submittingSmartSurvey) return;
    setState(() => _submittingSmartSurvey = true);
    try {
      final userName = widget.settings.userName.trim();
      final res = await http.post(
        Uri.parse('$_base/survey-submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userName': userName,
          'responses': _smartSurveyResponses,
          'survey': _smartSurveyQuestions,
        }),
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() { _showSmartSurvey = false; _smartSurveyQuestions = []; _smartSurveyResponses.clear(); });
        _showSnack('תודה! הסקר נשמר בהצלחה ✓');
        _loadSurveys();
      } else {
        _showSnack('שגיאה בשמירת הסקר');
      }
    } catch (_) {
      if (mounted) _showSnack('שגיאת חיבור');
    } finally {
      if (mounted) setState(() => _submittingSmartSurvey = false);
    }
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
        body: jsonEncode({'userName': widget.settings.userName}),
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
          title: RichText(
            text: TextSpan(
              style: const TextStyle(fontFamily: 'Heebo', fontSize: 17),
              children: [
                const TextSpan(
                  text: 'ג׳רביס',
                  style: TextStyle(color: _kGold, fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' — לוח ניהול',
                  style: TextStyle(color: JC.textMuted, fontWeight: FontWeight.w400, fontSize: 14),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: JC.textSecondary, size: 20),
              onPressed: _loadAll,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(62),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: JC.border.withOpacity(0.5), width: 0.6),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: _kGold,
                unselectedLabelColor: JC.textMuted,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _kGold.withOpacity(0.12),
                  border: Border.all(color: _kGold.withOpacity(0.45), width: 0.8),
                  boxShadow: [
                    BoxShadow(color: _kGold.withOpacity(0.18), blurRadius: 10, spreadRadius: 0),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 11),
                unselectedLabelStyle: const TextStyle(fontFamily: 'Heebo', fontSize: 11),
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
        ControlCenterTab.overview     => 'סקירה',
        ControlCenterTab.agents       => 'סוכנים',
        ControlCenterTab.analytics    => 'אנליטיקה',
        ControlCenterTab.development  => 'פיתוח',
        ControlCenterTab.testsSurveys => 'בדיקות',
        ControlCenterTab.settings     => 'הגדרות',
      };

  IconData _tabIcon(ControlCenterTab t) => switch (t) {
        ControlCenterTab.overview     => Icons.bar_chart_rounded,
        ControlCenterTab.agents       => Icons.smart_toy_outlined,
        ControlCenterTab.analytics    => Icons.analytics_outlined,
        ControlCenterTab.development  => Icons.build_outlined,
        ControlCenterTab.testsSurveys => Icons.science_outlined,
        ControlCenterTab.settings     => Icons.settings_outlined,
      };

  Widget _buildTabBody(ControlCenterTab t) => switch (t) {
        ControlCenterTab.overview     => _buildOverviewTab(),
        ControlCenterTab.agents       => _buildAgentsTab(),
        ControlCenterTab.analytics    => _buildAnalyticsTab(),
        ControlCenterTab.development  => _buildDevelopmentTab(),
        ControlCenterTab.testsSurveys => _buildTestsSurveysTab(),
        ControlCenterTab.settings     => _buildSettingsTab(),
      };

  Widget _tabWithBadge(String label, ControlCenterTab tab) {
    final count = _tabBadges[tab] ?? 0;
    final icon = Icon(_tabIcon(tab), size: 18);
    final iconWidget = count <= 0
        ? icon
        : Stack(
            clipBehavior: Clip.none,
            children: [
              icon,
              Positioned(
                top: -4, right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(8)),
                  constraints: const BoxConstraints(minWidth: 14),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'Heebo', fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          );
    return Tab(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [iconWidget, const SizedBox(height: 2), Text(label)],
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
            : _kGold;
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
                      style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12, height: 1.5)),
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
      color: _kGold,
      backgroundColor: JC.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: children,
      ),
    );
  }

  Widget _buildGreeting() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'בוקר טוב'
        : hour < 17
            ? 'צהריים טובים'
            : 'ערב טוב';
    final name = widget.settings.userName.trim();
    final greeting2 = name.isEmpty ? greeting : '$greeting, $name';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kGold.withOpacity(0.10), _kGold.withOpacity(0.02)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(greeting2,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo',
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text('ג׳רביס — לוח ניהול',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (_isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _kGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kGold.withOpacity(0.5), width: 0.8),
              ),
              child: Text('🛡 אדמין',
                  style: TextStyle(color: _kGold, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700, fontSize: 11)),
            )
          else
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kGold.withOpacity(0.12),
                border: Border.all(color: _kGold.withOpacity(0.3), width: 0.8),
              ),
              child: const Center(child: Text('👤', style: TextStyle(fontSize: 18))),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() => _tabListView([
        _buildGreeting(),
        const SizedBox(height: 12),
        _buildCommandBar(),
        const SizedBox(height: 12),
        _buildStatusBar(),
        const SizedBox(height: 10),
        _buildOverviewQuickActions(),
        const SizedBox(height: 14),
        _sectionTitle('💡 תובנות פרואקטיביות'),
        const SizedBox(height: 8),
        _buildInsightsCard(),
      ]);

  // ── Analytics tab ─────────────────────────────────────────────────────────
  Widget _buildAnalyticsTab() {
    final pendingProposals = _proposals.where((p) => p['status'] == _PS.proposal).length;
    final activeProposals  = _proposals.where((p) => p['status'] == _PS.active).length;
    final counters = [
      ('שיחות',   _stats['chat']?['total'],     '${_stats['chat']?['today'] ?? 0} היום',    Icons.chat_bubble_outline),
      ('משימות',  _stats['tasks']?['total'],    '${(_stats['tasks']?['total'] ?? 0) - (_stats['tasks']?['done'] ?? 0)} פתוחות', Icons.task_alt_rounded),
      ('תזכורות', _stats['reminders']?['total'],'${_stats['reminders']?['active'] ?? 0} פעילות', Icons.alarm_rounded),
      ('הצעות',   pendingProposals,             '$activeProposals פעילות',                  Icons.lightbulb_outline),
    ];
    final topAgents = List<Map<String, dynamic>>.from(_convInsights['topAgents'] ?? []);
    final intentSplit = Map<String, dynamic>.from(_convInsights['intentClassification'] ?? {});
    return _tabListView([
      // ── 4 counter cards ──────────────────────────────────────────
      GridView.count(
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.5,
        children: counters.map((entry) {
          final label = entry.$1;
          final val   = entry.$2;
          final sub   = entry.$3;
          final icon  = entry.$4;
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withOpacity(0.25), width: 0.8),
              boxShadow: [BoxShadow(color: _kGold.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: _kGoldDim),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
              const Spacer(),
              Text(_loadingStats ? '…' : (val?.toString() ?? '—'),
                  style: const TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 28, fontWeight: FontWeight.w800, height: 1)),
              Text(sub, style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10), overflow: TextOverflow.ellipsis),
            ]),
          );
        }).toList(),
      ),
      const SizedBox(height: 18),
      // ── Top agents ───────────────────────────────────────────────
      _sectionTitle('🤖 סוכנים פעילים'),
      const SizedBox(height: 8),
      if (_loadingConvInsights && topAgents.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2, color: _kGold)))
      else if (topAgents.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
          child: Text('אין נתוני שיחות עדיין', textAlign: TextAlign.right, style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12.5)),
        )
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            ...topAgents.take(6).map((a) {
              final name = a['agent']?.toString() ?? '';
              final count = (a['count'] as num?)?.toInt() ?? 0;
              final maxCount = (topAgents.first['count'] as num?)?.toInt() ?? 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(textDirection: TextDirection.rtl, children: [
                    Text(name, textAlign: TextAlign.right,
                        style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('$count', style: TextStyle(color: _kGoldDim, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxCount > 0 ? count / maxCount : 0,
                      minHeight: 5,
                      color: _kGold,
                      backgroundColor: _kGold.withOpacity(0.12),
                    ),
                  ),
                ]),
              );
            }),
          ]),
        ),
      const SizedBox(height: 18),
      // ── Intent breakdown ─────────────────────────────────────────
      if (intentSplit.isNotEmpty) ...[
        _sectionTitle('📊 פילוח כוונות'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
          child: Wrap(
            spacing: 6, runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: intentSplit.entries.take(8).map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kGold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _kGold.withOpacity(0.25)),
              ),
              child: Text('${e.key}  ${e.value}',
                  style: TextStyle(color: _kGoldDim, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
            )).toList(),
          ),
        ),
        const SizedBox(height: 18),
      ],
      // ── Provider breakdown ───────────────────────────────────────
      _sectionTitle('⚡ פילוח מודלים'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
        child: _buildProviderBreakdown(),
      ),
    ]);
  }

  Widget _buildOverviewQuickActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _triggeringE2e ? null : _triggerE2eRun,
            icon: _triggeringE2e
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
                : const Icon(Icons.play_circle_outline_rounded, size: 18),
            label: const Text('הרץ e2e עכשיו', style: TextStyle(fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kGold,
              side: const BorderSide(color: _kGold, width: 0.8),
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
  static const List<String> _kCommandSuggestions = [
    'הצג סטטיסטיקות',
    'כבה סוכן',
    'הרץ סריקה',
    'פתח אנליטיקה',
  ];

  Widget _buildCommandBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kGold.withOpacity(0.12), _kGold.withOpacity(0.03)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withOpacity(0.30), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.bolt_rounded, size: 18, color: _kGold),
            const SizedBox(width: 6),
            Text('שורת פקודה', style: TextStyle(color: _kGold, fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
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
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _kGold, width: 1.2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: _runningCmd ? null : _runCommand,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGold,
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
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _kCommandSuggestions.map((s) => Padding(
                padding: const EdgeInsets.only(left: 6),
                child: GestureDetector(
                  onTap: () {
                    _cmdCtrl.text = s;
                    _runCommand();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kGold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kGold.withOpacity(0.30), width: 0.8),
                    ),
                    child: Text(s,
                        style: TextStyle(color: _kGoldDim, fontFamily: 'Heebo',
                            fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
              )).toList(),
            ),
          ),
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

  ControlCenterTab? _serverTabToCc(String? id) {
    switch (id) {
      case 'overview': return ControlCenterTab.overview;
      case 'analytics': return ControlCenterTab.analytics;
      case 'agents': return ControlCenterTab.agents;
      case 'dev': return ControlCenterTab.development;
      case 'qa': return ControlCenterTab.testsSurveys;
      case 'settings': return ControlCenterTab.settings;
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
        child: CircularProgressIndicator(color: _kGold, strokeWidth: 2),
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
        // ── Smart proposals (personalised from survey + usage) ────────────────
        _buildSmartProposalsSection(),
        const SizedBox(height: 20),

        // ── Conversation insights ─────────────────────────────────────────────
        _sectionTitle('📊 תובנות שיחות'),
        const SizedBox(height: 8),
        _buildConvInsightsCard(),
        const SizedBox(height: 18),

        // ── Feedback pipeline (only if concerns exist) ────────────────────────
        if (_feedbackConcerns.isNotEmpty) ...[
          _sectionTitle('🔧 פידבק → פיתוח'),
          const SizedBox(height: 8),
          _buildFeedbackPipelineCard(),
          const SizedBox(height: 18),
        ],

        _sectionTitle('🗂️ סטטוס יכולות'),
        const SizedBox(height: 8),
        _buildCapabilitiesSection(),
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

  Widget _buildAgentsTab() {
    final filtered = _agentSearch.isEmpty
        ? _agents
        : _agents.where((a) {
            final name = (a['nameHe'] ?? a['name'] ?? a['id'] ?? '').toString().toLowerCase();
            final role = (a['role'] ?? '').toString().toLowerCase();
            final q = _agentSearch.toLowerCase();
            return name.contains(q) || role.contains(q);
          }).toList();

    return Column(
      children: [
        // Search bar pinned at top
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            textDirection: TextDirection.rtl,
            onChanged: (v) => setState(() => _agentSearch = v),
            style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'חיפוש סוכן...',
              hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12.5),
              prefixIcon: Icon(Icons.search, size: 18, color: JC.textMuted),
              filled: true,
              fillColor: JC.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: JC.border, width: 0.8)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: JC.border, width: 0.8)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _kGold, width: 1.2)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingAgents && _agents.isEmpty)
          const Expanded(child: Center(child: CircularProgressIndicator(color: _kGold, strokeWidth: 2)))
        else if (_agents.isEmpty)
          Expanded(child: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('לא נטענו סוכנים. בדוק חיבור לשרת.',
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
          )))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadAgents,
              color: _kGold,
              backgroundColor: JC.surface,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: filtered.isEmpty ? 1 : filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('אין תוצאות לחיפוש "$_agentSearch"',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
                    );
                  }
                  return _buildAgentTile(filtered[i]);
                },
              ),
            ),
          ),
      ],
    );
  }

  // ── בדיקות וסקרים: E2E reports (live) + read-only survey summary ───────────
  Widget _buildTestsSurveysTab() {
    final hasUserName = widget.settings.userName.trim().isNotEmpty;
    return Stack(
      children: [
        _tabListView([
      _sectionTitle('⚡ פעולות מהירות'),
      const SizedBox(height: 8),
      _buildOverviewQuickActions(),
      const SizedBox(height: 14),
      // Smart survey button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _loadingSmartSurvey ? null : _loadSmartSurvey,
          icon: _loadingSmartSurvey
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('✨', style: TextStyle(fontSize: 16)),
          label: Text(_loadingSmartSurvey ? 'טוען סקר...' : 'התחל סקר חכם',
              style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGold,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
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
    ]),
        // Smart survey modal overlay
        if (_showSmartSurvey) _buildSmartSurveyOverlay(),
      ],
    );
  }

  // ── Smart survey overlay ──────────────────────────────────────────────────
  Widget _buildSmartSurveyOverlay() {
    return Positioned.fill(
      child: Container(
        color: JC.bg.withValues(alpha: 0.95),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: const Text('✨ סקר חכם',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: _kGold, fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: JC.textMuted, size: 20),
                    onPressed: () => setState(() => _showSmartSurvey = false),
                  ),
                ],
              ),
            ),
            Text('השאלות נבחרו במיוחד בשבילך על סמך הסוכנים שהשתמשת בהם.',
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _smartSurveyQuestions.length,
                itemBuilder: (_, i) {
                  final q = _smartSurveyQuestions[i];
                  final qId = q['id']?.toString() ?? 'q$i';
                  final question = q['question']?.toString() ?? '';
                  final options = List<String>.from(q['options'] ?? []);
                  final isOpenText = q['open_text'] == true;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: JC.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: JC.border, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(question,
                            textAlign: TextAlign.right,
                            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo',
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        if (isOpenText)
                          TextField(
                            textDirection: TextDirection.rtl,
                            onChanged: (v) => setState(() => _smartSurveyResponses[qId] = v),
                            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'כתוב תשובה חופשית...',
                              hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
                              contentPadding: const EdgeInsets.all(8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: JC.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: JC.border),
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 6, runSpacing: 6,
                            textDirection: TextDirection.rtl,
                            children: options.map((opt) {
                              final selected = _smartSurveyResponses[qId] == opt;
                              return GestureDetector(
                                onTap: () => setState(() => _smartSurveyResponses[qId] = opt),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? _kGold.withOpacity(0.15)
                                        : JC.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: selected ? _kGold : JC.border,
                                      width: selected ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: Text(opt,
                                      style: TextStyle(
                                        color: selected ? _kGold : JC.textSecondary,
                                        fontFamily: 'Heebo', fontSize: 12,
                                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                      )),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Submit button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_submittingSmartSurvey || _smartSurveyResponses.isEmpty)
                      ? null
                      : _submitSmartSurvey,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _submittingSmartSurvey
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('שלח תשובות',
                          style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Conversation insights card (dev tab) ──────────────────────────────────
  // ── Smart proposals section ───────────────────────────────────────────────
  Widget _buildSmartProposalsSection() {
    final visible = _smartProposals.where((p) => !_dismissedSmartProposals.contains(p['id']?.toString())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Header row
        Row(
          textDirection: TextDirection.rtl,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('הצעות חכמות',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: _kGold,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
            if (_smartProposalsGenerated && !_loadingSmartProposals)
              TextButton.icon(
                onPressed: () {
                  setState(() { _smartProposals = []; _smartProposalsGenerated = false; });
                  _loadSmartProposals();
                },
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('רענן', style: TextStyle(fontFamily: 'Heebo', fontSize: 11)),
                style: TextButton.styleFrom(foregroundColor: _kGoldDim, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('מבוסס על תשובות הסקרים שלך ודפוסי השימוש',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11)),
        const SizedBox(height: 10),

        // Generate button (first load)
        if (!_smartProposalsGenerated && !_loadingSmartProposals)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _loadSmartProposals,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('הפק הצעות חכמות', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kGold,
                side: BorderSide(color: _kGold.withOpacity(0.6), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

        // Loading state
        if (_loadingSmartProposals)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withOpacity(0.2), width: 0.8),
            ),
            child: Column(children: [
              const CircularProgressIndicator(strokeWidth: 2, color: _kGold),
              const SizedBox(height: 12),
              Text('מנתח סקרים ודפוסי שימוש…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
            ]),
          ),

        // Empty state (generated but nothing)
        if (_smartProposalsGenerated && !_loadingSmartProposals && visible.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JC.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JC.border, width: 0.8),
            ),
            child: Text('כל ההצעות טופלו ✓\nלחץ "רענן" לייצר הצעות חדשות.',
                textAlign: TextAlign.center,
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
          ),

        // Proposal cards
        ...visible.map((p) => _buildSmartProposalCard(p)),
      ],
    );
  }

  Widget _buildSmartProposalCard(Map<String, dynamic> p) {
    final id             = p['id']?.toString() ?? '';
    final title          = p['title']?.toString() ?? '';
    final description    = p['description']?.toString() ?? '';
    final rationale      = p['rationale']?.toString() ?? '';
    final source         = p['source']?.toString() ?? 'usage';
    final category       = p['category']?.toString() ?? 'improvement';
    final priorityScore  = (p['priority_score'] as num?)?.toInt() ?? 5;

    final (sourceBadge, sourceColor) = switch (source) {
      'survey' => ('🗣️ סקר',       const Color(0xFF7C3AED)),
      'both'   => ('⭐ סקר+שימוש', const Color(0xFFEA580C)),
      _        => ('📊 שימוש',     const Color(0xFF0EA5E9)),
    };
    final priorityColor = priorityScore >= 8
        ? const Color(0xFFEF4444)
        : priorityScore >= 6
            ? const Color(0xFFF59E0B)
            : const Color(0xFF6B7280);

    final categoryLabel = switch (category) {
      'bug_fix'     => 'תיקון',
      'ux'          => 'חוויה',
      'performance' => 'ביצועים',
      'feature'     => 'פיצ\'ר',
      _             => 'שיפור',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withOpacity(0.2), width: 0.9),
        boxShadow: [BoxShadow(color: _kGold.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Badges row
            Row(
              textDirection: TextDirection.rtl,
              children: [
                // Source badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: sourceColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sourceColor.withOpacity(0.3), width: 0.7),
                  ),
                  child: Text(sourceBadge,
                      style: TextStyle(color: sourceColor, fontFamily: 'Heebo', fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: JC.border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(categoryLabel,
                      style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                ),
                const Spacer(),
                // Priority badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: priorityColor.withOpacity(0.35), width: 0.7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.priority_high, size: 10, color: priorityColor),
                      const SizedBox(width: 3),
                      Text('$priorityScore/10',
                          style: TextStyle(color: priorityColor, fontFamily: 'Heebo', fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Dismiss X
                GestureDetector(
                  onTap: () => _dismissSmartProposal(id),
                  child: Icon(Icons.close, size: 16, color: JC.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 9),

            // Title
            Text(title,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 5),

            // Description
            Text(description,
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12.5, height: 1.45)),

            if (rationale.isNotEmpty) ...[
              const SizedBox(height: 5),
              Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 12, color: _kGoldDim),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(rationale,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: _kGoldDim, fontFamily: 'Heebo', fontSize: 11, fontStyle: FontStyle.italic)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _showProposalClarifyFlow(p, mode: 'claude'),
                    icon: const Icon(Icons.auto_awesome, size: 13),
                    label: const Text('הוסף לפיתוח', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 11.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => _showProposalClarifyFlow(p, mode: 'task'),
                    icon: const Icon(Icons.task_alt_outlined, size: 13),
                    label: const Text('משימה', style: TextStyle(fontFamily: 'Heebo', fontSize: 11.5, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kGold,
                      side: BorderSide(color: _kGold.withOpacity(0.6), width: 0.9),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: () => _dismissSmartProposal(id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: JC.textMuted,
                    side: BorderSide(color: JC.border, width: 0.7),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    minimumSize: Size.zero,
                  ),
                  child: const Icon(Icons.thumb_down_outlined, size: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConvInsightsCard() {
    if (_loadingConvInsights) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.border, width: 0.8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final topAgents = List<Map<String, dynamic>>.from(_convInsights['topAgents'] ?? []);
    final intentSplit = Map<String, dynamic>.from(_convInsights['intentClassification'] ?? {});
    final chatVolume = (_convInsights['recentChatVolume'] as num?)?.toInt() ?? 0;
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
          // Volume stat
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Text('$chatVolume',
                  style: const TextStyle(color: _kGold, fontFamily: 'Heebo',
                      fontWeight: FontWeight.w800, fontSize: 28, height: 1)),
              const SizedBox(width: 6),
              Text('שיחות ב-7 ימים',
                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12)),
            ],
          ),
          if (topAgents.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('סוכנים פעילים',
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...topAgents.take(5).map((a) {
              final name = a['agent']?.toString() ?? '';
              final count = (a['count'] as num?)?.toInt() ?? 0;
              final maxCount = (topAgents.first['count'] as num?)?.toInt() ?? 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(name,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: maxCount > 0 ? count / maxCount : 0,
                          color: _kGold,
                          backgroundColor: JC.border,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('$count',
                        style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                  ],
                ),
              );
            }),
          ],
          if (intentSplit.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('סוגי פניות',
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 4,
              textDirection: TextDirection.rtl,
              children: intentSplit.entries.take(6).map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kGold.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _kGold.withOpacity(0.2)),
                  ),
                  child: Text('${e.key} (${e.value})',
                      style: const TextStyle(color: _kGoldDim, fontFamily: 'Heebo', fontSize: 10)),
                );
              }).toList(),
            ),
          ],
          if (topAgents.isEmpty && intentSplit.isEmpty)
            Text('אין נתונים להצגה עדיין.',
                textAlign: TextAlign.right,
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
        ],
      ),
    );
  }

  // ── Feedback → dev pipeline card ─────────────────────────────────────────
  Widget _buildFeedbackPipelineCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              const Text('🔧', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text('${_feedbackConcerns.length} תחומים לשיפור מהסקרים',
                  style: TextStyle(color: const Color(0xFFF59E0B), fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          ..._feedbackConcerns.take(4).map((c) {
            final area = c['area']?.toString() ?? '';
            final answer = c['answer']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(area,
                            textAlign: TextAlign.right,
                            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo',
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('תשובה: $answer',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFFF59E0B), size: 12),
                ],
              ),
            );
          }),
        ],
      ),
    );
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
      color: active ? _kGold : JC.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _settingRole ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? _kGold : JC.border, width: 1),
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
      if (!mounted) return;
      // Update role and rebuild TabController atomically before any await so that
      // concurrent setState calls (e.g. the event poller) never see a mismatch
      // between _visibleTabs.length and _tabController.length, which would
      // produce the "BOTTOM OVERFLOWED BY 99899 PIXELS" blank-tab-bar bug.
      widget.settings.role = role;
      _tabController.dispose();
      final newIdx = _visibleTabs.indexOf(oldTab);
      _tabController = TabController(
        length: _visibleTabs.length,
        vsync: this,
        initialIndex: newIdx >= 0 ? newIdx : 0,
      );
      setState(() => _settingRole = false);
      widget.settings.save(); // fire-and-forget; no await needed for UI correctness
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
              backgroundColor: _kGold,
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
      return SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: _kGold, strokeWidth: 2)),
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
      return SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: _kGold, strokeWidth: 2)),
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
              child: const Text('נסה עכשיו',
                  style: TextStyle(color: _kGold, fontFamily: 'Heebo',
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

  // ── Capabilities section (core agents + features in dev) ─────────────────

  Widget _buildCapabilitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Section A: יכולות ליבה (real Jarvis agents) ──────────────────
        _buildCoreCapabilitiesSection(),
        const SizedBox(height: 20),
        // ── Section B: בפיתוח (features.json building + planned) ─────────
        _buildInDevFeaturesSection(),
      ],
    );
  }

  Widget _buildCoreCapabilitiesSection() {
    if (_loadingAgents && _agents.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: _kGold, strokeWidth: 2),
      );
    }
    if (_agents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: JC.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JC.border, width: 0.8)),
        child: Text('לא נטענו יכולות', textAlign: TextAlign.center, style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
      );
    }
    // Sort agents by usage count (most used first)
    final sorted = [..._agents];
    sorted.sort((a, b) {
      final ca = ((a['metrics'] as Map?)??{})['count'] as num? ?? 0;
      final cb = ((b['metrics'] as Map?)??{})['count'] as num? ?? 0;
      return cb.compareTo(ca);
    });

    final unusedCount = sorted.where((a) {
      final c = ((a['metrics'] as Map?)??{})['count'] as num? ?? 0;
      return c == 0;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: Text('⚙️ יכולות ליבה — ${sorted.length} סוכנים',
                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            if (unusedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.35), width: 0.7),
                ),
                child: Text('$unusedCount ישן',
                    style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo', fontSize: 10, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ...sorted.map((agent) => _buildCoreCapabilityTile(agent)),
      ],
    );
  }

  Widget _buildCoreCapabilityTile(Map<String, dynamic> agent) {
    final id       = (agent['id'] ?? '').toString();
    final nameHe   = (agent['nameHe'] ?? agent['name'] ?? id).toString();
    final role     = (agent['role'] ?? '').toString();
    final status   = (agent['status'] ?? 'active').toString();
    final isDisabled = status == 'disabled';
    final isToggling = _togglingAgents.contains(id);
    final metrics  = agent['metrics'] as Map<String, dynamic>?;
    final callCount = (metrics?['count'] as num?)?.toInt() ?? 0;
    final avgMs    = metrics?['avgMs'] as num?;
    final isUnused = callCount == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isUnused
              ? const Color(0xFFEF4444).withOpacity(0.25)
              : isDisabled
                  ? JC.border.withOpacity(0.5)
                  : JC.border,
          width: 0.8,
        ),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          // Status dot
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDisabled
                  ? JC.textMuted
                  : isUnused
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF22C55E),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Expanded(
                      child: Text(nameHe,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: JC.textPrimary, fontFamily: 'Heebo',
                            fontWeight: FontWeight.w600, fontSize: 13,
                            decoration: isDisabled ? TextDecoration.lineThrough : null,
                          )),
                    ),
                    if (isUnused)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('לא בשימוש',
                            style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo', fontSize: 9, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                if (role.isNotEmpty)
                  Text(role, textAlign: TextAlign.right,
                      style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                // Usage stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (callCount > 0)
                      Text('$callCount קריאות',
                          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                    if (callCount > 0 && avgMs != null)
                      Text(' · ', style: TextStyle(color: JC.textMuted, fontSize: 10)),
                    if (avgMs != null)
                      Text('${avgMs.toInt()}ms ממוצע',
                          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10)),
                    if (callCount == 0)
                      Text('עדיין לא נוצל',
                          style: TextStyle(color: const Color(0xFFEF4444).withOpacity(0.7), fontFamily: 'Heebo', fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Action buttons: details + send to claude + toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Details
              GestureDetector(
                onTap: () => _showAgentDetails(agent),
                child: Icon(Icons.info_outline, size: 18, color: JC.textMuted),
              ),
              const SizedBox(width: 4),
              // Send to Claude for improvement
              Builder(builder: (ctx) => GestureDetector(
                onTap: () {
                  final prompt = '''שיפור יכולת ב-Jarvis: $nameHe
תפקיד: $role
${callCount > 0 ? 'שימוש: $callCount קריאות, ממוצע ${avgMs?.toInt() ?? 0}ms' : 'מצב: לא בשימוש כלל'}

אנא עזור לי לשפר את הסוכן הזה:
1. מה ניתן לשפר בלוגיקה ובתגובות?
2. איך לגרום למשתמשים להשתמש בו יותר?
3. קוד לדוגמה לשיפורים עיקריים
4. מה מדדי הצלחה מומלצים?''';
                  _showSendToClaudeMenu(ctx, prompt, title: nameHe);
                },
                child: Icon(Icons.open_in_new, size: 17, color: _kGoldDim),
              )),
              const SizedBox(width: 2),
              // Toggle enable/disable
              SizedBox(
                width: 28, height: 28,
                child: isToggling
                    ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
                    : IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: isDisabled ? 'הפעל' : 'השבת',
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
        ],
      ),
    );
  }

  Widget _buildInDevFeaturesSection() {
    final inDev = [..._building, ..._planned];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: Text('🔨 בפיתוח — ${inDev.length} פיצ\'רים',
                  style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Builder(builder: (ctx) => GestureDetector(
              onTap: () => _showAddFeatureDialog(ctx),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kGold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _kGold.withOpacity(0.4), width: 0.7),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 12, color: _kGold),
                  const SizedBox(width: 3),
                  Text('הוסף', style: TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 10.5, fontWeight: FontWeight.w600)),
                ]),
              ),
            )),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingFeatures)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: _kGold, strokeWidth: 2)))
        else if (inDev.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(child: Text('אין פיצ\'רים בפיתוח — לחץ הוסף',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13))),
          )
        else
          Builder(builder: (ctx) => Wrap(
            spacing: 6, runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: [
              ..._building.map((f) => _featureChip(f, const Color(0xFFF59E0B), 'building', ctx)),
              ..._planned.map((f) => _featureChip(f, JC.textSecondary, 'planned', ctx)),
            ],
          )),
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

  // ── Feature board ─────────────────────────────────────────────────────────

  Widget _buildFeatureBoard() {
    if (_loadingFeatures) {
      return SizedBox(height: 140,
          child: Center(child: CircularProgressIndicator(color: _kGold, strokeWidth: 2)));
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
                  color: _kGold.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kGold.withOpacity(0.4)),
                ),
                child: const Text('טעון מחדש',
                    style: TextStyle(color: _kGold, fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ]),
        ),
      );
    }

    final labels      = ['✅ ${_done.length} הושלם', '🔨 ${_building.length} בבנייה', '📋 ${_planned.length} מתוכנן'];
    final statusKeys  = ['done', 'building', 'planned'];
    final itemLists   = [_done, _building, _planned];
    final colors      = [const Color(0xFF22C55E), const Color(0xFFF59E0B), JC.textSecondary];
    final currentItems = itemLists[_featureTabIndex];
    final currentColor = colors[_featureTabIndex];
    final currentStatusKey = statusKeys[_featureTabIndex];

    // Count features without descriptions
    final emptyDescCount = [..._done, ..._building, ..._planned]
        .where((f) => (f['desc'] ?? '').toString().trim().isEmpty).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // "Generate descriptions" banner — shown when features have no description
        if (emptyDescCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: _generatingFeatureDescriptions ? null : _generateFeatureDescriptions,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: _kGold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGold.withOpacity(0.3), width: 0.8),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    if (_generatingFeatureDescriptions)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGold))
                    else
                      const Text('🤖', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _generatingFeatureDescriptions
                            ? 'מייצר הסברים...'
                            : 'ייצר הסברים ל-$emptyDescCount יכולות ללא תיאור',
                        style: TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!_generatingFeatureDescriptions)
                      Icon(Icons.auto_awesome, size: 14, color: _kGold.withOpacity(0.7)),
                  ],
                ),
              ),
            ),
          ),
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('אין פריטים — לחץ + להוסיף',
                style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo', fontSize: 13))),
          )
        else
          Builder(builder: (ctx) => Wrap(
            spacing: 6,
            runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: currentItems.map((f) => _featureChip(f, currentColor, currentStatusKey, ctx)).toList(),
          )),
        const SizedBox(height: 10),
        // "Add feature" button
        Builder(builder: (ctx) => GestureDetector(
          onTap: () => _showAddFeatureDialog(ctx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGold.withOpacity(0.4), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: _kGold),
                const SizedBox(width: 4),
                Text('הוסף יכולת', style: TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        )),
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

  Widget _featureChip(Map<String, dynamic> f, Color color, String statusKey, BuildContext ctx) {
    final name = f['name']?.toString() ?? '—';
    final desc = f['desc']?.toString().trim() ?? '';
    final hasDesc = desc.isNotEmpty;
    return GestureDetector(
      onTap: () => _showFeatureDetailSheet(ctx, f, statusKey),
      child: Container(
        padding: EdgeInsets.fromLTRB(10, hasDesc ? 8 : 6, 10, hasDesc ? 8 : 6),
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          borderRadius: BorderRadius.circular(hasDesc ? 10 : 20),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo',
                          fontSize: 12, fontWeight: hasDesc ? FontWeight.w600 : FontWeight.w400)),
                  if (hasDesc) ...[
                    const SizedBox(height: 2),
                    Text(desc,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 10.5, height: 1.35)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.chevron_right, size: 12, color: color.withOpacity(0.6)),
            ),
          ],
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
                      padding: const EdgeInsetsDirectional.only(end: 6),
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
                      padding: const EdgeInsetsDirectional.only(end: 6),
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
              const CircularProgressIndicator(color: _kGold, strokeWidth: 2),
              const SizedBox(height: 10),
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
        ? _kGold
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
                    left:   BorderSide(color: isActive ? _kGold.withOpacity(0.4) : JC.border, width: 0.8),
                    top:    BorderSide(color: isActive ? _kGold.withOpacity(0.4) : JC.border, width: 0.8),
                    bottom: BorderSide(color: isActive ? _kGold.withOpacity(0.4) : JC.border, width: 0.8),
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
                            _badge('Conf ${scores['confidence'] ?? '—'}/5', _kGoldDim),
                            _badge('Score ${scores['weighted_score'] ?? '—'}', const Color(0xFFA78BFA)),
                          ],
                        ),
                      ],
                      if (whyNow.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: _kGold.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kGold.withOpacity(0.22), width: 0.8),
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
                                  color: isActive ? Colors.transparent : _kGold.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _kGold.withOpacity(0.35), width: 0.8),
                                ),
                                child: activating
                                    ? const SizedBox(
                                        width: 13, height: 13,
                                        child: CircularProgressIndicator(strokeWidth: 1.8, color: _kGold),
                                      )
                                    : Text(isActive ? '⏸ חזרה לתכנון' : isDraftPlan ? '⚡ התחל ביצוע' : isValidation ? '⚡ חזרה לביצוע' : '🧭 צור תכנית',
                                        style: const TextStyle(color: _kGold, fontFamily: 'Heebo',
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

          // ── Send to Claude ─────────────────────────────────────────────────
          Builder(builder: (ctx) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () => _showSendToClaudeMenu(ctx, _proposalToPrompt(p), title: title),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kGold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kGold.withOpacity(0.3), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🤖', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        Text('שלח לקלוד', style: TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )),

          // ── Inline Jarvis response ─────────────────────────────────────────
          if (response != null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kGold.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kGold.withOpacity(0.2)),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text('🤖 ג׳רביס:',
                            style: TextStyle(color: _kGold, fontFamily: 'Heebo',
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        const Spacer(),
                        if (widget.onSwitchToChat != null)
                          GestureDetector(
                            onTap: () => _switchToChatWithProposal(p),
                            child: const Text('המשך בצ׳אט ←',
                                style: TextStyle(color: _kGold, fontFamily: 'Heebo',
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
              const Icon(Icons.auto_awesome_rounded, color: _kGold, size: 13),
              const SizedBox(width: 5),
              const Text("מחולל פרומפט לפיצ'ר חדש ב-Claude Code",
                  style: TextStyle(color: _kGold, fontFamily: 'Heebo',
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
                  color: _generatingPrompt ? _kGold.withOpacity(0.5) : _kGold,
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
                              size: 12, color: _kGold),
                          const SizedBox(width: 4),
                          Text(_promptCopied ? 'הועתק!' : 'העתק',
                              style: const TextStyle(color: _kGold,
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
                color: _kGold,
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
              child: CircularProgressIndicator(color: _kGold, strokeWidth: 2))
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
          alignment: AlignmentDirectional.centerEnd,
          padding: const EdgeInsetsDirectional.only(end: 16),
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
              textColor: _kGold,
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
      return SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(color: _kGold, strokeWidth: 2)),
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
                          : _kGoldDim,
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
                      if (mode.isNotEmpty) _badge(mode, _kGoldDim),
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
                    ? const Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
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
          color: selected ? _kGold.withOpacity(0.15) : JC.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _kGold.withOpacity(0.6) : JC.border,
            width: selected ? 1.0 : 0.7,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? _kGold : JC.textMuted,
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
          color: _kGold.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kGold.withOpacity(0.4), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(width: 13, height: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: _kGold))
            else if (icon != null)
              Icon(icon, size: 14, color: _kGold),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(
                color: _kGold, fontFamily: 'Heebo',
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
            borderSide: const BorderSide(color: _kGold)),
      );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(children: [
      Expanded(child: Divider(color: JC.border, height: 1)),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
          color: _kGoldDim, fontSize: 11, fontWeight: FontWeight.w700,
          fontFamily: 'Heebo', letterSpacing: 0.8)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Smart-proposal clarify + prompt-edit bottom sheet (2-step)
// ─────────────────────────────────────────────────────────────────────────────
class _ProposalClarifySheet extends StatefulWidget {
  final Map<String, dynamic> proposal;
  final String mode; // 'claude' | 'task'
  final String base;
  final void Function(String prompt) onSendToClaud;
  final Future<void> Function(Map<String, dynamic> p, {String? refinedPrompt}) onSendAsTask;

  const _ProposalClarifySheet({
    required this.proposal,
    required this.mode,
    required this.base,
    required this.onSendToClaud,
    required this.onSendAsTask,
  });

  @override
  State<_ProposalClarifySheet> createState() => _ProposalClarifySheetState();
}

class _ProposalClarifySheetState extends State<_ProposalClarifySheet> {
  static const Color _kGold    = Color(0xFFC9A84C);
  static const Color _kGoldDim = Color(0xFF8B7035);

  int _step = 0; // 0 = loading questions, 1 = questions, 2 = editing prompt
  List<Map<String, dynamic>> _questions = [];
  // answers: questionId → answer string
  final Map<String, String> _answers = {};
  // free text per question (shown alongside chips)
  final Map<String, TextEditingController> _freeText = {};
  bool _loadingQuestions = true;
  String? _loadError;

  bool _generatingPrompt = false;
  late TextEditingController _promptCtrl;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController();
    _loadQuestions();
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    for (final c in _freeText.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    setState(() { _loadingQuestions = true; _loadError = null; });
    try {
      final p = widget.proposal;
      final res = await http.post(
        Uri.parse('${widget.base}/dashboard/smart-proposals/clarify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': p['title'] ?? '',
          'description': p['description'] ?? '',
          'category': p['category'] ?? 'improvement',
          'rationale': p['rationale'] ?? '',
        }),
      ).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final qs = List<Map<String, dynamic>>.from(d['questions'] ?? []);
        if (qs.isNotEmpty) {
          setState(() {
            _questions = qs;
            _step = 1;
            _loadingQuestions = false;
          });
          for (final q in qs) {
            _freeText.putIfAbsent(q['id'] as String, () => TextEditingController());
          }
          return;
        }
      }
      // Fallback: build questions locally from proposal data
      _applyLocalQuestions();
    } catch (_) {
      if (mounted) _applyLocalQuestions();
    }
  }

  void _applyLocalQuestions() {
    if (!mounted) return;
    final category = widget.proposal['category']?.toString() ?? 'improvement';
    final qs = _localQuestions(category);
    setState(() {
      _questions = qs;
      _step = 1;
      _loadingQuestions = false;
    });
    for (final q in qs) {
      _freeText.putIfAbsent(q['id'] as String, () => TextEditingController());
    }
  }

  List<Map<String, dynamic>> _localQuestions(String category) {
    final title = (widget.proposal['title'] ?? '').toString().toLowerCase();
    final desc  = (widget.proposal['description'] ?? '').toString().toLowerCase();
    final text  = '$title $desc';

    // ── keyword → question bank (matches first winning topic) ───────────────
    final topics = <_TopicQs>[
      _TopicQs(
        keys: ['llm', 'מודל', 'model', 'ai', 'כוונות', 'intent', 'זיהוי', 'router', 'classification'],
        qs: [
          {'id': 'q1', 'question': 'איזה סוג קלטים קשה לזהות כרגע?', 'chips': ['שאלות אמביגואליות', 'מעבר בין נושאים', 'פקודות מקוצרות']},
          {'id': 'q2', 'question': 'מה הגישה המועדפת לשיפור?', 'chips': ['Fine-tuning / Few-shot', 'כללי keyword חדשים', 'שינוי ה-prompt הראשי']},
          {'id': 'q3', 'question': 'מה מדד ההצלחה?', 'chips': ['דיוק >90%', 'פחות fallback ל-LLM', 'זמן סיווג קצר יותר']},
        ],
      ),
      _TopicQs(
        keys: ['agent', 'סוכן', 'אייג׳נט', 'אייג\'נט', 'worker'],
        qs: [
          {'id': 'q1', 'question': 'מה הסוכן הזה אמור לעשות?', 'chips': ['ניהול מידע/נתונים', 'שאילתות חיצוניות', 'אוטומציה של פעולות']},
          {'id': 'q2', 'question': 'כיצד הסוכן יגיע לנתונים?', 'chips': ['Supabase', 'API חיצוני', 'זיכרון/Pinecone']},
          {'id': 'q3', 'question': 'האם נדרשת שמירת state בין שיחות?', 'chips': ['כן — זיכרון ארוך טווח', 'רק בשיחה', 'לא נדרש']},
        ],
      ),
      _TopicQs(
        keys: ['ui', 'ux', 'עיצוב', 'מסך', 'תצוגה', 'כפתור', 'widget', 'flutter', 'interface', 'צ\'אט', 'chat'],
        qs: [
          {'id': 'q1', 'question': 'באיזה מסך/רכיב השינוי?', 'chips': ["מסך הצ'אט הראשי", 'לוח הניהול (Control Center)', 'מסך הגדרות']},
          {'id': 'q2', 'question': 'מה ה-friction שמפריע למשתמש?', 'chips': ['לא ברור לשימוש', 'איטי/לא ספונטני', 'ויזואלית מבולגן']},
          {'id': 'q3', 'question': 'האם נדרש שינוי גם בשרת?', 'chips': ['Flutter בלבד', 'גם API חדש בשרת', 'שינוי לוגיקה עסקית']},
        ],
      ),
      _TopicQs(
        keys: ['reminder', 'תזכורת', 'task', 'משימה', 'calendar', 'לוח שנה', 'scheduling', 'recurring'],
        qs: [
          {'id': 'q1', 'question': 'איזה סוג ניהול זמן מדובר?', 'chips': ['תזכורות חד פעמיות', 'משימות חוזרות', 'שילוב לוח שנה']},
          {'id': 'q2', 'question': 'איך המשתמש יוצר/מנהל?', 'chips': ['דרך הצ\'אט בטבעי', 'ממסך ייעודי', 'שניהם']},
          {'id': 'q3', 'question': 'מה חסר ביכולת הנוכחית?', 'chips': ['התראות אמינות יותר', 'חיפוש וסינון', 'תצוגה ויזואלית']},
        ],
      ),
      _TopicQs(
        keys: ['memory', 'זיכרון', 'pinecone', 'embedding', 'vector', 'knowledge', 'ידע'],
        qs: [
          {'id': 'q1', 'question': 'מה סוג המידע לשמור/לאחזר?', 'chips': ['עובדות אישיות', 'העדפות והרגלים', 'היסטוריית שיחות']},
          {'id': 'q2', 'question': 'מה הבעיה בזיכרון הנוכחי?', 'chips': ['חיפוש לא מדויק', 'מידע ישן/לא רלוונטי', 'איטי מדי']},
          {'id': 'q3', 'question': 'מה אמצעי האחסון המועדף?', 'chips': ['Pinecone (סמנטי)', 'Supabase (מובנה)', 'שניהם']},
        ],
      ),
      _TopicQs(
        keys: ['performance', 'מהירות', 'speed', 'latency', 'cache', 'optimize', 'slow', 'איטי', 'ביצועים'],
        qs: [
          {'id': 'q1', 'question': 'איפה צוואר הבקבוק?', 'chips': ['קריאות LLM', 'שאילתות DB', 'עיבוד תשובה ב-Flutter']},
          {'id': 'q2', 'question': 'מה היעד לזמן תגובה?', 'chips': ['<500ms', '<1 שניה', 'שיפור יחסי 50%']},
          {'id': 'q3', 'question': 'מה הגישה העדיפה?', 'chips': ['Cache חכם', 'Streaming תשובות', 'קיצור ה-prompt']},
        ],
      ),
      _TopicQs(
        keys: ['notification', 'התראה', 'push', 'alert', 'נוטיפיקציה'],
        qs: [
          {'id': 'q1', 'question': 'מה סוג ההתראות?', 'chips': ['תזכורות מתוזמנות', 'אירועים בזמן אמת', 'עדכוני מצב']},
          {'id': 'q2', 'question': 'איפה ההתראה מוצגת?', 'chips': ['Push notification', 'בתוך האפליקציה', 'שניהם']},
          {'id': 'q3', 'question': 'מה הבעיה הנוכחית?', 'chips': ['לא מגיעות בזמן', 'תוכן לא מספיק', 'יותר מדי רעש']},
        ],
      ),
      _TopicQs(
        keys: ['survey', 'סקר', 'feedback', 'פידבק', 'rating', 'דירוג'],
        qs: [
          {'id': 'q1', 'question': 'מה מטרת הסקר?', 'chips': ['הבנת צרכים', 'מדידת שביעות רצון', 'איתור בעיות']},
          {'id': 'q2', 'question': 'מתי הסקר מוצג?', 'chips': ['לאחר שיחה', 'אחת לשבוע', 'לפי trigger ספציפי']},
          {'id': 'q3', 'question': 'מה עושים עם התוצאות?', 'chips': ['מזינים להצעות חכמות', 'מציגים כגרף', 'שניהם']},
        ],
      ),
      _TopicQs(
        keys: ['api', 'endpoint', 'route', 'rest', 'server', 'backend', 'שרת', 'integration'],
        qs: [
          {'id': 'q1', 'question': 'מה הendpoint עושה?', 'chips': ['קריאה/שאילתה', 'כתיבה/עדכון', 'אוטומציה/webhook']},
          {'id': 'q2', 'question': 'מי קורא ל-endpoint הזה?', 'chips': ['אפליקציית Flutter', 'cron job', 'webhook חיצוני']},
          {'id': 'q3', 'question': 'מה שיקולי אבטחה?', 'chips': ['אימות נדרש', 'rate limiting', 'ולידציה של קלט']},
        ],
      ),
    ];

    // Find matching topic
    for (final topic in topics) {
      if (topic.keys.any((k) => text.contains(k))) {
        return topic.qs;
      }
    }

    // Generic fallback by category
    final byCategory = {
      'feature':     [
        {'id': 'q1', 'question': "מה הפיצ'ר הזה פותר?", 'chips': ['חסר כרגע לחלוטין', 'קיים אבל לא מספיק', 'שיפור חוויה']},
        {'id': 'q2', 'question': 'מי ישתמש בו הכי הרבה?', 'chips': ['המשתמש היומיומי', 'מנהל/אדמין', 'כולם']},
        {'id': 'q3', 'question': 'מה הסדר עדיפויות?', 'chips': ['גבוה — נדרש עכשיו', 'בינוני', 'נמוך — nice to have']},
      ],
      'bug_fix':     [
        {'id': 'q1', 'question': 'מה גורם לבאג?', 'chips': ['edge case לא מטופל', 'race condition', 'נתון שגוי מהשרת']},
        {'id': 'q2', 'question': 'כמה משתמשים נפגעים?', 'chips': ['כולם', 'חלק — תלוי בהגדרות', 'מדי פעם']},
        {'id': 'q3', 'question': 'מה צעד הtriage הראשון?', 'chips': ['לוג ב-server', 'בדיקה ב-Flutter', 'בשניהם']},
      ],
      'ux':          [
        {'id': 'q1', 'question': 'מה המשתמש לא מצליח לעשות?', 'chips': ['לא מוצא את הפיצ\'ר', 'לא מבין מה לעשות', 'זורם מסובך מדי']},
        {'id': 'q2', 'question': 'מה השיפור הרצוי?', 'chips': ['פחות צעדים', 'יותר ויזואלי', 'פידבק מיידי']},
        {'id': 'q3', 'question': 'מה הפלטפורמה?', 'chips': ['Android', 'iOS', 'שניהם']},
      ],
      'performance': [
        {'id': 'q1', 'question': 'מה איטי?', 'chips': ['קריאת API', 'רינדור UI', 'חישוב/עיבוד']},
        {'id': 'q2', 'question': 'מה היעד?', 'chips': ['<500ms', '<1 שניה', 'שיפור 50%']},
        {'id': 'q3', 'question': 'מה הגישה?', 'chips': ['cache', 'streaming', 'קיצור prompt']},
      ],
      'improvement': [
        {'id': 'q1', 'question': 'מה השיפור פותר?', 'chips': ['בעיה קיימת', 'חוויה לא מספיקה', 'צורך חדש']},
        {'id': 'q2', 'question': 'באיזה חלק?', 'chips': ['Flutter', 'Node.js', 'שניהם']},
        {'id': 'q3', 'question': 'מה ההגדרת הצלחה?', 'chips': ['מדד כמותי', 'פידבק חיובי', 'ירידה בשגיאות']},
      ],
    };
    return List<Map<String, dynamic>>.from(byCategory[category] ?? byCategory['improvement']!);
  }

  Future<void> _generatePrompt({bool skipQuestions = false}) async {
    setState(() { _generatingPrompt = true; _step = 2; _loadingQuestions = false; });
    try {
      final p = widget.proposal;
      final answersList = skipQuestions
          ? <Map<String, dynamic>>[]
          : _questions.map((q) {
              final qid = q['id'] as String;
              final free = _freeText[qid]?.text.trim() ?? '';
              final sel  = _answers[qid] ?? '';
              final ans  = free.isNotEmpty ? free : sel;
              return {'question': q['question'], 'answer': ans};
            }).where((a) => (a['answer'] as String).isNotEmpty).toList();

      final res = await http.post(
        Uri.parse('${widget.base}/dashboard/smart-proposals/refine-prompt'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': p['title'] ?? '',
          'description': p['description'] ?? '',
          'category': p['category'] ?? 'improvement',
          'rationale': p['rationale'] ?? '',
          'answers': answersList,
        }),
      ).timeout(const Duration(seconds: 25));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        final text = d['prompt']?.toString() ?? '';
        _promptCtrl.text = text.isNotEmpty ? text : _fallbackPrompt();
      } else {
        _promptCtrl.text = _fallbackPrompt();
      }
    } catch (_) {
      if (mounted) _promptCtrl.text = _fallbackPrompt();
    } finally {
      if (mounted) setState(() => _generatingPrompt = false);
    }
  }

  String _fallbackPrompt() {
    final p = widget.proposal;
    final title       = p['title']?.toString() ?? '';
    final description = p['description']?.toString() ?? '';
    final rationale   = p['rationale']?.toString() ?? '';
    return '''📋 הצעת פיתוח: $title

תיאור:
$description
${rationale.isNotEmpty ? '\nרציונל:\n$rationale' : ''}

אנא עזור לי לממש זאת ב-Jarvis (Flutter + Node.js):
1. מה בדיוק לפתח
2. אילו קבצים לשנות/ליצור
3. סדר עבודה מומלץ
4. מה לבדוק לאחר הפיתוח''';
  }

  Future<void> _confirm() async {
    if (_sending) return;
    setState(() => _sending = true);
    final prompt = _promptCtrl.text.trim();
    if (widget.mode == 'claude') {
      Navigator.pop(context);
      widget.onSendToClaud(prompt);
    } else {
      Navigator.pop(context);
      await widget.onSendAsTask(widget.proposal, refinedPrompt: prompt);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, sc) => Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 6),
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: JC.border, borderRadius: BorderRadius.circular(2))),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  children: [
                    Icon(_step == 2 ? Icons.edit_note : Icons.help_outline, size: 18, color: _kGold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _step == 2
                            ? (widget.mode == 'claude' ? '✏️ ערוך פרומפט לקלוד' : '✏️ ערוך פרומפט למשימה')
                            : '🎯 דייק את הפרומפט',
                        style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    if (_step == 2)
                      GestureDetector(
                        onTap: () => setState(() { _step = 1; }),
                        child: Text('← חזור', style: TextStyle(color: _kGoldDim, fontFamily: 'Heebo', fontSize: 12)),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.all(16),
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // Loading questions
    if (_loadingQuestions) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 40),
        const CircularProgressIndicator(color: _kGold, strokeWidth: 2),
        const SizedBox(height: 12),
        Text('מייצר שאלות מדויקות...', style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
      ]);
    }
    if (_loadError != null) {
      return Column(children: [
        const SizedBox(height: 30),
        Text(_loadError!, style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo', fontSize: 13)),
        const SizedBox(height: 12),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.white),
          onPressed: _loadQuestions,
          child: const Text('נסה שוב', style: TextStyle(fontFamily: 'Heebo')),
        ),
      ]);
    }
    // Generating prompt
    if (_step == 2 && _generatingPrompt) {
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(height: 40),
        const CircularProgressIndicator(color: _kGold, strokeWidth: 2),
        const SizedBox(height: 12),
        Text('מייצר פרומפט מדויק...', style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 13)),
      ]);
    }
    // Step 1: Questions
    if (_step == 1) return _buildQuestionsStep();
    // Step 2: Edit prompt
    return _buildPromptStep();
  }

  Widget _buildQuestionsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Proposal mini-summary
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kGold.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kGold.withOpacity(0.2), width: 0.7),
          ),
          child: Text(
            widget.proposal['title']?.toString() ?? '',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13, color: _kGold),
          ),
        ),
        const SizedBox(height: 16),
        ...List.generate(_questions.length, (i) {
          final q = _questions[i];
          final qid   = q['id'] as String;
          final chips = List<String>.from(q['chips'] ?? []);
          final sel   = _answers[qid];
          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Question number + text
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(q['question']?.toString() ?? '',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13, color: JC.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 20, height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _kGold.withOpacity(0.15), shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Chips
                Wrap(
                  spacing: 6, runSpacing: 6,
                  textDirection: TextDirection.rtl,
                  children: chips.map((chip) {
                    final isSelected = sel == chip;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _answers[qid] = isSelected ? '' : chip;
                        if (!isSelected) _freeText[qid]?.clear();
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? _kGold.withOpacity(0.15) : JC.surfaceAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? _kGold : JC.border,
                            width: isSelected ? 1.2 : 0.7,
                          ),
                        ),
                        child: Text(chip,
                            style: TextStyle(
                                fontFamily: 'Heebo', fontSize: 12,
                                color: isSelected ? _kGold : JC.textSecondary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                // Free text (optional override)
                TextField(
                  controller: _freeText[qid],
                  textDirection: TextDirection.rtl,
                  onChanged: (_) => setState(() => _answers.remove(qid)),
                  style: const TextStyle(fontFamily: 'Heebo', fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'או כתוב בעצמך...',
                    hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 11.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: JC.border, width: 0.7)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: JC.border, width: 0.7)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kGold, width: 1.0)),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () => _generatePrompt(),
          icon: const Icon(Icons.auto_awesome, size: 15),
          label: const Text('צור פרומפט מדויק', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGold,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => _generatePrompt(skipQuestions: true),
          child: Text('דלג על שאלות', style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildPromptStep() {
    final isClaudeMode = widget.mode == 'claude';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ערוך את הפרומפט לפי הצורך:',
            textAlign: TextAlign.right,
            style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _promptCtrl,
          textDirection: TextDirection.rtl,
          maxLines: null,
          minLines: 8,
          style: const TextStyle(fontFamily: 'Heebo', fontSize: 12.5, height: 1.5),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: JC.border, width: 0.8)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: JC.border, width: 0.8)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kGold, width: 1.0)),
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _sending ? null : _confirm,
          icon: _sending
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(isClaudeMode ? Icons.open_in_new : Icons.task_alt_outlined, size: 16),
          label: Text(
            isClaudeMode ? 'שלח לקלוד' : 'שלח כמשימה',
            style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kGold,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Send-to-Claude bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _SendToClaudeSheet extends StatefulWidget {
  final String prompt;
  final String title;
  final String base;
  const _SendToClaudeSheet({required this.prompt, required this.title, required this.base});
  @override State<_SendToClaudeSheet> createState() => _SendToClaudeSheetState();
}

class _SendToClaudeSheetState extends State<_SendToClaudeSheet> {
  bool _askingJarvis = false;
  String? _jarvisReply;

  static const Color _kGold = Color(0xFFC9A84C);

  Future<void> _copyAndOpen() async {
    await Clipboard.setData(ClipboardData(text: widget.prompt));
    await launchUrl(Uri.parse('https://claude.ai'), mode: LaunchMode.externalApplication);
  }

  Future<void> _copyOnly() async {
    await Clipboard.setData(ClipboardData(text: widget.prompt));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('הועתק ללוח ✓', style: TextStyle(fontFamily: 'Heebo')),
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _askJarvis() async {
    setState(() { _askingJarvis = true; _jarvisReply = null; });
    try {
      final res = await http.post(
        Uri.parse('${widget.base}/ask-jarvis'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': widget.prompt, 'settings': {}}),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _jarvisReply = d['answer']?.toString() ?? 'אין תשובה');
      }
    } catch (_) {
      setState(() => _jarvisReply = 'שגיאת רשת — נסה שוב');
    } finally {
      setState(() => _askingJarvis = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGold.withOpacity(0.25), width: 0.8),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              // Title
              Row(children: [
                const Text('🤖', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  widget.title.isNotEmpty ? 'שלח לקלוד: ${widget.title}' : 'שלח לקלוד',
                  style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                )),
              ]),
              const SizedBox(height: 4),
              Text('בחר כיצד לשלוח את ההקשר לקלוד:',
                  style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Heebo', fontSize: 12)),
              const SizedBox(height: 16),
              // Option 1: Copy prompt
              _option(
                icon: Icons.copy_rounded,
                title: 'העתק Prompt ללוח',
                sub: 'מעתיק טקסט מוכן — הדבק ב-Claude.ai בעצמך',
                onTap: _copyOnly,
              ),
              const SizedBox(height: 8),
              // Option 2: Open Claude.ai
              _option(
                icon: Icons.open_in_browser_rounded,
                title: 'פתח ב-Claude.ai',
                sub: 'מעתיק + פותח Claude.ai בדפדפן',
                onTap: _copyAndOpen,
                highlight: true,
              ),
              const SizedBox(height: 8),
              // Option 3: Ask Jarvis inline
              _option(
                icon: Icons.auto_awesome_rounded,
                title: 'שאל את ג׳רביס',
                sub: 'מקבל תשובה ישירות כאן מהשרת',
                onTap: _askingJarvis ? null : _askJarvis,
                loading: _askingJarvis,
              ),
              // Jarvis reply
              if (_jarvisReply != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kGold.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kGold.withOpacity(0.2)),
                  ),
                  child: Text(_jarvisReply!,
                      style: TextStyle(color: Colors.grey.shade200, fontFamily: 'Heebo', fontSize: 13, height: 1.5)),
                ),
              ],
              // Prompt preview
              const SizedBox(height: 14),
              ExpansionTile(
                title: Text('צפה ב-Prompt', style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Heebo', fontSize: 11)),
                tilePadding: EdgeInsets.zero,
                iconColor: _kGold,
                collapsedIconColor: Colors.grey.shade500,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(widget.prompt,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70, height: 1.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option({required IconData icon, required String title, required String sub, required VoidCallback? onTap, bool highlight = false, bool loading = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: highlight ? _kGold.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlight ? _kGold.withOpacity(0.5) : Colors.grey.shade700, width: highlight ? 1.2 : 0.7),
        ),
        child: Row(children: [
          if (loading)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kGold))
          else
            Icon(icon, size: 20, color: highlight ? _kGold : Colors.grey.shade400),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: highlight ? _kGold : Colors.grey.shade200, fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13)),
            Text(sub, style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Heebo', fontSize: 11)),
          ])),
          Icon(Icons.chevron_left, size: 16, color: Colors.grey.shade600),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureDetailSheet extends StatefulWidget {
  final Map<String, dynamic> feature;
  final String currentStatus;
  final String base;
  final Future<bool> Function({required String name, required String oldStatus, required String newStatus, String? desc}) onPatch;
  final Future<bool> Function({required String name, required String status}) onDelete;
  final void Function(String prompt) onSendToClaud;
  final String Function(Map<String, dynamic>, String) featureToPrompt;
  final Future<String?> Function(String name, String status) onSuggestDesc;

  const _FeatureDetailSheet({
    required this.feature,
    required this.currentStatus,
    required this.base,
    required this.onPatch,
    required this.onDelete,
    required this.onSendToClaud,
    required this.featureToPrompt,
    required this.onSuggestDesc,
  });
  @override State<_FeatureDetailSheet> createState() => _FeatureDetailSheetState();
}

class _FeatureDetailSheetState extends State<_FeatureDetailSheet> {
  late String _status;
  late TextEditingController _descCtrl;
  bool _saving = false;
  bool _suggestingDesc = false;
  bool _deleting = false;
  bool _edited = false;

  static const Color _kGold = Color(0xFFC9A84C);

  final _statuses = [
    ('planned',  '📋 מתוכנן',  Color(0xFF6B7280)),
    ('building', '🔨 בבנייה', Color(0xFFF59E0B)),
    ('done',     '✅ הושלם',  Color(0xFF22C55E)),
  ];

  @override
  void initState() {
    super.initState();
    _status  = widget.currentStatus;
    _descCtrl = TextEditingController(text: widget.feature['desc']?.toString() ?? '');
    _descCtrl.addListener(() => setState(() => _edited = true));
  }

  @override
  void dispose() { _descCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.onPatch(
      name: widget.feature['name']?.toString() ?? '',
      oldStatus: widget.currentStatus,
      newStatus: _status,
      desc: _descCtrl.text.trim(),
    );
    if (mounted) {
      if (ok) Navigator.pop(context);
      else setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת יכולת', style: TextStyle(fontFamily: 'Heebo')),
          content: Text('למחוק את "${widget.feature['name']}"?', style: const TextStyle(fontFamily: 'Heebo')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('ביטול', style: TextStyle(fontFamily: 'Heebo'))),
            TextButton(onPressed: () => Navigator.pop(dCtx, true),
                child: const Text('מחק', style: TextStyle(color: Color(0xFFEF4444), fontFamily: 'Heebo'))),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final ok = await widget.onDelete(name: widget.feature['name']?.toString() ?? '', status: widget.currentStatus);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.feature['name']?.toString() ?? '—';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGold.withOpacity(0.25), width: 0.8),
        ),
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              // Name + delete
              Row(children: [
                Expanded(child: Text(name,
                    style: const TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700, fontSize: 17))),
                if (_deleting)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)))
                else
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                    onPressed: _confirmDelete,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
              const SizedBox(height: 14),
              // Status selector
              Text('סטטוס', style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(children: _statuses.map((t) {
                final (key, label, color) = t;
                final sel = _status == key;
                return Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => setState(() { _status = key; _edited = true; }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? color.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? color : Colors.grey.shade700, width: sel ? 1.2 : 0.6),
                      ),
                      child: Text(label, textAlign: TextAlign.center,
                          style: TextStyle(color: sel ? color : Colors.grey.shade500, fontFamily: 'Heebo', fontSize: 11)),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 14),
              // Description
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Text('תיאור', style: TextStyle(color: Colors.grey.shade500, fontFamily: 'Heebo', fontSize: 11, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _suggestingDesc ? null : () async {
                      setState(() => _suggestingDesc = true);
                      final name = widget.feature['name']?.toString() ?? '';
                      final suggestion = await widget.onSuggestDesc(name, _status);
                      if (mounted && suggestion != null) {
                        _descCtrl.text = suggestion;
                        setState(() => _edited = true);
                      }
                      if (mounted) setState(() => _suggestingDesc = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kGold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kGold.withOpacity(0.3), width: 0.7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_suggestingDesc)
                            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: _kGold))
                          else
                            const Text('🤖', style: TextStyle(fontSize: 10)),
                          const SizedBox(width: 4),
                          Text(_suggestingDesc ? 'מייצר...' : 'הצע תיאור',
                              style: const TextStyle(color: _kGold, fontFamily: 'Heebo', fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                textDirection: TextDirection.rtl,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'תיאור קצר של הפיצ\'ר...',
                  hintStyle: TextStyle(color: Colors.grey.shade600, fontFamily: 'Heebo', fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade700, width: 0.8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade700, width: 0.8)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kGold, width: 1.0)),
                ),
              ),
              const SizedBox(height: 16),
              // Action buttons
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final f = Map<String, dynamic>.from(widget.feature)..['desc'] = _descCtrl.text;
                      widget.onSendToClaud(widget.featureToPrompt(f, _status));
                    },
                    icon: const Icon(Icons.send_rounded, size: 14),
                    label: const Text('שלח לקלוד', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kGold,
                      side: BorderSide(color: _kGold.withOpacity(0.5), width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _edited && !_saving ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('שמור', style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// Helper for keyword-based question matching
class _TopicQs {
  final List<String> keys;
  final List<Map<String, dynamic>> qs;
  const _TopicQs({required this.keys, required this.qs});
}
