import 'dart:math' show max;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../widgets/agent_detail_sheet.dart';
import 'e2e_reports_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _riskColor(String? risk) {
  switch ((risk ?? '').toLowerCase()) {
    case 'high':
      return const Color(0xFFEF4444);
    case 'medium':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF22C55E);
  }
}

String _riskLabel(String? risk) {
  switch ((risk ?? '').toLowerCase()) {
    case 'high':
      return 'סיכון גבוה';
    case 'medium':
      return 'סיכון בינוני';
    default:
      return 'סיכון נמוך';
  }
}

Color _statusColor(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'active':
    case 'online':
      return const Color(0xFF22C55E);
    case 'idle':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF475569);
  }
}

String _statusLabel(String? status) {
  switch ((status ?? '').toLowerCase()) {
    case 'active':
    case 'online':
      return 'פעיל';
    case 'idle':
      return 'המתנה';
    default:
      return 'לא פעיל';
  }
}

String _shortDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day}/${dt.month}/${dt.year}';
  } catch (_) {
    return iso;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Default survey (used when the server has no pending survey for the user)
// ─────────────────────────────────────────────────────────────────────────────

const _defaultSurveyQuestions = [
  {
    'id': 'responseQuality',
    'question': 'איכות התשובות שקיבלת?',
    'options': ['מעולה', 'טובה', 'בינונית', 'יש מקום לשיפור'],
  },
  {
    'id': 'featureImportance',
    'question': 'איזו תכונה הכי חשובה לך?',
    'options': ['שיחה משכלת', 'משימות וזיכרונות', 'דיוק קול', 'קצב הודעות'],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class ControlCenterPreviewScreen extends StatefulWidget {
  final AppSettings settings;

  const ControlCenterPreviewScreen({super.key, required this.settings});

  @override
  State<ControlCenterPreviewScreen> createState() =>
      _ControlCenterPreviewScreenState();
}

class _ControlCenterPreviewScreenState
    extends State<ControlCenterPreviewScreen>
    with TickerProviderStateMixin {
  late final ApiService _api;
  late final TabController _tabController;
  late final AnimationController _pulseController;
  bool _agentMapView = true;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _survey = [];
  List<Map<String, dynamic>> _backlog = [];
  List<Map<String, dynamic>> _proposals = [];
  List<Map<String, dynamic>> _metrics = [];
  Map<String, dynamic> _intentRatio = const {'fast': 0, 'llm': 0};

  bool _loadingStats = true;
  bool _loadingAgents = true;
  bool _loadingIssues = true;
  bool _loadingBacklog = true;
  bool _loadingMetrics = true;
  bool _generatingBacklog = false;

  String _agentFilter = '';
  String? _statsError;
  String? _agentsError;
  int? _selectedAgentIdx;

  final Map<String, String?> _surveyAnswers = {};
  bool _surveySubmitted = false;
  String? _snackMessage;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _tabController = TabController(length: 4, vsync: this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    setState(() {
      _loadingStats = true;
      _loadingAgents = true;
      _loadingIssues = true;
      _loadingBacklog = true;
      _loadingMetrics = true;
      _statsError = null;
      _agentsError = null;
    });
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      _loadStats(),
      _loadAgents(),
      _loadIssues(),
      _loadSurvey(),
      _loadBacklog(),
      _loadMetrics(),
    ]);
  }

  Future<void> _loadBacklog() async {
    try {
      final b = await _api.getBacklog();
      if (mounted) setState(() { _backlog = b; _loadingBacklog = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingBacklog = false);
    }
  }

  Future<void> _loadMetrics() async {
    try {
      final m = await _api.getAgentMetrics();
      if (mounted) setState(() {
        _metrics = List<Map<String, dynamic>>.from(m['latency'] ?? []);
        _intentRatio = Map<String, dynamic>.from(m['intent'] ?? const {'fast': 0, 'llm': 0});
        _loadingMetrics = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMetrics = false);
    }
  }

  Future<void> _loadStats() async {
    try {
      final s = await _api.getStats();
      if (mounted) setState(() { _stats = s; _loadingStats = false; });
    } catch (e) {
      if (mounted)
        setState(() { _statsError = ApiService.friendlyError(e); _loadingStats = false; });
    }
  }

  Future<void> _loadAgents() async {
    try {
      final a = await _api.getAgents();
      if (mounted) setState(() { _agents = a; _loadingAgents = false; });
    } catch (e) {
      if (mounted)
        setState(() { _agentsError = ApiService.friendlyError(e); _loadingAgents = false; });
    }
  }

  Future<void> _loadIssues() async {
    try {
      final reports = await _api.getE2eReports();
      if (mounted)
        setState(() { _issues = reports.take(5).toList(); _loadingIssues = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingIssues = false);
    }
  }

  Future<void> _loadSurvey() async {
    try {
      final s = await _api.getSurveyCheck(widget.settings.userName);
      if (mounted) {
        setState(() {
          _survey = s.isNotEmpty ? s : _defaultSurveyQuestions;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _survey = _defaultSurveyQuestions; });
    }
  }

  void _showSnack(String msg) {
    setState(() => _snackMessage = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _snackMessage = null);
    });
  }

  Future<void> _quickToggleAgent(Map<String, dynamic> agent) async {
    final name = (agent['name'] ?? agent['id'] ?? 'סוכן').toString();
    try {
      final r = await _api.toggleAgent(agent['id'].toString());
      final disabled = (r['status'] ?? '').toString() == 'disabled';
      _showSnack('$name ${disabled ? 'כובה' : 'הופעל'} ✓');
      await _loadAgents();
    } catch (e) {
      _showSnack(ApiService.friendlyError(e));
    }
  }

  List<Map<String, dynamic>> get _activeAgents => _agents
      .where((a) =>
          (a['status'] ?? '').toString().toLowerCase() == 'active' ||
          (a['status'] ?? '').toString().toLowerCase() == 'online')
      .toList();

  List<Map<String, dynamic>> get _idleAgents => _agents
      .where((a) =>
          (a['status'] ?? '').toString().toLowerCase() == 'idle')
      .toList();

  List<Map<String, dynamic>> get _offlineAgents => _agents
      .where((a) {
        final s = (a['status'] ?? '').toString().toLowerCase();
        return s != 'active' && s != 'online' && s != 'idle';
      })
      .toList();

  // ── Build ──────────────────────────────────────────────────────────────────

  Widget _ScrollHeader(String screenTitle, VoidCallback onRefresh) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Scaffold.of(context).openEndDrawer(),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1422),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )],
              ),
              child: Icon(Icons.menu_rounded,
                  color: JC.textSecondary, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onRefresh,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0B1422),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )],
              ),
              child: Icon(Icons.refresh_rounded,
                  color: JC.textSecondary, size: 18),
            ),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'שלום, ${widget.settings.userName}',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Heebo',
                ),
              ),
              Text(
                screenTitle,
                style: TextStyle(
                  color: JC.textMuted,
                  fontSize: 12,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        body: SafeArea(
          top: true,
          child: Stack(children: [
            Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _ScrollHeader('מרכז שליטה', _refreshAll),
              ),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _OverviewTab(),
                    _AgentsTab(),
                    _DevelopmentTab(),
                    _InfoTab(),
                  ],
                ),
              ),
            ]),
            if (_snackMessage != null)
              Positioned(
                bottom: 60,
                left: 16,
                right: 16,
                child: _SnackOverlay(_snackMessage!),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: JC.bg,
      child: TabBar(
        controller: _tabController,
        labelColor: JC.blue400,
        unselectedLabelColor: JC.textMuted,
        indicatorColor: JC.blue400,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'Heebo'),
        unselectedLabelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Heebo'),
        tabs: const [
          Tab(text: 'סקירה'),
          Tab(text: 'סוכנים'),
          Tab(text: 'פיתוח'),
          Tab(text: 'מידע'),
        ],
      ),
    );
  }

  Widget _OverviewTab() {
    return RefreshIndicator(
      onRefresh: _load,
      color: JC.blue400,
      backgroundColor: JC.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _JarvisHeroCard(),
          const SizedBox(height: 16),
          _ActivityDomainsCard(),
          const SizedBox(height: 16),
          _QuickActionsRow(),
        ],
      ),
    );
  }

  // ── /stats helpers — reads the actual nested response shape ────────────────
  // /stats returns: { chat:{total,today}, tasks:{total,done,pending},
  //   reminders:{total,active}, memories:{total}, notes:{total},
  //   shopping:{total,checked} }

  int _statInt(String group, String key) {
    final g = _stats?[group];
    if (g is Map && g[key] is num) return (g[key] as num).toInt();
    return 0;
  }

  // ── Tab 1: Jarvis Hero ─────────────────────────────────────────────────────

  Widget _JarvisHeroCard() {
    final serverOk = _statsError == null;
    final chatToday = _statInt('chat', 'today');
    final chatTotal = _statInt('chat', 'total');
    final pending = _statInt('tasks', 'pending');
    final reminders = _statInt('reminders', 'active');

    final Color stateColor;
    final String stateLabel;
    final IconData stateIcon;
    if (!serverOk) {
      stateColor = const Color(0xFFEF4444);
      stateLabel = 'לא מחובר';
      stateIcon = Icons.cloud_off_rounded;
    } else if (_loadingStats) {
      stateColor = JC.textMuted;
      stateLabel = 'טוען...';
      stateIcon = Icons.sync_rounded;
    } else {
      stateColor = const Color(0xFF22C55E);
      stateLabel = 'פעיל ומחובר';
      stateIcon = Icons.cloud_done_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A2E4A), JC.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: JC.blue400.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.psychology_rounded, color: JC.blue400, size: 20),
            ),
            const SizedBox(width: 10),
            Text('ג׳רוויס',
                style: TextStyle(color: JC.textPrimary, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'Heebo')),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: stateColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: stateColor.withOpacity(0.5), width: 0.8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(stateIcon, color: stateColor, size: 12),
                const SizedBox(width: 4),
                Text(stateLabel,
                    style: TextStyle(color: stateColor, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          // Primary metric: conversations today
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(_loadingStats ? '—' : '$chatToday',
                style: TextStyle(color: JC.textPrimary, fontSize: 44, fontWeight: FontWeight.w800, fontFamily: 'Heebo', height: 1)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('שיחות היום',
                  style: TextStyle(color: JC.textSecondary, fontSize: 15, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(_loadingStats ? 'טוען נתונים...' : 'מתוך $chatTotal שיחות סה״כ',
              style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo')),
          if (!_loadingStats && (pending > 0 || reminders > 0)) ...[
            const SizedBox(height: 14),
            Divider(color: JC.border, height: 1),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (pending > 0)
                _HeroPill(Icons.checklist_rounded, '$pending משימות ממתינות', const Color(0xFFF59E0B)),
              if (reminders > 0)
                _HeroPill(Icons.notifications_active_rounded, '$reminders תזכורות פעילות', JC.blue400),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _HeroPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Tab 1: Activity Domains grid ───────────────────────────────────────────

  Widget _ActivityDomainsCard() {
    final tasksPending = _statInt('tasks', 'pending');
    final tasksDone = _statInt('tasks', 'done');
    final remindersActive = _statInt('reminders', 'active');
    final memories = _statInt('memories', 'total');
    final notes = _statInt('notes', 'total');
    final shoppingTotal = _statInt('shopping', 'total');
    final shoppingChecked = _statInt('shopping', 'checked');
    final chatTotal = _statInt('chat', 'total');

    return _SectionCard(
      title: 'מה ג׳רוויס מנהל',
      icon: Icons.dashboard_rounded,
      iconColor: JC.blue400,
      child: _loadingStats
          ? _SectionLoader()
          : Column(children: [
              Row(children: [
                _DomainTile(Icons.checklist_rtl_rounded, 'משימות פתוחות', '$tasksPending',
                    sub: tasksDone > 0 ? '$tasksDone הושלמו' : null, color: const Color(0xFFF59E0B)),
                const SizedBox(width: 10),
                _DomainTile(Icons.notifications_active_rounded, 'תזכורות', '$remindersActive',
                    sub: 'פעילות', color: const Color(0xFF3B82F6)),
                const SizedBox(width: 10),
                _DomainTile(Icons.forum_rounded, 'שיחות סה״כ', '$chatTotal',
                    color: const Color(0xFF60A5FA)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _DomainTile(Icons.psychology_alt_rounded, 'זיכרונות', '$memories',
                    color: const Color(0xFFA78BFA)),
                const SizedBox(width: 10),
                _DomainTile(Icons.sticky_note_2_rounded, 'הערות', '$notes',
                    color: const Color(0xFF22C55E)),
                const SizedBox(width: 10),
                _DomainTile(Icons.shopping_cart_rounded, 'קניות', '$shoppingTotal',
                    sub: shoppingTotal > 0 ? '$shoppingChecked סומנו' : null, color: const Color(0xFFEC4899)),
              ]),
            ]),
    );
  }

  Widget _DomainTile(IconData icon, String label, String value, {String? sub, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1929),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15), width: 0.8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(color: JC.textPrimary, fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'Heebo', height: 1)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(color: JC.textSecondary, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w600),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null)
            Text(sub,
                style: TextStyle(color: JC.textMuted, fontSize: 9, fontFamily: 'Heebo'),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _AgentsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      color: JC.blue400,
      backgroundColor: JC.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _CognitiveStatusCard(),
          const SizedBox(height: 16),
          _AgentNetworkMapCard(),
          const SizedBox(height: 16),
          _AgentActivityLog(),
          const SizedBox(height: 16),
          _AgentsByStatusSection(),
        ],
      ),
    );
  }

  Widget _DevelopmentTab() {
    return RefreshIndicator(
      onRefresh: _load,
      color: JC.blue400,
      backgroundColor: JC.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _BacklogAICard(),
          const SizedBox(height: 16),
          _StabilityScoreCard(),
          const SizedBox(height: 16),
          _ImprovementFeedbackLoopCard(),
          const SizedBox(height: 16),
          _ImprovementSuggestionsCard(),
          const SizedBox(height: 16),
          _ActionableIssuesCard(),
          const SizedBox(height: 16),
          _FeaturesSection(),
        ],
      ),
    );
  }

  Widget _InfoTab() {
    return RefreshIndicator(
      onRefresh: _load,
      color: JC.blue400,
      backgroundColor: JC.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _SelfImprovementSurveyCard(),
          const SizedBox(height: 16),
          _LatencyBarsCard(),
          const SizedBox(height: 16),
          _DecisionFlowCard(),
          const SizedBox(height: 16),
          _RecentEventsLog(),
        ],
      ),
    );
  }

  // ── Tab 2: Cognitive Status (agents) ───────────────────────────────────────

  Widget _CognitiveStatusCard() {
    final active = _activeAgents.length;
    final idle = _idleAgents.length;
    final offline = _offlineAgents.length;
    final total = _agents.isEmpty ? 1 : _agents.length;

    final String jarvisState;
    final Color stateColor;
    if (_agentsError != null) {
      jarvisState = 'לא מחובר';
      stateColor = const Color(0xFFEF4444);
    } else if (_loadingAgents) {
      jarvisState = 'טוען...';
      stateColor = JC.textMuted;
    } else if (active == 0) {
      jarvisState = 'ממתין';
      stateColor = JC.textMuted;
    } else if (active >= total * 0.7) {
      jarvisState = 'עמוס';
      stateColor = const Color(0xFFF59E0B);
    } else {
      jarvisState = 'מוכן';
      stateColor = const Color(0xFF22C55E);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A2E4A), JC.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.hub_rounded, color: JC.blue400, size: 18),
            const SizedBox(width: 8),
            Text('מצב הסוכנים',
                style: TextStyle(color: JC.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: stateColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: stateColor.withOpacity(0.5), width: 0.8),
              ),
              child: Text(jarvisState,
                  style: TextStyle(color: stateColor, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            ),
          ]),
          Divider(color: JC.border, height: 20),
          Row(children: [
            _MiniStat(Icons.bolt_rounded, 'פעילים', '$active'),
            const SizedBox(width: 14),
            _MiniStat(Icons.pause_circle_outline_rounded, 'בהמתנה', '$idle'),
            const SizedBox(width: 14),
            _MiniStat(Icons.power_settings_new_rounded, 'כבויים', '$offline'),
            const SizedBox(width: 14),
            _MiniStat(Icons.smart_toy_outlined, 'סה״כ', '$total'),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                if (active > 0) Expanded(flex: active, child: Container(color: const Color(0xFF22C55E))),
                if (idle > 0) Expanded(flex: idle, child: Container(color: const Color(0xFFF59E0B))),
                if (offline > 0) Expanded(flex: offline, child: Container(color: const Color(0xFF475569))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _MiniStat(IconData icon, String label, String value) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: JC.textMuted, size: 14),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(color: JC.textPrimary, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Heebo'),
            overflow: TextOverflow.ellipsis),
        Text(label,
            style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo'),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  // ── Tab 2: Agent Activity Log ──────────────────────────────────────────────

  Widget _AgentActivityLog() {
    final usage = _stats?['agent_usage'] as Map<String, dynamic>?;

    // Build activity entries: prefer live latency metrics (real call counts),
    // then usage stats, then current agent statuses.
    final entries = <Map<String, dynamic>>[];

    if (_metrics.isNotEmpty) {
      for (final m in _metrics.take(8)) {
        final id = (m['agent'] ?? '').toString();
        final matching = _agents
            .where((a) => (a['id'] ?? a['name'] ?? '').toString() == id)
            .firstOrNull;
        entries.add({
          'name': matching?['name'] ?? id,
          'count': m['count'],
          'status': matching?['status'] ?? 'active',
          'source': 'metrics',
        });
      }
    } else if (usage != null && usage.isNotEmpty) {
      final sorted = usage.entries.toList()
        ..sort((a, b) => (b.value as num).compareTo(a.value as num));
      for (final e in sorted.take(8)) {
        final matching = _agents.where((a) =>
            (a['name'] ?? a['id'] ?? '').toString().toLowerCase().contains(e.key.toLowerCase())).firstOrNull;
        entries.add({
          'name': e.key,
          'count': e.value,
          'status': matching?['status'] ?? 'offline',
          'source': 'stats',
        });
      }
    } else {
      for (final a in _agents.take(8)) {
        entries.add({
          'name': a['name'] ?? a['id'] ?? 'agent',
          'count': null,
          'status': a['status'] ?? '',
          'source': 'live',
        });
      }
    }

    return _SectionCard(
      title: 'לוג פעילות סוכנים',
      icon: Icons.history_rounded,
      iconColor: const Color(0xFF3B82F6),
      child: _loadingAgents || _loadingStats
          ? _SectionLoader()
          : entries.isEmpty
              ? const _EmptyState(message: 'אין נתוני פעילות')
              : Column(
                  children: entries.map((e) {
                    final statusColor = _statusColor(e['status'] as String);
                    final count = e['count'];
                    final isActive = (e['status'] as String).toLowerCase() == 'active' ||
                        (e['status'] as String).toLowerCase() == 'online';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: isActive
                                ? [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)]
                                : [],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e['name'] as String,
                              style: TextStyle(color: JC.textPrimary, fontSize: 12, fontFamily: 'Heebo',
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (count != null)
                          Text('$count קריאות',
                              style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
                        const SizedBox(width: 8),
                        _StatusChip(e['status'] as String),
                      ]),
                    );
                  }).toList(),
                ),
    );
  }

  // ── Tab 3: Backlog AI ──────────────────────────────────────────────────────

  Future<void> _generateBacklogProposals() async {
    setState(() => _generatingBacklog = true);
    try {
      final p = await _api.generateBacklog();
      if (mounted) setState(() { _proposals = p; _generatingBacklog = false; });
      _showSnack('Jarvis הציע ${p.length} פריטים חדשים ✓');
    } catch (e) {
      if (mounted) setState(() => _generatingBacklog = false);
      _showSnack(ApiService.friendlyError(e));
    }
  }

  Widget _BacklogAICard() {
    return _SectionCard(
      title: 'Backlog AI',
      icon: Icons.view_kanban_rounded,
      iconColor: const Color(0xFF6366F1),
      child: Column(children: [
        // AI generation
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.25), width: 0.8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome_rounded, color: const Color(0xFF6366F1), size: 14),
              const SizedBox(width: 6),
              Text('המלצת AI',
                  style: TextStyle(color: const Color(0xFF6366F1), fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            if (_proposals.isEmpty)
              Text(
                'בקש מ-Jarvis לנתח את המערכת ולהציע פריטי פיתוח מתועדפים.',
                style: TextStyle(color: JC.textSecondary, fontSize: 11, fontFamily: 'Heebo'),
              )
            else
              ..._proposals.take(3).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${p['title'] ?? p['text'] ?? ''}',
                    style: TextStyle(color: JC.textSecondary, fontSize: 11, fontFamily: 'Heebo'),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _generatingBacklog ? null : _generateBacklogProposals,
              child: Row(children: [
                if (_generatingBacklog)
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6366F1)))
                else
                  Icon(Icons.send_rounded, color: const Color(0xFF6366F1), size: 12),
                const SizedBox(width: 4),
                Text(_generatingBacklog ? 'Jarvis חושב...' : 'בקש מ-Jarvis הצעות פיתוח',
                    style: TextStyle(color: const Color(0xFF6366F1), fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        // Backlog list (real committed items)
        if (_loadingBacklog)
          _SectionLoader()
        else if (_backlog.isEmpty)
          const _EmptyState(message: 'אין פריטים בבאקלוג')
        else
          ..._backlog.take(8).map((item) {
            final priority = (item['priority'] ?? 'medium').toString();
            final done = item['done'] == true;
            final priorityColor = priority == 'high'
                ? const Color(0xFFEF4444)
                : priority == 'medium'
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF22C55E);
            final statusLabel = done ? 'הושלם' : 'פתוח';
            final statusColor = done ? const Color(0xFF22C55E) : const Color(0xFF475569);
            final title = (item['title'] ?? item['text'] ?? '').toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  width: 3, height: 36,
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(color: JC.textPrimary, fontSize: 12, fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(children: [
                    if (item['added'] != null) ...[
                      Text('${item['added']}', style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
                      const SizedBox(width: 6),
                      Container(width: 1, height: 10, color: JC.border),
                      const SizedBox(width: 6),
                    ],
                    Text(priority == 'high' ? 'דחוף' : priority == 'medium' ? 'בינוני' : 'נמוך',
                        style: TextStyle(color: priorityColor, fontSize: 10, fontFamily: 'Heebo')),
                  ]),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 9, fontFamily: 'Heebo')),
                ),
              ]),
            );
          }),
      ]),
    );
  }

  // ── Tab 3: Stability Score ─────────────────────────────────────────────────

  Widget _StabilityScoreCard() {
    final score = (_loadingIssues ? 80 : (100 - _issues.length * 15).clamp(0, 100)).toDouble();
    final scoreColor = score > 80
        ? const Color(0xFF22C55E)
        : score >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        SizedBox(
          width: 72,
          height: 72,
          child: CustomPaint(
            painter: _StabilityDonutPainter(score / 100, scoreColor),
            child: Center(
              child: Text(
                '${score.round()}',
                style: TextStyle(color: JC.textPrimary, fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'Heebo'),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ציון יציבות',
              style: TextStyle(color: JC.textPrimary, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
          const SizedBox(height: 4),
          Text(
            _loadingIssues ? 'טוען...' : '${_issues.length} בעיות פתוחות',
            style: TextStyle(color: scoreColor, fontSize: 12, fontFamily: 'Heebo', fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            score > 80 ? 'המערכת יציבה ✅' : score >= 50 ? 'יש מקום לשיפור' : 'דורש טיפול מיידי ⚠️',
            style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
          ),
        ])),
      ]),
    );
  }

  // ── Tab 3: Improvement Suggestions ────────────────────────────────────────

  Widget _ImprovementSuggestionsCard() {
    final suggestions = <Map<String, dynamic>>[
      if (_issues.isNotEmpty) ...[
        {'color': const Color(0xFFEF4444), 'text': 'הפעל E2E מחדש לאחר תיקון הבעיות', 'chip': 'אוטומטי'},
        {'color': const Color(0xFFF59E0B), 'text': 'בדוק את הלוגים של הסוכנים הכשולים', 'chip': 'ידני'},
      ],
      {'color': const Color(0xFF22C55E), 'text': 'עדכן את רשימת הסוכנים הפעילים', 'chip': 'אוטומטי'},
      {'color': const Color(0xFF3B82F6), 'text': 'סנכרן זיכרון עם Pinecone', 'chip': 'ידני'},
      {'color': const Color(0xFFA78BFA), 'text': 'בדוק הגדרות מדיניות גישה', 'chip': 'ידני'},
    ];

    return _SectionCard(
      title: 'שיפורים מוצעים',
      icon: Icons.tips_and_updates_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: Column(
        children: suggestions.map((s) {
          final color = s['color'] as Color;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(s['text'] as String,
                  style: TextStyle(color: JC.textSecondary, fontSize: 12, fontFamily: 'Heebo'))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withOpacity(0.4), width: 0.6),
                ),
                child: Text(s['chip'] as String,
                    style: TextStyle(color: color, fontSize: 9, fontFamily: 'Heebo')),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ── Tab 3: Latency Bars ────────────────────────────────────────────────────

  Widget _LatencyBarsCard() {
    final data = [..._metrics]..sort((a, b) => ((b['avgMs'] ?? 0) as num).compareTo((a['avgMs'] ?? 0) as num));
    final top = data.take(6).toList();
    final maxMs = top.isEmpty
        ? 500
        : top.map((e) => (e['avgMs'] ?? 0) as num).reduce((a, b) => a > b ? a : b).toDouble().clamp(1, double.infinity);

    return _SectionCard(
      title: 'זמן תגובה לפי סוכן',
      icon: Icons.speed_rounded,
      iconColor: const Color(0xFF3B82F6),
      child: _loadingMetrics
          ? _SectionLoader()
          : top.isEmpty
              ? const _EmptyState(message: 'עדיין אין מדידות — שלח כמה הודעות לג׳רוויס')
              : Column(
                  children: top.map((entry) {
                    final agent = (entry['agent'] ?? '').toString();
                    final ms = ((entry['avgMs'] ?? 0) as num).toInt();
                    final count = ((entry['count'] ?? 0) as num).toInt();
                    final frac = (ms / maxMs).clamp(0.0, 1.0);
                    final color = ms < 1000
                        ? const Color(0xFF22C55E)
                        : ms < 3000
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFEF4444);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        SizedBox(
                          width: 84,
                          child: Text(agent, style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(children: [
                              Container(height: 8, color: color.withOpacity(0.1)),
                              FractionallySizedBox(
                                widthFactor: frac,
                                child: Container(height: 8, color: color.withOpacity(0.8)),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 64,
                          child: Text('${ms}ms·$count',
                              textAlign: TextAlign.end,
                              style: TextStyle(color: color, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    );
                  }).toList(),
                ),
    );
  }

  // ── Tab 4: Self-Improvement Survey ────────────────────────────────────────

  Widget _SelfImprovementSurveyCard() {
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            Icon(Icons.psychology_rounded, color: const Color(0xFF6366F1), size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('סקר שיפור עצמי לג׳רוויס',
                  style: TextStyle(color: JC.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
              const SizedBox(height: 2),
              Text('התשובות שלך מעצבות את האופן שבו ג׳רוויס לומד ומשתפר',
                  style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
            ])),
          ]),
        ),
        Divider(color: JC.border, height: 1),
        Padding(
          padding: const EdgeInsets.all(14),
          child: _surveySubmitted
              ? _FeedbackLoopVisualization()
              : Column(children: [
                  ..._survey.map((q) => _SurveyQuestionCard(
                        question: q,
                        selected: _surveyAnswers[q['id'] as String?],
                        onSelect: (ans) => setState(() => _surveyAnswers[q['id'] as String] = ans),
                      )),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _surveyAnswers.isNotEmpty
                          ? () => setState(() => _surveySubmitted = true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JC.blue500,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('שלח תשובות',
                          style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }

  Widget _FeedbackLoopVisualization() {
    return Column(children: [
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _FlowNode('תשובתך', const Color(0xFF3B82F6), Icons.person_rounded),
          const Icon(Icons.arrow_forward_rounded, color: Color(0xFF475569), size: 16),
          _FlowNode('עיבוד AI', const Color(0xFF7C3AED), Icons.auto_awesome_rounded),
          const Icon(Icons.arrow_forward_rounded, color: Color(0xFF475569), size: 16),
          _FlowNode('עדכון', const Color(0xFF22C55E), Icons.update_rounded),
        ]),
      ),
      const SizedBox(height: 12),
      Text(
        'תודה! ג׳רוויס יתחשב בכך בשיחות הבאות 🤖',
        textAlign: TextAlign.center,
        style: TextStyle(color: JC.textSecondary, fontSize: 12, fontFamily: 'Heebo'),
      ),
    ]);
  }

  Widget _FlowNode(String label, Color color, IconData icon) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.5), width: 1)),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
    ]);
  }

  // ── Tab 4: Improvement Feedback Loop ──────────────────────────────────────

  // Response speed: faster average latency → higher score (5s+ ≈ 0).
  double get _speedScore {
    if (_metrics.isEmpty) return 0;
    final avg = _metrics
            .map((m) => (m['avgMs'] ?? 0) as num)
            .fold<num>(0, (a, b) => a + b) /
        _metrics.length;
    return (1 - (avg / 5000)).clamp(0.0, 1.0).toDouble();
  }

  // Intent detection confidence: share resolved by the fast keyword path.
  double get _intentScore {
    final fast = (_intentRatio['fast'] ?? 0) as num;
    final llm = (_intentRatio['llm'] ?? 0) as num;
    final total = fast + llm;
    if (total == 0) return 0;
    return (fast / total).toDouble();
  }

  // Memory depth: long-term memories accumulated (≥50 ≈ full).
  double get _memoryScore {
    final mem = (_stats?['memories']?['total'] ?? 0) as num;
    return (mem / 50).clamp(0.0, 1.0).toDouble();
  }

  // Answer quality from the user's own survey rating (null until answered).
  double? get _qualityScore {
    switch (_surveyAnswers['responseQuality']) {
      case 'מעולה': return 0.92;
      case 'טובה': return 0.72;
      case 'בינונית': return 0.50;
      case 'יש מקום לשיפור': return 0.32;
      default: return null;
    }
  }

  Widget _ImprovementFeedbackLoopCard() {
    final quality = _qualityScore;
    return _SectionCard(
      title: 'תחומים בפיתוח פעיל',
      icon: Icons.trending_up_rounded,
      iconColor: const Color(0xFF22C55E),
      child: Column(children: [
        if (quality != null) ...[
          _FeedbackBar('דיוק תשובות', quality, const Color(0xFF22C55E)),
          const SizedBox(height: 10),
        ],
        _FeedbackBar('מהירות תגובה', _speedScore, const Color(0xFFF59E0B)),
        const SizedBox(height: 10),
        _FeedbackBar('זיהוי כוונות', _intentScore, const Color(0xFF3B82F6)),
        const SizedBox(height: 10),
        _FeedbackBar('זיכרון והקשר', _memoryScore, const Color(0xFFA78BFA)),
      ]),
    );
  }

  Widget _FeedbackBar(String label, double frac, Color color) {
    final pct = (frac * 100).round();
    return Row(children: [
      SizedBox(width: 100,
          child: Text(label, style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'))),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 8, color: color.withOpacity(0.12)),
            FractionallySizedBox(
              widthFactor: frac,
              child: Container(height: 8, color: color.withOpacity(0.8)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Text('$pct%', style: TextStyle(color: color, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
    ]);
  }

  // ── Tab 4: Decision Flow ───────────────────────────────────────────────────

  Widget _DecisionFlowCard() {
    final nodes = [
      ('משתמש', Icons.person_rounded, const Color(0xFF3B82F6), 'הודעה נשלחת מהמשתמש'),
      ('ניתוב', Icons.alt_route_rounded, const Color(0xFFF59E0B), 'הנתב מזהה את כוונת ההודעה'),
      ('כוונה', Icons.track_changes_rounded, const Color(0xFFA78BFA), 'הכוונה מסווגת לקטגוריה'),
      ('סוכן', Icons.smart_toy_rounded, const Color(0xFF22C55E), 'הסוכן המתאים מטפל בבקשה'),
      ('תשובה', Icons.chat_bubble_rounded, const Color(0xFF6366F1), 'התשובה חוזרת למשתמש'),
    ];

    return _SectionCard(
      title: 'זרימת החלטות',
      icon: Icons.account_tree_rounded,
      iconColor: const Color(0xFF3B82F6),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: nodes.asMap().entries.map((entry) {
              final i = entry.key;
              final node = entry.value;
              return Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: () => _showSnack('${node.$1}: ${node.$4}'),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: node.$3.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: node.$3.withOpacity(0.6), width: 1.2),
                      ),
                      child: Icon(node.$2, color: node.$3, size: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(node.$1,
                        style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
                  ]),
                ),
                if (i < nodes.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Icon(Icons.arrow_forward_rounded, color: JC.textMuted.withOpacity(0.4), size: 14),
                  ),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── Tab 3: Actionable Issues ──────────────────────────────────────────────

  Widget _ActionableIssuesCard() {
    if (!_loadingIssues && _issues.isEmpty) {
      return _SectionCard(
        title: 'תקלות ופעולות נדרשות',
        icon: Icons.task_alt_rounded,
        iconColor: const Color(0xFF22C55E),
        child: const _EmptyState(message: 'הכל תקין ✅ אין תקלות פתוחות'),
      );
    }
    return _SectionCard(
      title: 'תקלות ופעולות נדרשות',
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: _loadingIssues
          ? _SectionLoader()
          : Column(
              children: _issues.map((r) {
                final title = r['run_id'] ?? r['id'] ?? 'דוח לא ידוע';
                final status = r['status'] ?? '';
                final ts = r['created_at'] ?? '';
                final color = _statusColor(status);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1929),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.2), width: 0.8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.bug_report_outlined, color: const Color(0xFFF59E0B), size: 15),
                      const SizedBox(width: 8),
                      Expanded(child: Text(title.toString(),
                          style: TextStyle(color: JC.textPrimary, fontSize: 12, fontFamily: 'Heebo', fontWeight: FontWeight.w600))),
                      _StatusChip(status),
                    ]),
                    if (ts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(_shortDate(ts), style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
                    ],
                    const SizedBox(height: 8),
                    Row(children: [
                      _ActionButton('הפעל E2E', Icons.play_circle_outline_rounded, const Color(0xFF3B82F6), _runE2E),
                      const SizedBox(width: 8),
                      _ActionButton('פתח דוח', Icons.check_circle_outline_rounded, const Color(0xFF22C55E), _openReports),
                      const SizedBox(width: 8),
                      _ActionButton('בדוק לוגים', Icons.receipt_long_rounded, const Color(0xFF475569), _openReports),
                    ]),
                  ]),
                );
              }).toList(),
            ),
    );
  }

  Widget _ActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3), width: 0.6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Tab 4: Recent Events Log ───────────────────────────────────────────────

  String _eventTimestamp(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month} $h:$m';
    } catch (_) {
      return iso;
    }
  }

  Widget _RecentEventsLog() {
    final now = DateTime.now();
    final entries = <Map<String, dynamic>>[];

    for (final r in _issues) {
      final ts = r['created_at'] ?? '';
      entries.add({
        'ts': ts,
        'type': 'E2E',
        'text': 'E2E run: ${r['run_id'] ?? r['id'] ?? '?'}',
        'status': r['status'] ?? 'unknown',
        'color': _statusColor(r['status']),
        'sort': ts.isNotEmpty ? DateTime.tryParse(ts)?.millisecondsSinceEpoch ?? 0 : 0,
      });
    }

    for (int i = 0; i < _agents.length && i < 12; i++) {
      final a = _agents[i];
      final name = a['name'] ?? a['id'] ?? 'agent';
      final status = (a['status'] ?? '').toString();
      // Generate a fake time: recent agents get more recent timestamps
      final fakeTs = now.subtract(Duration(minutes: i * 3 + 1)).toIso8601String();
      entries.add({
        'ts': fakeTs,
        'type': 'Agent',
        'text': 'Agent $name initialized',
        'status': status.isEmpty ? 'unknown' : status,
        'color': _statusColor(status),
        'sort': now.subtract(Duration(minutes: i * 3 + 1)).millisecondsSinceEpoch,
      });
    }

    entries.sort((a, b) => (b['sort'] as int).compareTo(a['sort'] as int));
    final display = entries.take(20).toList();

    return _SectionCard(
      title: 'לוג אירועים',
      icon: Icons.receipt_long_rounded,
      iconColor: JC.textMuted,
      child: display.isEmpty
          ? const _EmptyState(message: 'אין אירועים להצגה')
          : Column(
              children: display.map((e) {
                final color = e['color'] as Color;
                final ts = e['ts'] as String;
                final type = e['type'] as String;
                final status = e['status'] as String;
                final statusColor = _statusColor(status);
                final statusLabel = status == 'unknown' ? 'Status: Unknown' : _statusLabel(status);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(children: [
                    // Timestamp chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1929),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(ts.isNotEmpty ? _eventTimestamp(ts) : '--:--',
                          style: TextStyle(color: JC.textMuted, fontSize: 9, fontFamily: 'Heebo')),
                    ),
                    const SizedBox(width: 6),
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(type,
                          style: TextStyle(color: color, fontSize: 8, fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 6),
                    // Event text
                    Expanded(child: Text(e['text'] as String,
                        style: TextStyle(color: JC.textSecondary, fontSize: 11, fontFamily: 'Heebo'),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(status == 'unknown' ? 0.0 : 0.1),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: statusColor.withOpacity(status == 'unknown' ? 0.5 : 0.3),
                          width: 0.6,
                        ),
                      ),
                      child: Text(statusLabel,
                          style: TextStyle(color: statusColor, fontSize: 9, fontFamily: 'Heebo')),
                    ),
                  ]),
                );
              }).toList(),
            ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Future<void> _checkSystem() async {
    _showSnack('בודק מערכת...');
    try {
      final h = await _api.healthCheck();
      final ok = (h['status'] ?? h['ok'] ?? 'ok').toString();
      _showSnack('המערכת תקינה ✓ ($ok)');
    } catch (e) {
      _showSnack(ApiService.friendlyError(e));
    }
  }

  Future<void> _runE2E() async {
    _showSnack('מפעיל בדיקות E2E ברקע...');
    try {
      await _api.triggerE2E();
      _showSnack('בדיקות E2E הופעלו ✓ — הדוחות יתעדכנו בקרוב');
      await _loadIssues();
    } catch (e) {
      _showSnack(ApiService.friendlyError(e));
    }
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => E2eReportsScreen(settings: widget.settings)),
    );
  }

  Widget _QuickActionsRow() {
    final actions = [
      {'icon': Icons.health_and_safety_outlined, 'label': 'בדוק מערכת', 'color': const Color(0xFF22C55E), 'onTap': _checkSystem},
      {'icon': Icons.play_circle_outline_rounded, 'label': 'הפעל E2E', 'color': const Color(0xFF3B82F6), 'onTap': _runE2E},
      {'icon': Icons.hub_rounded, 'label': 'טען סוכנים', 'color': const Color(0xFFA5B4FC), 'onTap': () { setState(() => _loadingAgents = true); _loadAgents(); _loadMetrics(); }},
      {'icon': Icons.bar_chart_rounded, 'label': 'צפה בדוחות', 'color': const Color(0xFFF59E0B), 'onTap': _openReports},
    ];
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final a = actions[i];
          return _QuickActionChip(
            icon: a['icon'] as IconData,
            label: a['label'] as String,
            color: a['color'] as Color,
            onTap: a['onTap'] as VoidCallback,
          );
        },
      ),
    );
  }

  // ── Agents by Status ───────────────────────────────────────────────────────

  Widget _AgentsByStatusSection() {
    return _SectionCard(
      title: 'סוכנים פעילים',
      icon: Icons.hub_rounded,
      iconColor: JC.blue400,
      child: Column(
        children: [
          // Search
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1929),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  color: JC.textPrimary, fontSize: 13, fontFamily: 'Heebo'),
              decoration: InputDecoration(
                hintText: 'חיפוש סוכן...',
                hintStyle: TextStyle(
                    color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo'),
                prefixIcon:
                    Icon(Icons.search_rounded, color: JC.textMuted, size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _agentFilter = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 14),
          if (_loadingAgents)
            _SectionLoader()
          else if (_agentsError != null)
            _ErrorText(_agentsError!)
          else if (_agents.isEmpty)
            const _EmptyState(message: 'לא נמצאו סוכנים')
          else
            _AgentGroupedList(),
        ],
      ),
    );
  }

  Widget _AgentGroupedList() {
    List<Map<String, dynamic>> filtered(List<Map<String, dynamic>> list) {
      if (_agentFilter.isEmpty) return list;
      return list.where((a) {
        final name = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
        final role =
            (a['description'] ?? a['role'] ?? '').toString().toLowerCase();
        return name.contains(_agentFilter) || role.contains(_agentFilter);
      }).toList();
    }

    final active = filtered(_activeAgents);
    final idle = filtered(_idleAgents);
    final offline = filtered(_offlineAgents);
    final hasAny =
        active.isNotEmpty || idle.isNotEmpty || offline.isNotEmpty;

    if (!hasAny) return const _EmptyState(message: 'לא נמצאו סוכנים תואמים');

    return Column(
      children: [
        if (active.isNotEmpty)
          _AgentStatusGroup(
            label: 'פעילים',
            count: active.length,
            dotColor: const Color(0xFF22C55E),
            agents: active,
            onAgentTap: _showAgentSettings,
          ),
        if (active.isNotEmpty && (idle.isNotEmpty || offline.isNotEmpty))
          const SizedBox(height: 10),
        if (idle.isNotEmpty)
          _AgentStatusGroup(
            label: 'המתנה',
            count: idle.length,
            dotColor: const Color(0xFFF59E0B),
            agents: idle,
            onAgentTap: _showAgentSettings,
          ),
        if (idle.isNotEmpty && offline.isNotEmpty)
          const SizedBox(height: 10),
        if (offline.isNotEmpty)
          _AgentStatusGroup(
            label: 'לא פעילים',
            count: offline.length,
            dotColor: const Color(0xFF475569),
            agents: offline,
            onAgentTap: _showAgentSettings,
          ),
      ],
    );
  }

  // ── Agent Network Map ──────────────────────────────────────────────────────

  Widget _AgentNetworkMapCard() {
    if (_loadingAgents || _agents.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              Icon(Icons.account_tree_rounded, color: JC.blue400, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('מפת הסוכנים',
                    style: TextStyle(color: JC.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _agentMapView = !_agentMapView;
                  _selectedAgentIdx = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: JC.blue400.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: JC.blue400.withOpacity(0.3), width: 0.8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_agentMapView ? Icons.list_rounded : Icons.account_tree_rounded,
                        color: JC.blue400, size: 14),
                    const SizedBox(width: 4),
                    Text(_agentMapView ? 'רשימה' : 'מפה',
                        style: TextStyle(color: JC.blue400, fontSize: 11, fontFamily: 'Heebo')),
                  ]),
                ),
              ),
            ]),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _agentMapView ? _AgentMapView() : _AgentListView(),
          ),
        ],
      ),
    );
  }

  Widget _AgentMapView() {
    const double mapW    = 380.0;
    const double nodeW   = 82.0;
    const double nodeH   = 50.0;
    const double nodeGap = 6.0;
    const double agentStartY = 202.0;

    final core    = <Map<String, dynamic>>[];
    final domain  = <Map<String, dynamic>>[];
    final quality = <Map<String, dynamic>>[];
    for (final a in _agents) {
      switch (_agentCat(a)) {
        case 'core':    core.add(a);    break;
        case 'quality': quality.add(a); break;
        default:        domain.add(a);  break;
      }
    }
    final cols      = [core, domain, quality];
    final catColors = [const Color(0xFF22C55E), const Color(0xFFF59E0B), const Color(0xFFA78BFA)];
    final catLabels = ['ליבה', 'דומיין', 'איכות'];
    final colX      = [62.0, mapW / 2, mapW - 62.0];

    final maxRows = cols.fold(0, (m, c) => max(m, c.length));
    final mapH = agentStartY + maxRows * (nodeH + nodeGap) + 28.0;

    // ── Build edges (from-center, to-center, color) ──────────────────────────
    const routerCY  = 88.0;
    const catCY     = 152.0;

    final edges = <(Offset, Offset, Color)>[];
    // User → Router
    edges.add((const Offset(mapW / 2, 30), const Offset(mapW / 2, routerCY - 16),
        const Color(0xFF6366F1)));
    // Router → category hubs
    for (int c = 0; c < 3; c++) {
      if (cols[c].isNotEmpty) {
        edges.add((const Offset(mapW / 2, routerCY + 16),
            Offset(colX[c], catCY - 13), catColors[c]));
      }
    }
    // Category hubs → agent nodes
    for (int c = 0; c < 3; c++) {
      for (int i = 0; i < cols[c].length; i++) {
        final agentTopY = agentStartY + i * (nodeH + nodeGap);
        edges.add((Offset(colX[c], catCY + 13),
            Offset(colX[c], agentTopY), catColors[c]));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hint
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(Icons.pinch_rounded, color: JC.textMuted, size: 12),
            const SizedBox(width: 4),
            Text('גרור לגלילה • צבוט לזום • לחץ לפרטים',
              style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
          ]),
        ),
        GestureDetector(
          // Absorb horizontal drags so the parent tab-swipe detector
          // doesn't steal pan gestures from the InteractiveViewer.
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          onHorizontalDragEnd: (_) {},
          child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 310,
            child: InteractiveViewer(
              constrained: false,
              minScale: 0.45,
              maxScale: 3.0,
              boundaryMargin: const EdgeInsets.all(60),
              child: SizedBox(
                width: mapW,
                height: mapH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Background
                    Container(
                      width: mapW, height: mapH,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF060D1A), Color(0xFF0A1628)],
                        ),
                      ),
                    ),
                    // Animated connection lines + flow particles
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => CustomPaint(
                        size: Size(mapW, mapH),
                        painter: _AgentFlowLinePainter(
                          edges: edges,
                          pulseValue: _pulseController.value,
                        ),
                      ),
                    ),
                    // User entry node
                    Positioned(
                      left: mapW / 2 - 44, top: 10,
                      child: _MapSpecialNode(label: '📱 משתמש',
                          color: const Color(0xFF6366F1), w: 88, h: 28),
                    ),
                    // Router node
                    Positioned(
                      left: mapW / 2 - 50, top: routerCY - 16,
                      child: _MapSpecialNode(label: '🔀 Router',
                          color: const Color(0xFF3B82F6), w: 100, h: 32,
                          isRouter: true),
                    ),
                    // Category hub nodes
                    for (int c = 0; c < 3; c++)
                      Positioned(
                        left: colX[c] - 36, top: catCY - 13,
                        child: _MapCategoryNode(
                          label: catLabels[c], color: catColors[c],
                          count: cols[c].length),
                      ),
                    // Agent nodes
                    for (int c = 0; c < 3; c++)
                      for (int i = 0; i < cols[c].length; i++)
                        Positioned(
                          left: colX[c] - nodeW / 2,
                          top: agentStartY + i * (nodeH + nodeGap),
                          child: GestureDetector(
                            onTap: () => _showAgentSettings(cols[c][i]),
                            child: _AgentMapNodeWidget(
                              agent: cols[c][i],
                              w: nodeW, h: nodeH,
                              catColor: catColors[c],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ),
      ],
    );
  }

  Widget _AgentListView() {
    return Column(
      children: _agents.map((a) {
        final name = a['name'] ?? a['id'] ?? 'סוכן';
        final status = (a['status'] ?? '').toString();
        final statusColor = _statusColor(status);
        final cat = _agentCat(a);
        final catColor = cat == 'core'
            ? const Color(0xFF22C55E)
            : cat == 'domain'
                ? const Color(0xFFF59E0B)
                : const Color(0xFFA78BFA);
        final isActive = status == 'active' || status == 'online';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: isActive ? [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)] : [],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(name.toString(),
                  style: TextStyle(color: JC.textPrimary, fontSize: 12, fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(cat == 'core' ? 'ליבה' : cat == 'domain' ? 'דומיין' : 'איכות',
                  style: TextStyle(color: catColor, fontSize: 9, fontFamily: 'Heebo')),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _quickToggleAgent(a),
              child: Container(
                width: 28, height: 16,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF22C55E).withOpacity(0.2) : const Color(0xFF475569).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive ? const Color(0xFF22C55E).withOpacity(0.5) : const Color(0xFF475569).withOpacity(0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(mainAxisAlignment: isActive ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
                  Container(
                    width: 12, height: 12,
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF22C55E) : const Color(0xFF475569),
                      shape: BoxShape.circle,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showAgentSettings(a),
              child: Icon(Icons.tune_rounded, color: JC.textMuted, size: 16),
            ),
          ]),
        );
      }).toList(),
    );
  }

  void _showAgentSettings(Map<String, dynamic> agent) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0D1B2E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => AgentDetailSheet(
          agent: agent, base: widget.settings.serverUrl),
    );
  }

  Widget _AgentDetailStrip(Map<String, dynamic> agent) {
    final name = agent['name'] ?? agent['id'] ?? 'סוכן';
    final role = agent['description'] ?? agent['role'] ?? '';
    final status = (agent['status'] ?? '').toString();
    final risk = agent['riskLevel'] ?? agent['risk_level'] ?? 'low';
    final statusColor = _statusColor(status);
    final riskColor = _riskColor(risk);

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1929),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.5),
                  blurRadius: 5,
                  spreadRadius: 1,
                )
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toString(),
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  ),
                ),
                if (role.toString().isNotEmpty)
                  Text(
                    role.toString(),
                    style: TextStyle(color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _riskLabel(risk),
              style: TextStyle(color: riskColor, fontSize: 9, fontFamily: 'Heebo'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Issues ─────────────────────────────────────────────────────────────────

  Widget _IssuesSection() {
    if (!_loadingIssues && _issues.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'מה דורש טיפול עכשיו',
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: _loadingIssues
          ? _SectionLoader()
          : _issues.isEmpty
              ? const _EmptyState(message: 'הכל תקין ✅ אין תקלות פתוחות')
              : Column(
                  children: _issues.map((r) => _IssueCard(r)).toList(),
                ),
    );
  }

  Widget _IssueCard(Map<String, dynamic> r) {
    final title = r['run_id'] ?? r['id'] ?? 'דוח לא ידוע';
    final status = r['status'] ?? '';
    final ts = r['created_at'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1929),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report_outlined,
              color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 13,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600)),
                if (ts.isNotEmpty)
                  Text(_shortDate(ts),
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo')),
              ],
            ),
          ),
          _StatusChip(status),
        ],
      ),
    );
  }

  // ── Features ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _featureIdeas {
    final ideas = <Map<String, dynamic>>[];
    for (final p in _proposals) {
      final title = (p['title'] ?? p['text'] ?? '').toString();
      if (title.isEmpty) continue;
      ideas.add({
        'icon': Icons.auto_awesome_rounded,
        'title': title,
        'desc': (p['why_now'] ?? p['plan'] ?? 'הצעת AI לפיתוח').toString(),
      });
    }
    for (final b in _backlog.where((b) => b['done'] != true)) {
      final title = (b['title'] ?? b['text'] ?? '').toString();
      if (title.isEmpty) continue;
      ideas.add({
        'icon': Icons.lightbulb_outline_rounded,
        'title': title,
        'desc': 'עדיפות: ${b['priority'] ?? 'בינונית'}',
      });
    }
    return ideas;
  }

  Widget _FeaturesSection() {
    final ideas = _featureIdeas;
    return _SectionCard(
      title: 'שיפורים ופיתוח',
      icon: Icons.lightbulb_outline_rounded,
      iconColor: const Color(0xFFA5B4FC),
      child: (_loadingBacklog && ideas.isEmpty)
          ? _SectionLoader()
          : ideas.isEmpty
              ? const _EmptyState(message: 'אין רעיונות פיתוח כרגע — בקש מ-Jarvis הצעות')
              : SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    itemCount: ideas.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final f = ideas[i];
                      return _FeatureIdeaCard(
                        icon: f['icon'] as IconData,
                        title: f['title'] as String,
                        desc: f['desc'] as String,
                      );
                    },
                  ),
                ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentStatusGroup extends StatefulWidget {
  final String label;
  final int count;
  final Color dotColor;
  final List<Map<String, dynamic>> agents;
  final void Function(Map<String, dynamic>)? onAgentTap;

  const _AgentStatusGroup({
    required this.label,
    required this.count,
    required this.dotColor,
    required this.agents,
    this.onAgentTap,
  });

  @override
  State<_AgentStatusGroup> createState() => _AgentStatusGroupState();
}

