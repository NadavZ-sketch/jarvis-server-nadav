import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../widgets/preview_banner.dart';

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
// Demo data
// ─────────────────────────────────────────────────────────────────────────────

const _demoFeatureIdeas = [
  {'icon': Icons.auto_awesome, 'title': 'סיכום יום אוטומטי', 'desc': 'Jarvis מסכם כל יום ב-21:00 עם הישגים ומשימות פתוחות'},
  {'icon': Icons.mic_none_rounded, 'title': 'בריגייד קולי', 'desc': 'הפעלת פקודות בלי לפתוח את האפליקציה'},
  {'icon': Icons.hub_rounded, 'title': 'חיבור Google Calendar', 'desc': 'סנכרון דו-כיווני עם יומן Google'},
  {'icon': Icons.trending_up_rounded, 'title': 'ניתוח מגמות', 'desc': 'Jarvis מזהה דפוסים בפעילות ומציע שיפורים'},
  {'icon': Icons.group_rounded, 'title': 'שיתוף משימות', 'desc': 'שליחת משימות לחברי צוות דרך WhatsApp'},
];

const _demoSurveyQuestions = [
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

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _issues = [];
  List<Map<String, dynamic>> _survey = [];

  bool _loadingStats = true;
  bool _loadingAgents = true;
  bool _loadingIssues = true;
  bool _useDemoSurvey = false;

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
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refreshAll() {
    setState(() {
      _loadingStats = true;
      _loadingAgents = true;
      _loadingIssues = true;
      _statsError = null;
      _agentsError = null;
    });
    _load();
  }

  Future<void> _load() async {
    await Future.wait(
        [_loadStats(), _loadAgents(), _loadIssues(), _loadSurvey()]);
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
          _survey = s.isNotEmpty ? s : _demoSurveyQuestions;
          _useDemoSurvey = s.isEmpty;
        });
      }
    } catch (_) {
      if (mounted)
        setState(() { _survey = _demoSurveyQuestions; _useDemoSurvey = true; });
    }
  }

  void _showSnack(String msg) {
    setState(() => _snackMessage = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _snackMessage = null);
    });
  }

  // Health score: fraction of active agents
  double get _healthScore {
    if (_agents.isEmpty) return 1.0;
    final active = _agents
        .where((a) =>
            (a['status'] ?? '').toString().toLowerCase() == 'active' ||
            (a['status'] ?? '').toString().toLowerCase() == 'online')
        .length;
    return active / _agents.length;
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
            onTap: () => Navigator.pop(context),
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
              child: Icon(Icons.arrow_back_ios_new_rounded,
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
                '$screenTitle · Preview',
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
              const PreviewBanner(),
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
          _CognitiveStatusCard(),
          const SizedBox(height: 16),
          _SystemHealthCard(),
          const SizedBox(height: 16),
          _StatsRow(),
          const SizedBox(height: 16),
          _QuickActionsRow(),
        ],
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
          _AgentNetworkMapCard(),
          const SizedBox(height: 12),
          _AgentResourceBars(),
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
          _StabilityScoreCard(),
          const SizedBox(height: 16),
          _ImprovementSuggestionsCard(),
          const SizedBox(height: 16),
          _LatencyBarsCard(),
          const SizedBox(height: 16),
          _IssuesSection(),
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
          _ImprovementFeedbackLoopCard(),
          const SizedBox(height: 16),
          _DecisionFlowCard(),
          const SizedBox(height: 16),
          _RecentEventsLog(),
        ],
      ),
    );
  }

  // ── Tab 1: Cognitive Status ────────────────────────────────────────────────

  Widget _CognitiveStatusCard() {
    final active = _activeAgents.length;
    final idle = _idleAgents.length;
    final offline = _offlineAgents.length;
    final total = _agents.isEmpty ? 1 : _agents.length;

    final String statusLabel;
    final Color statusColor;
    if (active > idle && active > 0) {
      statusLabel = 'מחשב';
      statusColor = JC.blue400;
    } else if (idle >= active && idle > 0) {
      statusLabel = 'ממתין';
      statusColor = JC.textMuted;
    } else {
      statusLabel = 'מגיב';
      statusColor = const Color(0xFF22C55E);
    }

    final coreCount = _agents.where((a) => _agentCat(a) == 'core').length;
    final domainCount = _agents.where((a) => _agentCat(a) == 'domain').length;
    final qualityCount = _agents.where((a) => _agentCat(a) == 'quality').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.psychology_rounded, color: JC.blue400, size: 18),
            const SizedBox(width: 8),
            Text('מצב קוגניטיבי',
                style: TextStyle(color: JC.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Heebo')),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.5), width: 0.8),
              ),
              child: Text(statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 11, fontFamily: 'Heebo', fontWeight: FontWeight.w700)),
            ),
          ]),
          Divider(color: JC.border, height: 20),
          Row(children: [
            _DotLabel(const Color(0xFF22C55E), 'ליבה', coreCount),
            const SizedBox(width: 16),
            _DotLabel(const Color(0xFFF59E0B), 'דומיין', domainCount),
            const SizedBox(width: 16),
            _DotLabel(const Color(0xFFA78BFA), 'איכות', qualityCount),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                Expanded(flex: coreCount + 1, child: Container(color: const Color(0xFF22C55E).withOpacity(0.7))),
                Expanded(flex: domainCount + 1, child: Container(color: const Color(0xFFF59E0B).withOpacity(0.7))),
                Expanded(flex: qualityCount + 1, child: Container(color: const Color(0xFFA78BFA).withOpacity(0.7))),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _DotLabel(const Color(0xFF22C55E), 'פעיל', active),
            const SizedBox(width: 12),
            _DotLabel(const Color(0xFFF59E0B), 'המתנה', idle),
            const SizedBox(width: 12),
            _DotLabel(const Color(0xFF475569), 'לא פעיל', offline),
            const Spacer(),
            Text('${active}/${total} פעיל',
                style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ]),
        ],
      ),
    );
  }

  Widget _DotLabel(Color color, String label, int count) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text('$label $count', style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
    ]);
  }

  // ── Tab 2: Agent Resource Bars ─────────────────────────────────────────────

  Widget _AgentResourceBars() {
    final coreAgents = _agents.where((a) => _agentCat(a) == 'core').toList();
    final domainAgents = _agents.where((a) => _agentCat(a) == 'domain').toList();
    final qualityAgents = _agents.where((a) => _agentCat(a) == 'quality').toList();

    if (_loadingAgents) return const SizedBox.shrink();

    return _SectionCard(
      title: 'עומס לפי קטגוריה',
      icon: Icons.bar_chart_rounded,
      iconColor: const Color(0xFFA78BFA),
      child: Column(children: [
        _CatBar('ליבה', coreAgents.length, 6, const Color(0xFF22C55E)),
        const SizedBox(height: 10),
        _CatBar('דומיין', domainAgents.length, 7, const Color(0xFFF59E0B)),
        const SizedBox(height: 10),
        _CatBar('איכות', qualityAgents.length, 7, const Color(0xFFA78BFA)),
      ]),
    );
  }

  Widget _CatBar(String label, int count, int max, Color color) {
    final frac = max == 0 ? 0.0 : (count / max).clamp(0.0, 1.0);
    return Row(children: [
      SizedBox(width: 44, child: Text(label, style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'))),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 10, color: color.withOpacity(0.12)),
            FractionallySizedBox(
              widthFactor: frac,
              child: Container(height: 10, color: color.withOpacity(0.8)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Text('$count/$max', style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
    ]);
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
    const data = [
      ('chatAgent', 87),
      ('memoryAgent', 143),
      ('weatherAgent', 342),
      ('taskAgent', 65),
      ('e2eAgent', 489),
    ];
    const maxMs = 500;

    return _SectionCard(
      title: 'זמן תגובה לפי סוכן',
      icon: Icons.speed_rounded,
      iconColor: const Color(0xFF3B82F6),
      headerTrailing: const DemoChip(),
      child: Column(
        children: data.map((entry) {
          final frac = (entry.$2 / maxMs).clamp(0.0, 1.0);
          final color = entry.$2 < 100
              ? const Color(0xFF22C55E)
              : entry.$2 < 300
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEF4444);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(
                width: 80,
                child: Text(entry.$1, style: TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
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
                width: 48,
                child: Text('${entry.$2}ms',
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
            if (_useDemoSurvey) const DemoChip(),
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

  Widget _ImprovementFeedbackLoopCard() {
    final qualityFrac = _surveyAnswers['responseQuality'] == 'מעולה'
        ? 0.92 : _surveyAnswers['responseQuality'] == 'טובה'
            ? 0.72 : _surveyAnswers['responseQuality'] == 'בינונית'
                ? 0.50 : 0.75;

    return _SectionCard(
      title: 'תחומים בפיתוח פעיל',
      icon: Icons.trending_up_rounded,
      iconColor: const Color(0xFF22C55E),
      child: Column(children: [
        _FeedbackBar('דיוק תשובות', qualityFrac, const Color(0xFF22C55E), false),
        const SizedBox(height: 10),
        _FeedbackBar('מהירות תגובה', 0.68, const Color(0xFFF59E0B), true),
        const SizedBox(height: 10),
        _FeedbackBar('זיהוי כוונות', 0.81, const Color(0xFF3B82F6), true),
        const SizedBox(height: 10),
        _FeedbackBar('זיכרון והקשר', 0.59, const Color(0xFFA78BFA), true),
      ]),
    );
  }

  Widget _FeedbackBar(String label, double frac, Color color, bool isDemo) {
    final pct = (frac * 100).round();
    return Row(children: [
      SizedBox(width: 100,
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(color: JC.textMuted, fontSize: 12, fontFamily: 'Heebo'))),
            if (isDemo) const SizedBox(width: 4),
            if (isDemo) const DemoChip(),
          ])),
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

  // ── Tab 4: Recent Events Log ───────────────────────────────────────────────

  Widget _RecentEventsLog() {
    final entries = <Map<String, dynamic>>[];

    for (final r in _issues) {
      entries.add({
        'ts': r['created_at'] ?? '',
        'text': 'E2E run: ${r['run_id'] ?? r['id'] ?? '?'} → ${r['status'] ?? 'Status: Unknown'}',
        'color': _statusColor(r['status']),
      });
    }

    for (final a in _agents.take(10)) {
      final name = a['name'] ?? a['id'] ?? 'agent';
      final status = (a['status'] ?? '').toString();
      entries.add({
        'ts': '',
        'text': '[boot] Agent $name initialized — ${_statusLabel(status)}',
        'color': _statusColor(status),
      });
    }

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
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    if (ts.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1929),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_shortDate(ts),
                            style: TextStyle(color: JC.textMuted, fontSize: 9, fontFamily: 'Heebo')),
                      ),
                    Container(width: 6, height: 6,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e['text'] as String,
                        style: TextStyle(color: JC.textSecondary, fontSize: 11, fontFamily: 'Heebo'),
                        overflow: TextOverflow.ellipsis)),
                  ]),
                );
              }).toList(),
            ),
    );
  }

  // ── System Health Card ─────────────────────────────────────────────────────

  Widget _SystemHealthCard() {
    final score = _healthScore;
    final pct = (score * 100).round();
    final healthColor = score > 0.8
        ? const Color(0xFF22C55E)
        : score > 0.5
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);
    final serverOk = _statsError == null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2E4A),
            JC.surface,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          // Health ring
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _loadingAgents ? null : score,
                  strokeWidth: 5,
                  backgroundColor: const Color(0xFF1A2E4A),
                  valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                ),
                if (!_loadingAgents)
                  Text(
                    '$pct%',
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Heebo',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'בריאות המערכת',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Heebo',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  serverOk ? 'השרת פעיל ומחובר' : 'שגיאת חיבור לשרת',
                  style: TextStyle(
                    color: serverOk
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    fontSize: 12,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatusDot(const Color(0xFF22C55E)),
                    const SizedBox(width: 4),
                    Text(
                      '${_activeAgents.length} פעילים',
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo'),
                    ),
                    const SizedBox(width: 10),
                    _StatusDot(const Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      '${_idleAgents.length} המתנה',
                      style: TextStyle(
                          color: JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ──────────────────────────────────────────────────────────

  Widget _QuickActionsRow() {
    final actions = [
      {'icon': Icons.health_and_safety_outlined, 'label': 'בדוק מערכת', 'color': const Color(0xFF22C55E)},
      {'icon': Icons.play_circle_outline_rounded, 'label': 'הפעל E2E', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.hub_rounded, 'label': 'טען סוכנים', 'color': const Color(0xFFA5B4FC)},
      {'icon': Icons.bar_chart_rounded, 'label': 'צפה בדוחות', 'color': const Color(0xFFF59E0B)},
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
            onTap: () => _showSnack('${a['label']} · בקרוב (Preview)'),
          );
        },
      ),
    );
  }

  // ── Stats Row ──────────────────────────────────────────────────────────────

  Widget _StatsRow() {
    final totalMessages =
        _stats?['total_messages'] ?? _stats?['totalMessages'] ?? '—';
    final serverOk = _statsError == null;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.dns_rounded,
            label: 'שרת',
            value: serverOk ? 'פעיל' : 'שגיאה',
            valueColor:
                serverOk ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'הודעות',
            value: '$totalMessages',
            valueColor: null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.smart_toy_outlined,
            label: 'סוכנים',
            value: _loadingAgents ? '...' : '${_agents.length}',
            valueColor: null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.warning_amber_rounded,
            label: 'תקלות',
            value: _loadingIssues ? '...' : '${_issues.length}',
            valueColor: _issues.isNotEmpty
                ? const Color(0xFFF59E0B)
                : const Color(0xFF22C55E),
          ),
        ),
      ],
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
          ),
        if (active.isNotEmpty && (idle.isNotEmpty || offline.isNotEmpty))
          const SizedBox(height: 10),
        if (idle.isNotEmpty)
          _AgentStatusGroup(
            label: 'המתנה',
            count: idle.length,
            dotColor: const Color(0xFFF59E0B),
            agents: idle,
          ),
        if (idle.isNotEmpty && offline.isNotEmpty)
          const SizedBox(height: 10),
        if (offline.isNotEmpty)
          _AgentStatusGroup(
            label: 'לא פעילים',
            count: offline.length,
            dotColor: const Color(0xFF475569),
            agents: offline,
          ),
      ],
    );
  }

  // ── Agent Network Map ──────────────────────────────────────────────────────

  Widget _AgentNetworkMapCard() {
    if (_loadingAgents || _agents.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'מפת הסוכנים',
      icon: Icons.account_tree_rounded,
      iconColor: JC.blue400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 220,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sz = Size(constraints.maxWidth, 220);
                return GestureDetector(
                  onTapUp: (details) {
                    final positions = _AgentTreePainter.agentPositions(_agents, sz);
                    int? closest;
                    double minDist = 18;
                    for (final p in positions) {
                      final d = (p.$2 - details.localPosition).distance;
                      if (d < minDist) {
                        minDist = d;
                        closest = p.$1;
                      }
                    }
                    setState(() => _selectedAgentIdx =
                        closest == _selectedAgentIdx ? null : closest);
                  },
                  child: CustomPaint(
                    size: sz,
                    painter: _AgentTreePainter(
                      agents: _agents,
                      selectedIdx: _selectedAgentIdx,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selectedAgentIdx != null && _selectedAgentIdx! < _agents.length)
            _AgentDetailStrip(_agents[_selectedAgentIdx!]),
        ],
      ),
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

  Widget _FeaturesSection() {
    return _SectionCard(
      title: 'שיפורים ופיתוח',
      icon: Icons.lightbulb_outline_rounded,
      iconColor: const Color(0xFFA5B4FC),
      headerTrailing: const DemoChip(),
      child: SizedBox(
        height: 130,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          reverse: true,
          itemCount: _demoFeatureIdeas.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final f = _demoFeatureIdeas[i];
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

class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot(this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: JC.textMuted, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? JC.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFamily: 'Heebo',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
                color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo'),
          ),
        ],
      ),
    );
  }
}

