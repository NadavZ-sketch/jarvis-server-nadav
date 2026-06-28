import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_settings.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TabAgents — Slice 2 of the Control Center redesign.
//
// Renders:
//   A. "סוכנים חיים" — live list with toggles + expandable detail rows.
//   B. Expanded detail: mission, permission pills, memoryAccess pill, risk
//      pill, small metrics row, risk-level selector, and action buttons.
//   C. "הרשאות וסיכונים" — semantic permission pills shown inline in each
//      expanded agent detail (permissions[] with read/write/delete coloring).
//
// Optimistic mutations:
//   - toggleAgent: flips status locally, reverts + SnackBar on error.
//   - setAgentRisk: updates risk locally, reverts + SnackBar on error.
//
// Success % formula:
//   dashboard.tasksHandled > 0
//     ? ((tasksHandled - failures) / tasksHandled * 100).round()
//     : healthScore
//
// Polling: RefreshIndicator + adaptive 30 s timer (pause on background).
// ─────────────────────────────────────────────────────────────────────────────

class TabAgents extends StatefulWidget {
  final AppSettings settings;
  const TabAgents({super.key, required this.settings});

  @override
  State<TabAgents> createState() => _TabAgentsState();
}

class _TabAgentsState extends State<TabAgents>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = ApiService(widget.settings);

  List<Map<String, dynamic>> _agents = [];
  bool _loading = true;
  String? _error;

  // Which agent id is currently expanded
  String? _expandedId;

  // Polling
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _load();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agents = await _api.getAgents();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.friendlyError(e);
        _loading = false;
      });
    }
  }

  // ── Optimistic toggle ──────────────────────────────────────────────────────
  Future<void> _toggleAgent(int index) async {
    final agent = Map<String, dynamic>.from(_agents[index]);
    final oldStatus = agent['status'] as String? ?? 'disabled';
    final newStatus = oldStatus == 'active' ? 'disabled' : 'active';

    // Optimistic update
    setState(() {
      _agents[index] = {...agent, 'status': newStatus};
    });

    try {
      final result = await _api.toggleAgent(agent['id'] as String);
      final confirmedStatus = result['status'] as String? ?? newStatus;
      if (!mounted) return;
      setState(() {
        _agents[index] = {..._agents[index], 'status': confirmedStatus};
      });
    } catch (e) {
      if (!mounted) return;
      // Revert
      setState(() {
        _agents[index] = {..._agents[index], 'status': oldStatus};
      });
      _showError(ApiService.friendlyError(e));
    }
  }

  // ── Optimistic risk change ─────────────────────────────────────────────────
  Future<void> _setRisk(int index, String newRisk) async {
    final agent = _agents[index];
    final oldRisk = agent['risk'] as String? ?? 'low';
    if (oldRisk == newRisk) return;

    // Optimistic update
    setState(() {
      _agents[index] = {...agent, 'risk': newRisk};
    });

    try {
      await _api.setAgentRisk(agent['id'] as String, newRisk);
    } catch (e) {
      if (!mounted) return;
      // Revert
      setState(() {
        _agents[index] = {..._agents[index], 'risk': oldRisk};
      });
      _showError(ApiService.friendlyError(e));
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Heebo')),
        backgroundColor: JC.cancelRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: JC.cancelRed),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: JC.cancelRed, fontFamily: 'Heebo'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _load,
            child: const Text('נסה שוב',
                style: TextStyle(fontFamily: 'Heebo')),
          ),
        ]),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('סוכנים חיים'),
            const SizedBox(height: 8),
            ..._buildAgentList(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Agent list rows ────────────────────────────────────────────────────────
  List<Widget> _buildAgentList() {
    if (_agents.isEmpty) {
      return [
        _eventRow(
          accentColor: JC.textMuted,
          child: Text(
            'אין סוכנים זמינים',
            style: TextStyle(
                fontFamily: 'Heebo', fontSize: 13, color: JC.textMuted),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (int i = 0; i < _agents.length; i++) {
      final agent = _agents[i];
      final id = agent['id'] as String? ?? '$i';
      final isExpanded = _expandedId == id;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _agentRow(i, agent, isExpanded),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: _agentDetail(i, agent),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  // ── Single agent row ───────────────────────────────────────────────────────
  Widget _agentRow(int index, Map<String, dynamic> agent, bool isExpanded) {
    final nameHe = agent['nameHe'] as String? ?? '';
    final name = agent['name'] as String? ?? '—';
    final displayName = nameHe.isNotEmpty ? nameHe : name;
    final role = agent['role'] as String? ?? '';
    final metrics = agent['metrics'] as Map<String, dynamic>? ?? {};
    final count = (metrics['count'] as num?)?.toInt() ?? 0;
    final avgMs = (metrics['avgMs'] as num?)?.toInt() ?? 0;
    final status = agent['status'] as String? ?? 'disabled';
    final isActive = status == 'active';

    final avatarChar = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : '?';

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedId = isExpanded ? null : (agent['id'] as String?);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JC.surface,
          border: Border.all(
            color: isExpanded
                ? JC.amber400.withOpacity(0.45)
                : JC.border.withOpacity(0.18),
          ),
          borderRadius: BorderRadius.only(
            topRight: const Radius.circular(12),
            topLeft: const Radius.circular(12),
            bottomRight: isExpanded ? Radius.zero : const Radius.circular(12),
            bottomLeft: isExpanded ? Radius.zero : const Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: JC.shadow.withOpacity(0.10),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.16),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: _statusColor(status).withOpacity(0.35), width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                avatarChar,
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: _statusColor(status),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: JC.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$role · $count קריאות · ${avgMs}ms',
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 11,
                      color: JC.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Toggle
            GestureDetector(
              onTap: () => _toggleAgent(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isActive
                      ? JC.green500.withOpacity(0.85)
                      : JC.border.withOpacity(0.3),
                ),
                padding: const EdgeInsets.all(3),
                alignment:
                    isActive ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Expanded detail panel ─────────────────────────────────────────────────
  Widget _agentDetail(int index, Map<String, dynamic> agent) {
    final nameHe = agent['nameHe'] as String? ?? '';
    final name = agent['name'] as String? ?? '—';
    final displayName = nameHe.isNotEmpty ? nameHe : name;
    final mission = agent['mission'] as String? ??
        agent['role'] as String? ??
        '';
    final permissions =
        List<String>.from(agent['permissions'] as List? ?? []);
    final memoryAccess = agent['memoryAccess'] as String? ?? '';
    final risk = agent['risk'] as String? ?? 'low';
    final status = agent['status'] as String? ?? 'disabled';
    final isActive = status == 'active';

    final metrics = agent['metrics'] as Map<String, dynamic>? ?? {};
    final avgMs = (metrics['avgMs'] as num?)?.toInt() ?? 0;

    final dashboard = agent['dashboard'] as Map<String, dynamic>? ?? {};
    final tasksHandled = (dashboard['tasksHandled'] as num?)?.toInt() ?? 0;
    final failures = (dashboard['failures'] as num?)?.toInt() ?? 0;
    final healthScore = (agent['healthScore'] as num?)?.toInt() ?? 0;

    final successPct = tasksHandled > 0
        ? ((tasksHandled - failures) / tasksHandled * 100).round()
        : healthScore;

    final prompt = agent['prompt'] as String? ?? '';
    final connections =
        List<Map<String, dynamic>>.from(agent['connections'] as List? ?? []);

    return Container(
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border(
          right: BorderSide(color: JC.amber400.withOpacity(0.45)),
          left: BorderSide(color: JC.amber400.withOpacity(0.45)),
          bottom: BorderSide(color: JC.amber400.withOpacity(0.45)),
        ),
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mission / description
          if (mission.isNotEmpty) ...[
            Text(
              mission,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 12,
                color: JC.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Permission pills
          if (permissions.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...permissions.map((p) => _permissionPill(p)),
                if (memoryAccess.isNotEmpty)
                  _pill(memoryAccess, JC.amber400),
                _riskPill(risk),
              ],
            ),
            const SizedBox(height: 12),
          ] else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (memoryAccess.isNotEmpty)
                  _pill(memoryAccess, JC.amber400),
                _riskPill(risk),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // Metrics row
          Row(
            children: [
              _miniMetric(
                label: 'הצלחה',
                value: '$successPct%',
                color: successPct >= 90
                    ? JC.green500
                    : successPct >= 70
                        ? JC.amber400
                        : JC.cancelRed,
              ),
              const SizedBox(width: 16),
              _miniMetric(
                label: 'תגובה',
                value: '${avgMs}ms',
                color: avgMs <= 500
                    ? JC.green500
                    : avgMs <= 1500
                        ? JC.amber400
                        : JC.cancelRed,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Risk control — 3-segment selector
          _riskSelector(index, risk),
          const SizedBox(height: 14),

          // Action buttons row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                label: isActive ? 'השבת' : 'הפעל',
                color: isActive ? JC.cancelRed : JC.green500,
                onPressed: () => _toggleAgent(index),
              ),
              _actionButton(
                label: 'פרומפט',
                color: JC.blue400,
                onPressed: () => _showPromptDialog(context, displayName, prompt),
              ),
              _actionButton(
                label: 'חיבורים',
                color: JC.amber400,
                onPressed: () =>
                    _showConnectionsDialog(context, displayName, connections),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section header (gold + gradient line, mirrors tab_overview) ────────────
  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Heebo',
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: JC.amber400,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [JC.amber400.withOpacity(0.34), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Event row (mirrors tab_overview) ──────────────────────────────────────
  Widget _eventRow({required Color accentColor, required Widget child}) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        border: Border.all(color: JC.border.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action button (mirrors tab_overview) ──────────────────────────────────
  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.42)),
        backgroundColor: color.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
            fontFamily: 'Heebo', fontWeight: FontWeight.w900, fontSize: 11),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }

  // ── Risk level selector (3-segment) ───────────────────────────────────────
  Widget _riskSelector(int index, String currentRisk) {
    const levels = ['low', 'medium', 'high'];
    const labelsHe = ['נמוך', 'בינוני', 'גבוה'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'סיכון: ',
          style: TextStyle(
              fontFamily: 'Heebo', fontSize: 11, color: JC.textMuted),
        ),
        const SizedBox(width: 6),
        ...List.generate(levels.length, (i) {
          final level = levels[i];
          final label = labelsHe[i];
          final isSelected = currentRisk == level;
          final color = _riskColor(level);
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => _setRisk(index, level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? color : JC.border.withOpacity(0.3),
                    width: isSelected ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w400,
                    color: isSelected ? color : JC.textMuted,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Permission pill with semantic color ───────────────────────────────────
  Widget _permissionPill(String permission) {
    final lower = permission.toLowerCase();
    Color color;
    if (lower.contains('delete') ||
        lower.contains('מחיק') ||
        lower.contains('approval') ||
        lower.contains('אישור')) {
      color = JC.cancelRed;
    } else if (lower.contains('write') ||
        lower.contains('כתיב') ||
        lower.contains('update') ||
        lower.contains('עדכון') ||
        lower.contains('create') ||
        lower.contains('יצירה')) {
      color = JC.amber400;
    } else {
      color = JC.blue400;
    }
    return _pill(permission, color);
  }

  Widget _riskPill(String risk) {
    final color = _riskColor(risk);
    final label = _riskLabelHe(risk);
    return _pill(label, color);
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.38)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ── Mini metric box (inline in detail) ───────────────────────────────────
  Widget _miniMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Heebo', fontSize: 10, color: JC.textMuted)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            )),
      ],
    );
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showPromptDialog(
      BuildContext context, String agentName, String prompt) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: Text(
            'פרומפט — $agentName',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w900,
              color: JC.amber400,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Text(
                prompt.isEmpty ? 'אין פרומפט' : prompt,
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 13,
                  color: prompt.isEmpty ? JC.textMuted : JC.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('סגור',
                  style:
                      TextStyle(fontFamily: 'Heebo', color: JC.blue400)),
            ),
          ],
        ),
      ),
    );
  }

  void _showConnectionsDialog(
    BuildContext context,
    String agentName,
    List<Map<String, dynamic>> connections,
  ) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: JC.surface,
          title: Text(
            'חיבורים — $agentName',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w900,
              color: JC.amber400,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: connections.isEmpty
                ? Text(
                    'אין חיבורים',
                    style: TextStyle(
                        fontFamily: 'Heebo', color: JC.textMuted),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: connections.map((c) {
                        final connName =
                            (c['nameHe'] as String? ?? '').isNotEmpty
                                ? c['nameHe'] as String
                                : (c['name'] as String? ?? '—');
                        final direction =
                            c['direction'] as String? ?? '';
                        final type = c['type'] as String? ?? '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _eventRow(
                            accentColor: JC.blue400,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  connName,
                                  style: TextStyle(
                                    fontFamily: 'Heebo',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: JC.textPrimary,
                                  ),
                                ),
                                if (direction.isNotEmpty || type.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    [direction, type]
                                        .where((s) => s.isNotEmpty)
                                        .join(' · '),
                                    style: TextStyle(
                                      fontFamily: 'Heebo',
                                      fontSize: 11,
                                      color: JC.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('סגור',
                  style: TextStyle(fontFamily: 'Heebo', color: JC.blue400)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Colour helpers ────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return JC.green500;
      case 'disabled':
        return JC.textMuted;
      default:
        return JC.amber400; // 'custom' or unknown
    }
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'high':
        return JC.cancelRed;
      case 'medium':
        return JC.amber400;
      default:
        return JC.green500; // 'low'
    }
  }

  String _riskLabelHe(String risk) {
    switch (risk) {
      case 'high':
        return 'סיכון גבוה';
      case 'medium':
        return 'סיכון בינוני';
      default:
        return 'סיכון נמוך';
    }
  }
}