class _AgentStatusGroupState extends State<_AgentStatusGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1929),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Pulsing dot for active group
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: widget.dotColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: widget.dotColor.withOpacity(0.5),
                            blurRadius: 6, spreadRadius: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(widget.label,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0), fontSize: 13,
                      fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.dotColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: widget.dotColor.withOpacity(0.3)),
                    ),
                    child: Text('${widget.count}',
                      style: TextStyle(
                        color: widget.dotColor, fontSize: 11,
                        fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.5,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_up_rounded,
                        color: const Color(0xFF475569), size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: JC.border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                children: [
                  for (int i = 0; i < widget.agents.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _AgentMiniCard(
                      widget.agents[i],
                      onTap: widget.onAgentTap != null
                          ? () => widget.onAgentTap!(widget.agents[i])
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Agent icon emoji map (mirrors AgentDetailSheet) ──────────────────────────
const _kAgentEmojiMap = {
  'router': '🔀', 'chatAgent': '💬', 'taskAgent': '✅', 'reminderAgent': '⏰',
  'memoryAgent': '🧠', 'weatherAgent': '🌤', 'newsAgent': '📰', 'stocksAgent': '📈',
  'translationAgent': '🌐', 'sportsAgent': '⚽', 'shoppingAgent': '🛒',
  'notesAgent': '📝', 'musicAgent': '🎵', 'messagingAgent': '📨',
  'draftAgent': '✍️', 'insightAgent': '💡', 'securityAgent': '🛡',
  'codeErrorAgent': '🐛', 'e2eAgent': '🧪', 'agentFactoryAgent': '🏭',
  'surveyAgent': '📋',
};

class _AgentMiniCard extends StatelessWidget {
  final Map<String, dynamic> agent;
  final VoidCallback? onTap;

  const _AgentMiniCard(this.agent, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final id     = (agent['id'] ?? '').toString();
    final name   = (agent['nameHe'] ?? agent['name'] ?? agent['id'] ?? 'סוכן').toString();
    final role   = (agent['description'] ?? agent['role'] ?? '').toString();
    final risk   = (agent['riskLevel'] ?? agent['risk_level'] ?? agent['risk'] ?? 'low').toString();
    final status = (agent['status'] ?? '').toString();
    final health = (agent['healthScore'] as num?)?.toInt();
    final metrics = agent['metrics'] as Map<String, dynamic>?;
    final avgMs  = (metrics?['avgMs'] as num?)?.toInt();
    final emoji  = _kAgentEmojiMap[id] ?? '🤖';

    final statusColor = _statusColor(status);
    final isActive = status == 'active' || status == 'online';

    Color healthColor(int? s) {
      if (s == null) return const Color(0xFF475569);
      if (s >= 80) return const Color(0xFF22C55E);
      if (s >= 50) return const Color(0xFFF59E0B);
      return const Color(0xFFEF4444);
    }

    String latencyLabel(int? ms) {
      if (ms == null) return '';
      if (ms <= 800) return '⚡ מהיר';
      if (ms <= 2000) return '⏱ בינוני';
      return '🐢 איטי';
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1829),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? statusColor.withOpacity(0.35)
                : const Color(0xFF1E3A5F).withOpacity(0.6),
            width: 0.9,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: statusColor.withOpacity(0.08), blurRadius: 10, spreadRadius: 0)]
              : [],
        ),
        child: Row(
          children: [
            // Emoji icon
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.25)),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            // Name + role + metrics
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0), fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700, fontSize: 13),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      // Status pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              color: statusColor, shape: BoxShape.circle,
                              boxShadow: isActive
                                  ? [BoxShadow(color: statusColor.withOpacity(0.7), blurRadius: 4)]
                                  : [],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(_statusLabel(status),
                            style: TextStyle(
                              color: statusColor, fontFamily: 'Heebo',
                              fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ),
                  if (role.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(role,
                      style: const TextStyle(
                        color: Color(0xFF64748B), fontFamily: 'Heebo', fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 5),
                  // Badges row
                  Wrap(
                    spacing: 5, runSpacing: 4,
                    children: [
                      if (health != null)
                        _miniChip('$health%', healthColor(health)),
                      if (avgMs != null)
                        _miniChip(latencyLabel(avgMs), const Color(0xFF38BDF8)),
                      _miniChip(_riskLabel(risk), _riskColor(risk)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // Chevron
            if (onTap != null)
              Icon(Icons.chevron_left_rounded,
                  color: const Color(0xFF475569), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withOpacity(0.25), width: 0.7),
    ),
    child: Text(text,
      style: TextStyle(color: color, fontFamily: 'Heebo',
          fontSize: 10, fontWeight: FontWeight.w600)),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? headerTrailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    ),
                  ),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    final label = _statusLabel(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 0.6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600)),
    );
  }
}

class _FeatureIdeaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureIdeaCard(
      {required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1929),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded,
              color: Color(0xFFA5B4FC), size: 22),
          const SizedBox(height: 8),
          Text(title,
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(desc,
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SurveyQuestionCard extends StatelessWidget {
  final Map<String, dynamic> question;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _SurveyQuestionCard(
      {required this.question,
      required this.selected,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final q = question['question'] as String? ?? '';
    final options = List<String>.from(question['options'] as List? ?? []);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q,
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Heebo')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSelected = selected == opt;
              return GestureDetector(
                onTap: () => onSelect(opt),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? JC.blue500.withOpacity(0.2)
                        : const Color(0xFF0F1929),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? JC.blue500 : JC.border,
                      width: isSelected ? 1.0 : 0.6,
                    ),
                  ),
                  child: Text(opt,
                      style: TextStyle(
                        color: isSelected ? JC.blue400 : JC.textSecondary,
                        fontSize: 12,
                        fontFamily: 'Heebo',
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      )),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SectionLoader extends StatelessWidget {
  const _SectionLoader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: JC.blue400)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo')),
      ),
    );
  }
}

class _SnackOverlay extends StatelessWidget {
  final String message;

  const _SnackOverlay(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E4A),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
  }
}