class _AgentStatusGroup extends StatefulWidget {
  final String label;
  final int count;
  final Color dotColor;
  final List<Map<String, dynamic>> agents;

  const _AgentStatusGroup({
    required this.label,
    required this.count,
    required this.dotColor,
    required this.agents,
  });

  @override
  State<_AgentStatusGroup> createState() => _AgentStatusGroupState();
}

class _AgentStatusGroupState extends State<_AgentStatusGroup> {
  bool _expanded = true;

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: widget.dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.dotColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        color: widget.dotColor,
                        fontSize: 10,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: JC.textMuted,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(color: JC.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.6,
                ),
                itemCount: widget.agents.length,
                itemBuilder: (_, i) => _AgentMiniCard(widget.agents[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentMiniCard extends StatelessWidget {
  final Map<String, dynamic> agent;

  const _AgentMiniCard(this.agent);

  @override
  Widget build(BuildContext context) {
    final name = agent['name'] ?? agent['id'] ?? 'סוכן';
    final role = agent['description'] ?? agent['role'] ?? '';
    final risk = agent['riskLevel'] ?? agent['risk_level'] ?? 'low';
    final status = (agent['status'] ?? '').toString();
    final riskColor = _riskColor(risk);
    final statusColor = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1929),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
        border: Border.all(color: statusColor.withOpacity(0.15), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, color: JC.blue400, size: 14),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  name.toString(),
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              role.toString(),
              style: TextStyle(
                  color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _riskLabel(risk),
              style: TextStyle(
                  color: riskColor, fontSize: 9, fontFamily: 'Heebo'),
            ),
          ),
        ],
      ),
    );
  }
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

