import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../widgets/preview_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Risk / status helpers
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

// ─────────────────────────────────────────────────────────────────────────────
// Demo data for non-existent backend sections
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
    extends State<ControlCenterPreviewScreen> {
  late final ApiService _api;

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

  // Survey state
  final Map<String, String?> _surveyAnswers = {};
  bool _surveySubmitted = false;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.settings);
    _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadStats(), _loadAgents(), _loadIssues(), _loadSurvey()]);
  }

  Future<void> _loadStats() async {
    try {
      final s = await _api.getStats();
      if (mounted) setState(() { _stats = s; _loadingStats = false; });
    } catch (e) {
      if (mounted) setState(() { _statsError = ApiService.friendlyError(e); _loadingStats = false; });
    }
  }

  Future<void> _loadAgents() async {
    try {
      final a = await _api.getAgents();
      if (mounted) setState(() { _agents = a; _loadingAgents = false; });
    } catch (e) {
      if (mounted) setState(() { _agentsError = ApiService.friendlyError(e); _loadingAgents = false; });
    }
  }

  Future<void> _loadIssues() async {
    try {
      final reports = await _api.getE2eReports();
      if (mounted) setState(() { _issues = reports.take(5).toList(); _loadingIssues = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingIssues = false; });
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
      if (mounted) setState(() { _survey = _demoSurveyQuestions; _useDemoSurvey = true; });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 16,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: JC.textSecondary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'מרכז שליטה',
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo',
                ),
              ),
              Text(
                'Control Center · Preview',
                style: TextStyle(
                  color: JC.textMuted,
                  fontSize: 11,
                  fontFamily: 'Heebo',
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: JC.textSecondary, size: 22),
              onPressed: () {
                setState(() {
                  _loadingStats = true;
                  _loadingAgents = true;
                  _loadingIssues = true;
                  _statsError = null;
                  _agentsError = null;
                });
                _load();
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: JC.blue400,
                backgroundColor: JC.surface,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _StatusSection(),
                    const SizedBox(height: 20),
                    _IssuesSection(),
                    const SizedBox(height: 20),
                    _AgentsSection(),
                    const SizedBox(height: 20),
                    _FeaturesSection(),
                    const SizedBox(height: 20),
                    _SurveySection(),
                    SizedBox(height: bottomPad + 8),
                  ],
                ),
              ),
            ),
            const PreviewBanner(),
          ],
        ),
      ),
    );
  }

  // ── Section: Status ────────────────────────────────────────────────────────

  Widget _StatusSection() {
    return _SectionCard(
      title: 'סטטוס מערכת',
      icon: Icons.monitor_heart_rounded,
      iconColor: const Color(0xFF22C55E),
      child: _loadingStats
          ? const _SectionLoader()
          : _statsError != null
              ? _ErrorText(_statsError!)
              : _StatsGrid(_stats ?? {}),
    );
  }

  Widget _StatsGrid(Map<String, dynamic> s) {
    final totalMessages = s['total_messages'] ?? s['totalMessages'] ?? '—';
    final agentCount = _agents.isNotEmpty ? _agents.length : (s['agents'] ?? '—');
    final issueCount = _issues.length;
    final serverOk = _statsError == null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(label: 'שרת', value: serverOk ? 'פעיל ✓' : 'שגיאה', valueColor: serverOk ? const Color(0xFF22C55E) : const Color(0xFFEF4444))),
            const SizedBox(width: 10),
            Expanded(child: _StatTile(label: 'הודעות', value: '$totalMessages')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'סוכנים', value: '$agentCount')),
            const SizedBox(width: 10),
            Expanded(child: _StatTile(label: 'תקלות פתוחות', value: '$issueCount', valueColor: issueCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E))),
          ],
        ),
      ],
    );
  }

  // ── Section: Issues ────────────────────────────────────────────────────────

  Widget _IssuesSection() {
    if (!_loadingIssues && _issues.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'מה דורש טיפול עכשיו',
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: _loadingIssues
          ? const _SectionLoader()
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
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report_outlined, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: JC.textPrimary, fontSize: 13, fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                if (ts.isNotEmpty)
                  Text(_shortDate(ts), style: const TextStyle(color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
              ],
            ),
          ),
          _StatusChip(status),
        ],
      ),
    );
  }

  // ── Section: Agents ────────────────────────────────────────────────────────

  Widget _AgentsSection() {
    return _SectionCard(
      title: 'סוכנים פעילים',
      icon: Icons.hub_rounded,
      iconColor: JC.blue400,
      headerTrailing: _agentFilter.isNotEmpty
          ? GestureDetector(
              onTap: () => setState(() => _agentFilter = ''),
              child: const Text('נקה', style: TextStyle(color: JC.blue400, fontSize: 12, fontFamily: 'Heebo')),
            )
          : null,
      child: Column(
        children: [
          // Search bar
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1929),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: JC.border, width: 0.8),
            ),
            child: TextField(
              textDirection: TextDirection.rtl,
              style: const TextStyle(color: JC.textPrimary, fontSize: 13, fontFamily: 'Heebo'),
              decoration: const InputDecoration(
                hintText: 'חיפוש סוכן...',
                hintStyle: TextStyle(color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo'),
                prefixIcon: Icon(Icons.search_rounded, color: JC.textMuted, size: 18),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _agentFilter = v.toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          _loadingAgents
              ? const _SectionLoader()
              : _agentsError != null
                  ? _ErrorText(_agentsError!)
                  : _agents.isEmpty
                      ? const _EmptyState(message: 'לא נמצאו סוכנים')
                      : _AgentGrid(),
        ],
      ),
    );
  }

  Widget _AgentGrid() {
    final filtered = _agentFilter.isEmpty
        ? _agents
        : _agents.where((a) {
            final name = (a['name'] ?? a['id'] ?? '').toString().toLowerCase();
            final role = (a['description'] ?? a['role'] ?? '').toString().toLowerCase();
            return name.contains(_agentFilter) || role.contains(_agentFilter);
          }).toList();

    if (filtered.isEmpty) {
      return const _EmptyState(message: 'לא נמצאו סוכנים תואמים');
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: filtered.length,
      itemBuilder: (_, i) => _AgentCard(agent: filtered[i]),
    );
  }

  // ── Section: Feature Ideas ─────────────────────────────────────────────────

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

  // ── Section: Survey ────────────────────────────────────────────────────────

  Widget _SurveySection() {
    return _SectionCard(
      title: 'סקר חכם',
      icon: Icons.quiz_outlined,
      iconColor: const Color(0xFF93C5FD),
      headerTrailing: _useDemoSurvey ? const DemoChip() : null,
      child: _surveySubmitted
          ? const _EmptyState(message: 'תודה! התשובות נשמרו 🙏')
          : Column(
              children: [
                ..._survey.map((q) => _SurveyQuestionCard(
                      question: q,
                      selected: _surveyAnswers[q['id'] as String?],
                      onSelect: (ans) => setState(
                          () => _surveyAnswers[q['id'] as String] = ans),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('שלח תשובות',
                        style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

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
        border: Border.all(color: JC.border, width: 0.8),
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
                    style: const TextStyle(
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
          const Divider(color: JC.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1929),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                color: valueColor ?? JC.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Heebo',
              )),
        ],
      ),
    );
  }
}

class _AgentCard extends StatefulWidget {
  final Map<String, dynamic> agent;

  const _AgentCard({required this.agent});

  @override
  State<_AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<_AgentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.agent;
    final name = a['name'] ?? a['id'] ?? 'סוכן';
    final role = a['description'] ?? a['role'] ?? '';
    final status = a['status'] ?? 'active';
    final risk = a['riskLevel'] ?? a['risk_level'] ?? 'low';
    final autonomy = a['autonomyLevel'] ?? a['autonomy'] ?? '—';
    final perms = a['permissions'];

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _expanded ? JC.blue500 : JC.border,
            width: _expanded ? 1.0 : 0.6,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: JC.blue500.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.smart_toy_outlined,
                      color: JC.blue400, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name.toString(),
                    style: const TextStyle(
                      color: JC.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (role.toString().isNotEmpty)
              Text(
                role.toString(),
                style: const TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const Spacer(),
            Row(
              children: [
                _StatusChip(status),
                const SizedBox(width: 6),
                _RiskBadge(risk),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              const Divider(color: JC.border, height: 1),
              const SizedBox(height: 8),
              _DetailRow(label: 'אוטונומיה', value: autonomy.toString()),
              if (perms != null)
                _DetailRow(
                    label: 'הרשאות',
                    value: perms is List ? perms.join(', ') : perms.toString()),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: JC.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Heebo')),
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

class _RiskBadge extends StatelessWidget {
  final String risk;

  const _RiskBadge(this.risk);

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(risk);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_riskLabel(risk),
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
        border: Border.all(color: JC.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFA5B4FC), size: 22),
          const SizedBox(height: 8),
          Text(title,
              style: const TextStyle(
                  color: JC.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(desc,
              style: const TextStyle(
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
      {required this.question, required this.selected, required this.onSelect});

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
              style: const TextStyle(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: JC.blue400)),
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
            style: const TextStyle(
                color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo')),
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

String _shortDate(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day}/${dt.month}/${dt.year}';
  } catch (_) {
    return iso;
  }
}