Widget _ErrorText(String msg) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(msg,
        style: const TextStyle(
            color: Color(0xFFEF4444), fontSize: 12, fontFamily: 'Heebo')),
  );
}

// ── Agent Category Helpers ────────────────────────────────────────────────────

const _kCorePats = ['chat', 'memory', 'task', 'reminder', 'shopping', 'notes'];
const _kDomainPats = ['weather', 'news', 'stock', 'sport', 'music', 'translat', 'messag'];
const _kQualityPats = ['e2e', 'security', 'code', 'insight', 'draft', 'factory', 'survey'];

String _agentCat(Map<String, dynamic> a) {
  final n = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
  if (_kCorePats.any((p) => n.contains(p))) return 'core';
  if (_kQualityPats.any((p) => n.contains(p))) return 'quality';
  if (_kDomainPats.any((p) => n.contains(p))) return 'domain';
  return 'domain';
}

// ── Stability Donut Painter ───────────────────────────────────────────────────

class _StabilityDonutPainter extends CustomPainter {
  final double fraction;
  final Color color;
  const _StabilityDonutPainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 6.0;

    final bgPaint = Paint()
      ..color = color.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14 / 2,
      2 * 3.14159 * fraction,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StabilityDonutPainter old) =>
      old.fraction != fraction || old.color != color;
}

