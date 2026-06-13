import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../screens/create_sprint_sheet.dart';

class ScrumView extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> sprints;
  final String projectId;
  final AppSettings settings;
  final VoidCallback? onDataChanged;

  const ScrumView({
    super.key,
    required this.tasks,
    required this.sprints,
    required this.projectId,
    required this.settings,
    this.onDataChanged,
  });

  @override
  State<ScrumView> createState() => _ScrumViewState();
}

class _ScrumViewState extends State<ScrumView> {
  late List<Map<String, dynamic>> _tasks;
  late List<Map<String, dynamic>> _sprints;
  String? _selectedSprintId;
  bool _aiLoading = false;
  String? _aiSuggestion;

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.tasks.map((t) => Map<String, dynamic>.from(t)));
    _sprints = List.from(widget.sprints.map((s) => Map<String, dynamic>.from(s)));
    final active = _sprints.where((s) => s['status'] == 'active').toList();
    if (active.isNotEmpty) {
      _selectedSprintId = active.first['id'] as String?;
    }
  }

  @override
  void didUpdateWidget(ScrumView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks || oldWidget.sprints != widget.sprints) {
      setState(() {
        _tasks = List.from(widget.tasks.map((t) => Map<String, dynamic>.from(t)));
        _sprints = List.from(widget.sprints.map((s) => Map<String, dynamic>.from(s)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          _buildSprintSelector(),
          TabBar(
            tabs: const [Tab(text: 'ספרינט'), Tab(text: 'באקלוג')],
            labelColor: JC.blue400,
            unselectedLabelColor: JC.textMuted,
            indicatorColor: JC.blue500,
            labelStyle: const TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSprintTab(),
                _buildBacklogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSprintSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: JC.surface,
      child: Row(
        children: [
          Text(
            'ספרינט:',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600,
              color: JC.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButton<String?>(
              value: _selectedSprintId,
              dropdownColor: JC.surface,
              style: TextStyle(
                fontFamily: 'Heebo',
                color: JC.textPrimary,
                fontSize: 13,
              ),
              isExpanded: true,
              underline: const SizedBox(),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    'בחר ספרינט...',
                    style: TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
                  ),
                ),
                ..._sprints.map((s) => DropdownMenuItem<String?>(
                      value: s['id'] as String?,
                      child: Row(
                        children: [
                          _sprintStatusDot(s['status'] as String?),
                          const SizedBox(width: 6),
                          Text(
                            s['name'] as String? ?? '',
                            style: const TextStyle(
                              fontFamily: 'Heebo',
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedSprintId = v),
            ),
          ),
          TextButton(
            onPressed: _showCreateSprintSheet,
            child: Text(
              '+ ספרינט',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 12,
                color: JC.blue400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSprintTab() {
    if (_selectedSprintId == null) {
      return Center(
        child: Text(
          'בחר ספרינט מהרשימה',
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 14,
            color: JC.textMuted,
          ),
        ),
      );
    }

    final sprintList = _sprints.where((s) => s['id'] == _selectedSprintId).toList();
    if (sprintList.isEmpty) {
      return Center(
        child: Text(
          'הספרינט לא נמצא',
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 14,
            color: JC.textMuted,
          ),
        ),
      );
    }
    final sprint = sprintList.first;

    return ListView(
      children: [
        if (sprint['goal'] != null) _buildGoalCard(sprint['goal'] as String),
        _buildBurndownSection(sprint),
        _buildVelocitySection(),
        _buildSprintTasksList(sprint),
        _buildAISprintPlanner(),
        _buildSprintActions(sprint),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildGoalCard(String goal) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JC.blue500.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.blue500.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_rounded, size: 16, color: JC.blue400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              goal,
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 13,
                color: JC.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBurndownSection(Map<String, dynamic> sprint) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'גרף שריפה',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: JC.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  horizontalInterval: 10,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: JC.bg, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, m) => Text(
                        '${v.toInt()}',
                        style: TextStyle(
                          fontSize: 9,
                          color: JC.textMuted,
                          fontFamily: 'Heebo',
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (v, m) => Text(
                        '${v.toInt()}',
                        style: TextStyle(
                          fontSize: 9,
                          color: JC.textMuted,
                          fontFamily: 'Heebo',
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _idealBurndown(sprint),
                    isCurved: false,
                    color: JC.textMuted,
                    barWidth: 1.5,
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: _actualBurndown(sprint),
                    isCurved: false,
                    color: JC.blue400,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: JC.blue400.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legend(JC.textMuted, 'אידיאלי'),
              const SizedBox(width: 16),
              _legend(JC.blue400, 'בפועל'),
            ],
          ),
        ],
      ),
    );
  }

  List<FlSpot> _idealBurndown(Map<String, dynamic> sprint) {
    final start = DateTime.tryParse(sprint['start_date'] as String? ?? '') ?? DateTime.now();
    final end = DateTime.tryParse(sprint['end_date'] as String? ?? '') ??
        DateTime.now().add(const Duration(days: 14));
    final duration = end.difference(start).inDays;
    if (duration <= 0) return [const FlSpot(0, 0)];
    final sprintTasks = _tasks.where((t) => t['sprint_id'] == sprint['id']).toList();
    final total = sprintTasks.fold<int>(
        0, (s, t) => s + ((t['story_points'] as int?) ?? 1));
    if (total == 0) {
      return [FlSpot(0, 0), FlSpot(duration.toDouble(), 0)];
    }
    return List.generate(
      duration + 1,
      (i) => FlSpot(i.toDouble(), total * (1 - i / duration)),
    );
  }

  List<FlSpot> _actualBurndown(Map<String, dynamic> sprint) {
    final start = DateTime.tryParse(sprint['start_date'] as String? ?? '') ?? DateTime.now();
    final sprintTasks = _tasks.where((t) => t['sprint_id'] == sprint['id']).toList();
    final total = sprintTasks.fold<int>(
        0, (s, t) => s + ((t['story_points'] as int?) ?? 1));
    final today = DateTime.now();
    final daysSoFar = today.difference(start).inDays.clamp(0, 90);

    final Map<int, int> completedByDay = {};
    for (final t in sprintTasks) {
      if (t['done'] == true) {
        final updatedAt = DateTime.tryParse(t['updated_at'] as String? ?? '');
        if (updatedAt != null) {
          final dayIdx = updatedAt.difference(start).inDays;
          if (dayIdx >= 0) {
            completedByDay[dayIdx] =
                (completedByDay[dayIdx] ?? 0) + ((t['story_points'] as int?) ?? 1);
          }
        }
      }
    }

    final spots = <FlSpot>[];
    int remaining = total;
    for (int i = 0; i <= daysSoFar; i++) {
      remaining -= completedByDay[i] ?? 0;
      spots.add(FlSpot(
        i.toDouble(),
        remaining.toDouble().clamp(0, total.toDouble()),
      ));
    }
    return spots.isEmpty ? [FlSpot(0, total.toDouble())] : spots;
  }

  Widget _buildVelocitySection() {
    final completedSprints =
        _sprints.where((s) => s['status'] == 'completed').toList();
    if (completedSprints.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'מהירות (velocity)',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: JC.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (v, m) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= completedSprints.length) {
                          return const SizedBox.shrink();
                        }
                        final name =
                            (completedSprints[idx]['name'] as String? ?? '')
                                .split(' ')
                                .first;
                        return Text(
                          name,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'Heebo',
                            color: JC.textMuted,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: completedSprints.asMap().entries.map((e) {
                  final s = e.value;
                  final pts = _tasks
                      .where((t) =>
                          t['sprint_id'] == s['id'] && t['done'] == true)
                      .fold<int>(
                          0,
                          (sum, t) =>
                              sum + ((t['story_points'] as int?) ?? 1));
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: pts.toDouble(),
                        color: JC.indigo500,
                        width: 20,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSprintTasksList(Map<String, dynamic> sprint) {
    final sprintTasks =
        _tasks.where((t) => t['sprint_id'] == sprint['id']).toList();
    if (sprintTasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'אין משימות בספרינט זה עדיין',
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 13,
            color: JC.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'משימות ספרינט (${sprintTasks.length})',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: JC.textSecondary,
              ),
            ),
          ),
          ...sprintTasks.map((t) {
            final isDone = t['done'] == true;
            final pts = t['story_points'] as int?;
            return ListTile(
              dense: true,
              leading: Icon(
                isDone
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: isDone ? JC.green500 : JC.textMuted,
                size: 18,
              ),
              title: Text(
                t['content'] as String? ?? '',
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 13,
                  color: isDone ? JC.textMuted : JC.textPrimary,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              trailing: pts != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: JC.indigo500.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$pts',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Heebo',
                          color: JC.indigo300,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : null,
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildAISprintPlanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          if (_aiSuggestion != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: JC.indigo500.withOpacity(0.3)),
              ),
              child: Text(
                _aiSuggestion!,
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 13,
                  color: JC.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _aiLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: JC.indigo300,
                      ),
                    )
                  : Icon(Icons.auto_awesome, size: 16, color: JC.indigo300),
              label: Text(
                'תכנן ספרינט עם AI',
                style: TextStyle(
                  fontFamily: 'Heebo',
                  color: JC.indigo300,
                  fontSize: 13,
                ),
              ),
              onPressed: _aiLoading ? null : _runAISprintPlanner,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: JC.indigo500.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAISprintPlanner() async {
    setState(() => _aiLoading = true);
    final backlog = _tasks
        .where((t) => t['sprint_id'] == null && t['done'] != true)
        .toList();
    final taskList = backlog
        .map((t) => '"${t['content']}" (${t['story_points'] ?? '?'}נק)')
        .join(', ');
    final message = taskList.isEmpty
        ? 'תכנן ספרינט של 2 שבועות לפרויקט. אין משימות בבאקלוג כרגע. הצע מטרת ספרינט כללית.'
        : 'תכנן ספרינט של 2 שבועות לפרויקט. הבאקלוג: $taskList. אילו משימות לכלול? הצע מטרת ספרינט.';

    try {
      final res = await http
          .post(
            Uri.parse('${widget.settings.serverUrl}/ask-jarvis'),
            headers: {
              'Content-Type': 'application/json',
              'x-user-role': 'member',
              'x-user-plan': 'free',
              'x-user-consent': 'true',
            },
            body: jsonEncode({
              'message': message,
              'settings': widget.settings.toJson(),
            }),
          )
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final answer = data['answer'] as String? ?? '';
      setState(() {
        _aiSuggestion = answer.isNotEmpty ? answer : 'לא התקבלה הצעה מה-AI';
        _aiLoading = false;
      });
    } catch (e) {
      setState(() {
        _aiSuggestion = ApiService.friendlyError(e);
        _aiLoading = false;
      });
    }
  }

  Widget _buildSprintActions(Map<String, dynamic> sprint) {
    final status = sprint['status'] as String? ?? 'planned';

    if (status == 'completed') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: JC.green500.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: JC.green500.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: JC.green500, size: 16),
              const SizedBox(width: 6),
              Text(
                'הושלם',
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 13,
                  color: JC.green500,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: status == 'planned'
            ? ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text(
                  'התחל ספרינט',
                  style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                ),
                onPressed: () => _startSprint(sprint),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JC.blue500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              )
            : ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text(
                  'סיים ספרינט',
                  style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600),
                ),
                onPressed: () => _completeSprint(sprint),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JC.green500,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _startSprint(Map<String, dynamic> sprint) async {
    final sprintId = sprint['id'] as String? ?? '';
    if (sprintId.isEmpty) return;
    try {
      final updated = await ApiService(widget.settings)
          .startSprint(widget.projectId, sprintId);
      setState(() {
        final idx = _sprints.indexWhere((s) => s['id'] == sprintId);
        if (idx >= 0) _sprints[idx] = updated;
      });
      widget.onDataChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ApiService.friendlyError(e),
              style: const TextStyle(fontFamily: 'Heebo'),
            ),
            backgroundColor: JC.cancelRed,
          ),
        );
      }
    }
  }

  Future<void> _completeSprint(Map<String, dynamic> sprint) async {
    final sprintId = sprint['id'] as String? ?? '';
    if (sprintId.isEmpty) return;
    try {
      final updated = await ApiService(widget.settings)
          .completeSprint(widget.projectId, sprintId);
      setState(() {
        final idx = _sprints.indexWhere((s) => s['id'] == sprintId);
        if (idx >= 0) _sprints[idx] = updated;
      });
      widget.onDataChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ApiService.friendlyError(e),
              style: const TextStyle(fontFamily: 'Heebo'),
            ),
            backgroundColor: JC.cancelRed,
          ),
        );
      }
    }
  }

  Widget _buildBacklogTab() {
    final backlog = _tasks
        .where((t) => t['sprint_id'] == null && t['done'] != true)
        .toList();

    return ListView.builder(
      itemCount: backlog.length + 1,
      itemBuilder: (ctx, i) {
        if (i == backlog.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: Icon(Icons.add, color: JC.blue400),
              label: Text(
                'הוסף משימה לבאקלוג',
                style: TextStyle(fontFamily: 'Heebo', color: JC.blue400),
              ),
              onPressed: _showAddBacklogTaskSheet,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: JC.blue400.withOpacity(0.4)),
              ),
            ),
          );
        }

        final task = backlog[i];
        final pts = task['story_points'];

        return ListTile(
          title: Text(
            task['content'] as String? ?? '',
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 13,
              color: JC.textPrimary,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _showStoryPointsDialog(task),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: JC.indigo500.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pts?.toString() ?? '?',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Heebo',
                      color: JC.indigo300,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_sprints.any((s) => s['status'] != 'completed'))
                IconButton(
                  icon: Icon(
                    Icons.playlist_add,
                    color: JC.blue400,
                    size: 20,
                  ),
                  onPressed: () => _showAddToSprintDialog(task),
                  tooltip: 'הוסף לספרינט',
                ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateSprintSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, controller) => CreateSprintSheet(
          projectId: widget.projectId,
          settings: widget.settings,
          onCreated: () async {
            try {
              final sprints = await ApiService(widget.settings)
                  .getSprints(widget.projectId);
              if (mounted) {
                setState(() {
                  _sprints = sprints;
                });
                widget.onDataChanged?.call();
              }
            } catch (_) {}
          },
        ),
      ),
    );
  }

  void _showAddBacklogTaskSheet() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'משימה חדשה לבאקלוג',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: JC.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary),
              decoration: InputDecoration(
                hintText: 'תיאור המשימה...',
                hintStyle: TextStyle(fontFamily: 'Heebo', color: JC.textMuted),
                filled: true,
                fillColor: JC.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  Navigator.pop(ctx);
                  try {
                    final result = await ApiService(widget.settings)
                        .addTask(text, projectId: widget.projectId);
                    final task = result['task'] is Map
                        ? Map<String, dynamic>.from(
                            result['task'] as Map)
                        : result;
                    setState(() => _tasks.add(task));
                    widget.onDataChanged?.call();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ApiService.friendlyError(e),
                            style: const TextStyle(fontFamily: 'Heebo'),
                          ),
                          backgroundColor: JC.cancelRed,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: JC.blue500,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'הוסף',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStoryPointsDialog(Map<String, dynamic> task) {
    int? selected = task['story_points'] as int?;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surface,
        title: Text(
          'נקודות סיפור',
          style: TextStyle(
            fontFamily: 'Heebo',
            color: JC.textPrimary,
            fontSize: 15,
          ),
        ),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [1, 2, 3, 5, 8, 13, 21].map((pts) {
            final isSelected = selected == pts;
            return GestureDetector(
              onTap: () {
                selected = pts;
                Navigator.pop(ctx, pts);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? JC.indigo500.withOpacity(0.25)
                      : JC.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? JC.indigo500
                        : JC.textMuted.withOpacity(0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    '$pts',
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? JC.indigo300 : JC.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ).then((pts) async {
      if (pts == null) return;
      final prev = task['story_points'];
      setState(() => task['story_points'] = pts);
      try {
        await ApiService(widget.settings)
            .updateTaskStoryPoints(task['id']?.toString() ?? '', pts as int);
        widget.onDataChanged?.call();
      } catch (_) {
        setState(() => task['story_points'] = prev);
      }
    });
  }

  void _showAddToSprintDialog(Map<String, dynamic> task) {
    final availableSprints =
        _sprints.where((s) => s['status'] != 'completed').toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'הוסף לספרינט',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: JC.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              task['content'] as String? ?? '',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 13,
                color: JC.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ...availableSprints.map((s) {
              return ListTile(
                leading: _sprintStatusDot(s['status'] as String?),
                title: Text(
                  s['name'] as String? ?? '',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 14,
                    color: JC.textPrimary,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final sprintId = s['id'] as String? ?? '';
                  final prev = task['sprint_id'];
                  setState(() => task['sprint_id'] = sprintId);
                  try {
                    await ApiService(widget.settings)
                        .updateTaskSprint(task['id']?.toString() ?? '', sprintId);
                    widget.onDataChanged?.call();
                  } catch (_) {
                    setState(() => task['sprint_id'] = prev);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 3, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontFamily: 'Heebo',
            color: JC.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _sprintStatusDot(String? status) {
    final Color color;
    switch (status) {
      case 'active':
        color = JC.green500;
        break;
      case 'completed':
        color = JC.blue500;
        break;
      default:
        color = JC.textMuted;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