// ── Agent Tree CustomPainter ──────────────────────────────────────────────────

class _AgentTreePainter extends CustomPainter {
  final List<Map<String, dynamic>> agents;
  final int? selectedIdx;

  static const _catGreen  = Color(0xFF22C55E);
  static const _catAmber  = Color(0xFFF59E0B);
  static const _catPurple = Color(0xFFA78BFA);
  static const _rootBlue  = Color(0xFF3B82F6);
  static const _edgeColor = Color(0x22FFFFFF);

  const _AgentTreePainter({required this.agents, this.selectedIdx});

  // Returns list of (agentIndex, canvasPosition) for tap-hit-testing
  static List<(int, Offset)> agentPositions(
      List<Map<String, dynamic>> agents, Size size) {
    final w = size.width;

    final core    = <int>[];
    final domain  = <int>[];
    final quality = <int>[];

    for (var i = 0; i < agents.length; i++) {
      switch (_agentCat(agents[i])) {
        case 'core':    core.add(i);    break;
        case 'quality': quality.add(i); break;
        default:        domain.add(i);  break;
      }
    }

    final catAgents  = [core, domain, quality];
    final catCentersX = [w * 0.78, w * 0.50, w * 0.22];
    const agentY = 175.0;
    const spread = 72.0;

    final result = <(int, Offset)>[];
    for (var c = 0; c < 3; c++) {
      final list = catAgents[c].take(7).toList();
      if (list.isEmpty) continue;
      final cx = catCentersX[c];
      final step = list.length == 1 ? 0.0 : spread / (list.length - 1);
      final startX = cx - spread / 2;
      for (var j = 0; j < list.length; j++) {
        result.add((list[j], Offset(startX + step * j, agentY)));
      }
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;

    final core    = <int>[];
    final domain  = <int>[];
    final quality = <int>[];
    for (var i = 0; i < agents.length; i++) {
      switch (_agentCat(agents[i])) {
        case 'core':    core.add(i);    break;
        case 'quality': quality.add(i); break;
        default:        domain.add(i);  break;
      }
    }

    final rootPt = Offset(w * 0.5, 28);

    final catDefs = [
      (pt: Offset(w * 0.78, 95), label: 'ליבה',   color: _catGreen,  idxs: core),
      (pt: Offset(w * 0.50, 95), label: 'דומיין', color: _catAmber,  idxs: domain),
      (pt: Offset(w * 0.22, 95), label: 'איכות',  color: _catPurple, idxs: quality),
    ];

    final edgePaint = Paint()
      ..color = _edgeColor
      ..strokeWidth = 1.0;

    // Root → category edges
    for (final cat in catDefs) {
      canvas.drawLine(rootPt, cat.pt, edgePaint);
    }

    // Category → agent edges and agent nodes
    final positions = agentPositions(agents, size);
    final posMap = {for (final p in positions) p.$1: p.$2};

    for (final cat in catDefs) {
      for (final idx in cat.idxs.take(7)) {
        final agentPt = posMap[idx];
        if (agentPt == null) continue;
        canvas.drawLine(cat.pt, agentPt, edgePaint);

        final a = agents[idx];
        final status = (a['status'] ?? '').toString().toLowerCase();
        final agentColor = (status == 'active' || status == 'online')
            ? const Color(0xFF22C55E)
            : status == 'idle'
                ? const Color(0xFFF59E0B)
                : const Color(0xFF475569);

        final isSelected = idx == selectedIdx;
        if (isSelected) {
          canvas.drawCircle(agentPt, 11, Paint()..color = agentColor.withOpacity(0.3));
        }
        canvas.drawCircle(agentPt, 5.5, Paint()..color = agentColor);

        // Agent name label (truncated)
        final agentName = (a['name'] ?? a['id'] ?? '').toString();
        final short = agentName.length > 8 ? '${agentName.substring(0, 7)}…' : agentName;
        final labelTp = TextPainter(
          text: TextSpan(
            text: short,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF64748B),
              fontSize: 7,
              fontFamily: 'Heebo',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 60);
        labelTp.paint(canvas, agentPt.translate(-labelTp.width / 2, 7));
      }
    }

    // Category nodes (drawn on top of edges)
    for (final cat in catDefs) {
      canvas.drawCircle(cat.pt, 16, Paint()..color = cat.color.withOpacity(0.15));
      canvas.drawCircle(cat.pt, 11, Paint()..color = cat.color);

      final tp = TextPainter(
        text: TextSpan(
          text: cat.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            fontFamily: 'Heebo',
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, cat.pt.translate(-tp.width / 2, 13));

      // Agent count badge
      final cnt = cat.idxs.length;
      if (cnt > 0) {
        final cntTp = TextPainter(
          text: TextSpan(
            text: '$cnt',
            style: TextStyle(color: cat.color, fontSize: 7, fontWeight: FontWeight.w700, fontFamily: 'Heebo'),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        cntTp.paint(canvas, cat.pt.translate(-cntTp.width / 2, -11 - cntTp.height / 2));
      }
    }

    // Root node
    canvas.drawCircle(rootPt, 21, Paint()..color = _rootBlue.withOpacity(0.2));
    canvas.drawCircle(rootPt, 15, Paint()..color = _rootBlue);

    final rootTp = TextPainter(
      text: const TextSpan(
        text: 'Jarvis',
        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700, fontFamily: 'Heebo'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rootTp.paint(canvas, rootPt.translate(-rootTp.width / 2, 17));
  }

  @override
  bool shouldRepaint(covariant _AgentTreePainter old) =>
      old.agents != agents || old.selectedIdx != selectedIdx;
}