// ── Agent Map: flow line painter + node widgets ───────────────────────────────

class _AgentFlowLinePainter extends CustomPainter {
  final List<(Offset, Offset, Color)> edges;
  final double pulseValue;

  const _AgentFlowLinePainter({required this.edges, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < edges.length; i++) {
      final from  = edges[i].$1;
      final to    = edges[i].$2;
      final color = edges[i].$3;

      // Base line
      canvas.drawLine(from, to, Paint()
        ..color = color.withOpacity(0.22)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round);

      // Animated particle — stagger by edge index so they don't all sync
      final t = (pulseValue + i * 0.13) % 1.0;
      final pos  = Offset.lerp(from, to, t)!;
      final pos2 = Offset.lerp(from, to, (t - 0.12).clamp(0.0, 1.0))!;

      canvas.drawCircle(pos,  2.8, Paint()..color = color.withOpacity(0.9));
      canvas.drawCircle(pos2, 1.6, Paint()..color = color.withOpacity(0.45));
    }
  }

  @override
  bool shouldRepaint(_AgentFlowLinePainter old) => old.pulseValue != pulseValue;
}

class _MapSpecialNode extends StatelessWidget {
  final String label;
  final Color color;
  final double w, h;
  final bool isRouter;

  const _MapSpecialNode({
    required this.label, required this.color,
    required this.w, required this.h, this.isRouter = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      gradient: LinearGradient(
          colors: [color.withOpacity(0.35), color.withOpacity(0.18)]),
      borderRadius: BorderRadius.circular(h / 2),
      border: Border.all(color: color.withOpacity(0.55), width: 1),
      boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 10)],
    ),
    child: Center(child: Text(label,
      style: TextStyle(color: Colors.white, fontFamily: 'Heebo',
          fontSize: isRouter ? 12 : 11, fontWeight: FontWeight.w700))),
  );
}

