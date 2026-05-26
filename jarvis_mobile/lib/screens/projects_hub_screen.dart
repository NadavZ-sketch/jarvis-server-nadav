import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../transitions/slide_fade_route.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/empty_state.dart';
import '../widgets/markdown_lite.dart';
import 'project_detail_screen.dart';

// ─── ProjectsHubScreen ───────────────────────────────────────────────────────

class ProjectsHubScreen extends StatefulWidget {
  final AppSettings settings;
  const ProjectsHubScreen({super.key, required this.settings});

  @override
  State<ProjectsHubScreen> createState() => _ProjectsHubScreenState();
}

class _ProjectsHubScreenState extends State<ProjectsHubScreen> {
  List<Map<String, dynamic>> _projects = [];
  bool _loading = true;
  String? _error;
  String? _briefingText;
  bool _briefingLoading = false;
  List<Map<String, dynamic>> _risks = [];
  List<Map<String, dynamic>> _conflicts = [];
  Set<String> _dismissedRisks = {};
  String _filter = 'all';

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadDismissed();
    _loadBriefingCache();
    _loadCache();
    _fetch();
  }

  // ─── Persistence helpers ───────────────────────────────────────────────────

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('dismissed_risks') ?? [];
      if (mounted) setState(() => _dismissedRisks = Set<String>.from(list));
    } catch (_) {}
  }

  Future<void> _saveDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('dismissed_risks', _dismissedRisks.toList());
    } catch (_) {}
  }

  Future<void> _loadBriefingCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString('weekly_briefing');
      final tsStr = prefs.getString('weekly_briefing_ts');
      if (text != null && tsStr != null) {
        final ts = DateTime.tryParse(tsStr);
        if (ts != null && DateTime.now().difference(ts).inDays < 7) {
          if (mounted) setState(() => _briefingText = text);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('projects');
    if (cached != null && mounted && _projects.isEmpty) {
      setState(() {
        _projects = cached;
        _loading = false;
      });
      _computeRisks();
      _computeConflicts();
    }
  }

  // ─── Data fetching ─────────────────────────────────────────────────────────

  Future<void> _fetch() async {
    if (_projects.isEmpty && mounted) setState(() => _loading = true);
    try {
      final data = await ApiService(widget.settings).getProjects();
      if (!mounted) return;
      setState(() {
        _projects = data;
        _loading = false;
        _error = null;
      });
      await CacheService.saveList('projects', data);
      _computeRisks();
      _computeConflicts();
    } catch (e) {
      if (!mounted) return;
      if (_projects.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'שגיאה בטעינת הפרויקטים';
        });
      } else {
        setState(() => _loading = false);
      }
    }
  }

  // ─── Risk computation ──────────────────────────────────────────────────────

  void _computeRisks() {
    final now = DateTime.now();
    final risks = <Map<String, dynamic>>[];

    for (final p in _projects) {
      final status = (p['status'] as String?) ?? '';
      if (status == 'completed' || status == 'archived') continue;

      final dueDateStr = p['due_date'] as String?;
      if (dueDateStr != null) {
        final dueDate = DateTime.tryParse(dueDateStr);
        if (dueDate != null) {
          final diff = dueDate.difference(now).inDays;
          if (diff < 0) {
            risks.add({
              'type': 'overdue',
              'message': '${p['name']} — חרג מהתאריך',
              'severity': 'critical',
              'key': 'overdue_${p['id']}',
            });
          } else if (diff <= 7) {
            risks.add({
              'type': 'near',
              'message': '${p['name']} — דדליין בעוד $diff ימים',
              'severity': 'warning',
              'key': 'near_${p['id']}',
            });
          }
        }
      }

      final createdAtStr = p['created_at'] as String?;
      if (createdAtStr != null) {
        final createdAt = DateTime.tryParse(createdAtStr);
        if (createdAt != null && now.difference(createdAt).inDays > 14) {
          final tasks = p['_tasks'] as List?;
          final milestones = p['_milestones'] as List?;
          if (tasks != null && milestones != null) {
            final progress = _computeProgress(p);
            if (progress < 0.3) {
              risks.add({
                'type': 'slow',
                'message': '${p['name']} — התקדמות איטית (${(progress * 100).round()}%)',
                'severity': 'warning',
                'key': 'slow_${p['id']}',
              });
            }
          }
        }
      }
    }

    final filtered = risks
        .where((r) => !_dismissedRisks.contains(r['key'] as String))
        .take(5)
        .toList();

    setState(() => _risks = filtered);
  }

  void _computeConflicts() {
    final dateCounts = <String, int>{};
    for (final p in _projects) {
      final status = (p['status'] as String?) ?? '';
      if (status == 'completed' || status == 'archived') continue;
      final dueDateStr = p['due_date'] as String?;
      if (dueDateStr == null) continue;
      final d = DateTime.tryParse(dueDateStr);
      if (d == null) continue;
      final key = '${d.day}.${d.month}.${d.year}';
      dateCounts[key] = (dateCounts[key] ?? 0) + 1;
    }

    final conflicts = <Map<String, dynamic>>[];
    for (final entry in dateCounts.entries) {
      if (entry.value >= 2) {
        final conflictKey = 'conflict_${entry.key}';
        if (!_dismissedRisks.contains(conflictKey)) {
          conflicts.add({
            'type': 'conflict',
            'message': '${entry.key} — ${entry.value} פרויקטים עם דדליין',
            'severity': 'warning',
            'key': conflictKey,
          });
        }
      }
    }

    setState(() => _conflicts = conflicts);
  }

  // ─── Weekly briefing ───────────────────────────────────────────────────────

  Future<void> _fetchBriefing() async {
    if (_briefingLoading) return;
    setState(() => _briefingLoading = true);

    final summaryParts = _projects.map((p) {
      final name = p['name'] ?? '';
      final status = p['status'] ?? '';
      final due = p['due_date'] != null ? ', דדליין: ${p['due_date']}' : '';
      return '$name (סטטוס: $status$due)';
    }).join('; ');

    final message =
        'ברייפינג שבועי על הפרויקטים שלי: $summaryParts. תן סיכום קצר מה קורה ומה חשוב לשים לב אליו השבוע.';

    try {
      final result =
          await ApiService(widget.settings).askJarvis(message, widget.settings);
      final text = (result['answer'] as String?) ?? '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weekly_briefing', text);
      await prefs.setString(
          'weekly_briefing_ts', DateTime.now().toIso8601String());
      if (mounted) setState(() {
        _briefingText = text;
        _briefingLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _briefingLoading = false);
    }
  }

  // ─── Methodology recommendation ────────────────────────────────────────────

  // ─── Create sheet ──────────────────────────────────────────────────────────

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreateProjectSheet(
        settings: widget.settings,
        onCreated: () {
          Navigator.pop(ctx);
          _fetch();
        },
      ),
    );
  }

  // ─── Computed helpers ──────────────────────────────────────────────────────

  double _computeProgress(Map<dynamic, dynamic> p) {
    final tasks = p['_tasks'] as List? ?? [];
    final milestones = p['_milestones'] as List? ?? [];
    final total = tasks.length + milestones.length;
    if (total == 0) return 0.0;
    final done = tasks.where((t) => t['done'] == true).length +
        milestones.where((m) => m['completed'] == true).length;
    return done / total;
  }

  String _dueDateLabel(Map<dynamic, dynamic> p) {
    final s = p['due_date'] as String?;
    if (s == null) return '';
    final d = DateTime.tryParse(s);
    if (d == null) return '';
    final diff = d.difference(DateTime.now()).inDays;
    if (diff < 0) return 'איחור ${diff.abs()} ימים';
    if (diff == 0) return 'היום!';
    if (diff <= 7) return 'עוד $diff ימים';
    return '${d.day}.${d.month}.${d.year}';
  }

  Color _dueDateColor(Map<dynamic, dynamic> p) {
    final s = p['due_date'] as String?;
    if (s == null) return JC.textMuted;
    final diff =
        DateTime.tryParse(s)?.difference(DateTime.now()).inDays ?? 999;
    if (diff < 0) return JC.cancelRed;
    if (diff <= 7) return JC.amber400;
    return JC.textMuted;
  }

  List<Map<String, dynamic>> get _filteredProjects {
    return _projects.where((p) {
      final status = (p['status'] as String?) ?? '';
      if (_filter == 'active') {
        return status == 'active' || status == 'paused' || status == 'planning';
      }
      if (_filter == 'completed') return status == 'completed';
      return true;
    }).toList();
  }

  String _filterLabel(String f) {
    switch (f) {
      case 'active':
        return 'פעיל';
      case 'completed':
        return 'הושלם';
      default:
        return 'הכל';
    }
  }

  int get _activeCount => _projects
      .where((p) =>
          (p['status'] as String?) == 'active' ||
          (p['status'] as String?) == 'paused')
      .length;

  int get _overdueCount =>
      _risks.where((r) => r['type'] == 'overdue').length;

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          centerTitle: false,
          title: const Text(
            'פרויקטים',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          foregroundColor: JC.textPrimary,
          actions: [
            if (_briefingLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.assignment_rounded),
                tooltip: 'ברייפינג שבועי',
                onPressed: _fetchBriefing,
                color: JC.textSecondary,
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'רענן',
              onPressed: _fetch,
              color: JC.textSecondary,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showCreateSheet,
          backgroundColor: JC.blue500,
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
        body: _loading && _projects.isEmpty
            ? const LoadingSkeleton(itemCount: 4, itemHeight: 88)
            : _error != null && _projects.isEmpty
                ? EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'לא ניתן לטעון פרויקטים',
                    subtitle: _error!,
                  )
                : CustomScrollView(
                    slivers: [
                      // Stats row
                      SliverToBoxAdapter(child: _buildStatsRow()),

                      // Briefing card
                      if (_briefingText != null)
                        SliverToBoxAdapter(child: _buildBriefingCard()),

                      // Risk + conflict cards
                      if (_risks.isNotEmpty || _conflicts.isNotEmpty)
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) {
                              final all = [..._risks, ..._conflicts];
                              final risk = all[i];
                              return _buildRiskCard(risk);
                            },
                            childCount: _risks.length + _conflicts.length,
                          ),
                        ),

                      // Filter chips
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: _buildFilterChips(),
                        ),
                      ),

                      // Projects list
                      if (_filteredProjects.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: EmptyState(
                              icon: Icons.folder_open_rounded,
                              title: _filter == 'all'
                                  ? 'אין פרויקטים עדיין'
                                  : 'אין פרויקטים בקטגוריה זו',
                              subtitle: _filter == 'all'
                                  ? 'לחץ + כדי ליצור פרויקט חדש'
                                  : '',
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) =>
                                _buildProjectCard(_filteredProjects[i]),
                            childCount: _filteredProjects.length,
                          ),
                        ),

                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
      ),
    );
  }

  // ─── Stats row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildStatCard(
            value: '$_activeCount',
            label: 'פעילים',
            accent: JC.blue500,
          ),
          _buildStatCard(
            value: '—',
            label: 'משימות פתוחות',
            accent: JC.indigo500,
          ),
          _buildStatCard(
            value: '$_overdueCount',
            label: 'באיחור',
            accent: _overdueCount > 0 ? JC.cancelRed : JC.green500,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.bg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: accent,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 11,
                color: JC.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Briefing card ─────────────────────────────────────────────────────────

  Widget _buildBriefingCard() {
    return Dismissible(
      key: const ValueKey('briefing'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => setState(() => _briefingText = null),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            right: BorderSide(color: JC.blue500, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: JC.blue400, size: 16),
                const SizedBox(width: 6),
                Text(
                  'ברייפינג שבועי',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: JC.blue400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownLite(
              text: _briefingText!,
              baseStyle: TextStyle(
                fontSize: 13,
                color: JC.textSecondary,
                fontFamily: 'Heebo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Risk card ─────────────────────────────────────────────────────────────

  Widget _buildRiskCard(Map<String, dynamic> risk) {
    final severity = risk['severity'] as String? ?? 'warning';
    final isCritical = severity == 'critical';

    return Dismissible(
      key: ValueKey(risk['key']),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() => _dismissedRisks.add(risk['key'] as String));
        _saveDismissed();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            right: BorderSide(
              color: isCritical ? JC.cancelRed : JC.amber400,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isCritical
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              color: isCritical ? JC.cancelRed : JC.amber400,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                risk['message'] as String? ?? '',
                style: TextStyle(
                  fontSize: 12.5,
                  color: JC.textSecondary,
                  fontFamily: 'Heebo',
                ),
              ),
            ),
            Icon(Icons.chevron_left_rounded, color: JC.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  // ─── Filter chips ──────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: ['all', 'active', 'completed'].map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(
                _filterLabel(f),
                style: const TextStyle(fontFamily: 'Heebo', fontSize: 12),
              ),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f),
              selectedColor: JC.blue500.withValues(alpha: 0.2),
              backgroundColor: JC.surface,
              side: BorderSide(color: selected ? JC.blue500 : JC.bg),
              labelStyle:
                  TextStyle(color: selected ? JC.blue400 : JC.textMuted),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Project card ──────────────────────────────────────────────────────────

  Widget _buildProjectCard(Map<String, dynamic> p) {
    final colorStr = p['color'] as String? ?? '#3b82f6';
    final color = _parseColor(colorStr);
    final progress = _computeProgress(p);
    final methodology = p['methodology'] as String? ?? '';
    final priority = p['priority'] as String? ?? '';
    final dueDateLabel = _dueDateLabel(p);
    final dueDateColor = _dueDateColor(p);
    final status = _statusLabel(p['status'] as String? ?? '');

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        SlideFadeRoute(
          page: ProjectDetailScreen(
            project: p,
            settings: widget.settings,
            onRefresh: _fetch,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JC.bg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Color dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p['name'] as String? ?? '',
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: JC.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (methodology.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _buildMethodChip(methodology),
                ],
                if (priority.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _buildPriorityDot(priority),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: JC.bg,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor(p['status'] as String? ?? '')
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _statusColor(p['status'] as String? ?? '')
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          _statusColor(p['status'] as String? ?? ''),
                    ),
                  ),
                ),
                const Spacer(),
                if (dueDateLabel.isNotEmpty)
                  Text(
                    dueDateLabel,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 12,
                      color: dueDateColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Methodology chip ──────────────────────────────────────────────────────

  Widget _buildMethodChip(String methodology) {
    final color = _methodColor(methodology);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        _methodLabel(methodology),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          fontFamily: 'Heebo',
          color: color,
        ),
      ),
    );
  }

  // ─── Priority dot ──────────────────────────────────────────────────────────

  Widget _buildPriorityDot(String priority) {
    final color = _priorityColor(priority);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  // ─── Color & label helpers ─────────────────────────────────────────────────

  Color _methodColor(String m) {
    switch (m.toLowerCase()) {
      case 'kanban':
        return JC.blue500;
      case 'scrum':
        return JC.indigo500;
      case 'eisenhower':
        return JC.amber400;
      case 'gantt':
        return JC.green500;
      default:
        return JC.textMuted;
    }
  }

  String _methodLabel(String m) {
    switch (m.toLowerCase()) {
      case 'kanban':
        return 'Kanban';
      case 'scrum':
        return 'Scrum';
      case 'eisenhower':
        return 'Eisenhower';
      case 'gantt':
        return 'Gantt';
      default:
        return m;
    }
  }

  Color _priorityColor(String p) {
    switch (p.toLowerCase()) {
      case 'critical':
        return JC.cancelRed;
      case 'high':
        return JC.amber400;
      case 'medium':
        return JC.blue400;
      default:
        return JC.textMuted;
    }
  }

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'active':
        return 'פעיל';
      case 'paused':
        return 'מושהה';
      case 'completed':
        return 'הושלם';
      case 'planning':
        return 'בתכנון';
      case 'archived':
        return 'בארכיון';
      default:
        return s;
    }
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'active':
        return JC.green500;
      case 'paused':
        return JC.amber400;
      case 'completed':
        return JC.blue400;
      case 'planning':
        return JC.indigo300;
      case 'archived':
        return JC.textMuted;
      default:
        return JC.textMuted;
    }
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return JC.blue500;
    }
  }
}

// ─── _CreateProjectSheet ─────────────────────────────────────────────────────

class _CreateProjectSheet extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onCreated;

  const _CreateProjectSheet({
    required this.settings,
    required this.onCreated,
  });

  @override
  State<_CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends State<_CreateProjectSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _methodology = 'kanban';
  String _priority = 'medium';
  DateTime? _startDate;
  DateTime? _dueDate;
  String _color = '#3b82f6';
  bool _saving = false;

  bool _loadingRec = false;
  String? _methodRec;
  String? _methodRecReason;

  static const _colors = [
    '#6366f1',
    '#3b82f6',
    '#22c55e',
    '#f59e0b',
    '#ef4444',
    '#a78bfa',
    '#f472b6',
    '#06b6d4',
  ];

  static const _methodologies = ['kanban', 'scrum', 'eisenhower', 'gantt'];
  static const _priorities = ['low', 'medium', 'high', 'critical'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return JC.blue500;
    }
  }

  Color _methodColor(String m) {
    switch (m) {
      case 'kanban':
        return JC.blue500;
      case 'scrum':
        return JC.indigo500;
      case 'eisenhower':
        return JC.amber400;
      case 'gantt':
        return JC.green500;
      default:
        return JC.textMuted;
    }
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'kanban':
        return 'Kanban';
      case 'scrum':
        return 'Scrum';
      case 'eisenhower':
        return 'Eisenhower';
      case 'gantt':
        return 'Gantt';
      default:
        return m;
    }
  }

  String _methodIcon(String m) {
    switch (m) {
      case 'kanban':
        return '📋';
      case 'scrum':
        return '🔄';
      case 'eisenhower':
        return '🎯';
      case 'gantt':
        return '📊';
      default:
        return '📋';
    }
  }

  String _priorityLabel(String p) {
    switch (p) {
      case 'low':
        return 'נמוכה';
      case 'medium':
        return 'בינונית';
      case 'high':
        return 'גבוהה';
      case 'critical':
        return 'קריטי';
      default:
        return p;
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'critical':
        return JC.cancelRed;
      case 'high':
        return JC.amber400;
      case 'medium':
        return JC.blue400;
      default:
        return JC.textMuted;
    }
  }

  Future<void> _fetchMethodRec(String name, String desc) async {
    if (_loadingRec) return;
    setState(() => _loadingRec = true);

    final prompt =
        'הפרויקט: $name. $desc. איזו שיטת עבודה תמליץ: kanban/scrum/eisenhower/gantt? הסבר בקצרה. החזר JSON: {"methodology":"...","reason":"..."} בלבד.';

    try {
      final result =
          await ApiService(widget.settings).askJarvis(prompt, widget.settings);
      final answer = (result['answer'] as String?) ?? '';
      // Extract JSON from answer
      final jsonMatch = RegExp(r'\{[^}]+\}').firstMatch(answer);
      if (jsonMatch != null) {
        final parsed =
            jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final rec = (parsed['methodology'] as String? ?? '').toLowerCase();
        final reason = parsed['reason'] as String? ?? '';
        if (mounted) {
          setState(() {
            _methodRec = rec;
            _methodRecReason = reason;
            _loadingRec = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingRec = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRec = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    final body = <String, dynamic>{
      'name': name,
      if (_descCtrl.text.trim().isNotEmpty) 'description': _descCtrl.text.trim(),
      'methodology': _methodology,
      'priority': _priority,
      'color': _color,
      if (_startDate != null)
        'start_date': _startDate!.toIso8601String().substring(0, 10),
      if (_dueDate != null)
        'due_date': _dueDate!.toIso8601String().substring(0, 10),
      'status': 'planning',
    };

    try {
      await ApiService(widget.settings).createProject(body);
      widget.onCreated();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('שגיאה ביצירת הפרויקט')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: JC.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                'פרויקט חדש',
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: JC.textPrimary,
                ),
              ),
              const SizedBox(height: 20),

              // Name field
              _buildLabel('שם הפרויקט'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    fontFamily: 'Heebo', fontSize: 14, color: JC.textPrimary),
                decoration: InputDecoration(
                  hintText: 'לדוגמה: אפליקציה חדשה',
                  hintStyle:
                      TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
                  filled: true,
                  fillColor: JC.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: JC.bg),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: JC.bg),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: JC.blue500),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),

              // Description field
              _buildLabel('תיאור (אופציונלי)'),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                textDirection: TextDirection.rtl,
                maxLines: 2,
                style: TextStyle(
                    fontFamily: 'Heebo', fontSize: 14, color: JC.textPrimary),
                decoration: InputDecoration(
                  hintText: 'מה מטרת הפרויקט?',
                  hintStyle:
                      TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
                  filled: true,
                  fillColor: JC.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: JC.bg),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: JC.bg),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: JC.blue500),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Methodology selector
              _buildLabel('שיטת עבודה'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _methodologies.map((m) {
                  final selected = _methodology == m;
                  final color = _methodColor(m);
                  return GestureDetector(
                    onTap: () => setState(() => _methodology = m),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.2)
                            : JC.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? color.withValues(alpha: 0.6)
                              : JC.bg,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_methodIcon(m),
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            _methodLabel(m),
                            style: TextStyle(
                              fontFamily: 'Heebo',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? color : JC.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),

              // Jarvis recommendation
              TextButton.icon(
                icon: Icon(Icons.auto_awesome,
                    size: 16, color: JC.blue400),
                label: Text(
                  '💡 קבל המלצה מ-Jarvis',
                  style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 13,
                      color: JC.blue400),
                ),
                onPressed: _loadingRec
                    ? null
                    : () =>
                        _fetchMethodRec(_nameCtrl.text, _descCtrl.text),
              ),

              if (_methodRec != null && _methodRecReason != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: JC.green500.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: JC.green500.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline_rounded,
                          color: JC.green500, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Jarvis ממליץ: ${_methodLabel(_methodRec!)} — $_methodRecReason',
                          style: TextStyle(
                            fontFamily: 'Heebo',
                            fontSize: 12.5,
                            color: JC.green500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 8),

              // Priority selector
              _buildLabel('עדיפות'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _priorities.map((pr) {
                  final selected = _priority == pr;
                  final color = _priorityColor(pr);
                  return GestureDetector(
                    onTap: () => setState(() => _priority = pr),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.2)
                            : JC.bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? color.withValues(alpha: 0.6)
                              : JC.bg,
                        ),
                      ),
                      child: Text(
                        _priorityLabel(pr),
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? color : JC.textMuted,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Dates
              _buildLabel('תאריכים'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => _startDate = d);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: JC.bg,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _startDate != null
                            ? '${_startDate!.day}.${_startDate!.month}.${_startDate!.year}'
                            : 'תאריך התחלה',
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 13,
                          color: _startDate != null
                              ? JC.textPrimary
                              : JC.textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _dueDate ??
                              DateTime.now()
                                  .add(const Duration(days: 14)),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (d != null) setState(() => _dueDate = d);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: JC.bg,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _dueDate != null
                            ? '${_dueDate!.day}.${_dueDate!.month}.${_dueDate!.year}'
                            : 'דדליין',
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          fontSize: 13,
                          color: _dueDate != null
                              ? JC.textPrimary
                              : JC.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Color swatches
              _buildLabel('צבע'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: _colors.map((c) {
                  final isSelected = _color == c;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: _parseColor(c),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: Colors.white, width: 2)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                    color: _parseColor(c)
                                        .withValues(alpha: 0.5),
                                    blurRadius: 6)
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: JC.blue500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'צור פרויקט',
                          style: TextStyle(
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Heebo',
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: JC.textSecondary,
      ),
    );
  }
}