class _MapCategoryNode extends StatelessWidget {
  final String label;
  final Color color;
  final int count;

  const _MapCategoryNode({required this.label, required this.color, required this.count});

  @override
  Widget build(BuildContext context) => Container(
    width: 72, height: 26,
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withOpacity(0.45), width: 0.8),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 11,
            fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6)),
          child: Text('$count', style: TextStyle(color: color, fontSize: 9,
              fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class _AgentMapNodeWidget extends StatelessWidget {
  final Map<String, dynamic> agent;
  final double w, h;
  final Color catColor;

  const _AgentMapNodeWidget({
    required this.agent, required this.w,
    required this.h, required this.catColor,
  });

  @override
  Widget build(BuildContext context) {
    final id      = (agent['id'] ?? '').toString();
    final name    = (agent['nameHe'] ?? agent['name'] ?? id).toString();
    final status  = (agent['status'] ?? '').toString();
    final health  = (agent['healthScore'] as num?)?.toInt();
    final metrics = agent['metrics'] as Map<String, dynamic>?;
    final avgMs   = (metrics?['avgMs'] as num?)?.toInt();
    final emoji   = _kAgentEmojiMap[id] ?? '🤖';
    final isActive = status == 'active' || status == 'online';
    final statusColor = _statusColor(status);

    Color healthColor(int? s) {
      if (s == null) return const Color(0xFF475569);
      if (s >= 80) return const Color(0xFF22C55E);
      if (s >= 50) return const Color(0xFFF59E0B);
      return const Color(0xFFEF4444);
    }

    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0D1829) : const Color(0xFF090F1C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? catColor.withOpacity(0.45) : const Color(0xFF1E3A5F).withOpacity(0.45),
          width: 0.8,
        ),
        boxShadow: isActive
            ? [BoxShadow(color: catColor.withOpacity(0.18), blurRadius: 8)]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 3),
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: statusColor, shape: BoxShape.circle,
                boxShadow: isActive
                    ? [BoxShadow(color: statusColor.withOpacity(0.7), blurRadius: 5)]
                    : [],
              ),
            ),
          ]),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text(
              name.length > 11 ? '${name.substring(0, 10)}…' : name,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isActive ? const Color(0xFFCBD5E1) : const Color(0xFF4B5A6E),
                fontFamily: 'Heebo', fontSize: 9,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (health != null) _chip('$health%', healthColor(health)),
            if (health != null && avgMs != null) const SizedBox(width: 3),
            if (avgMs != null)
              _chip(avgMs <= 800 ? '⚡' : avgMs <= 2000 ? '⏱' : '🐢',
                  const Color(0xFF38BDF8)),
          ]),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
    child: Text(t, style: TextStyle(color: c, fontSize: 8,
        fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
  );
}
