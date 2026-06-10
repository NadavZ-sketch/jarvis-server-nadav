import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';

class EisenhowerMatrix extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;
  final String projectId;
  final AppSettings settings;
  final ValueChanged<Map<String, dynamic>>? onTaskUpdated;

  const EisenhowerMatrix({
    super.key,
    required this.tasks,
    required this.projectId,
    required this.settings,
    this.onTaskUpdated,
  });

  @override
  State<EisenhowerMatrix> createState() => _EisenhowerMatrixState();
}

class _EisenhowerMatrixState extends State<EisenhowerMatrix> {
  late List<Map<String, dynamic>> _tasks;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.tasks.map((t) => Map<String, dynamic>.from(t)));
  }

  @override
  void didUpdateWidget(EisenhowerMatrix oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      setState(() {
        _tasks = List.from(widget.tasks.map((t) => Map<String, dynamic>.from(t)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _buildQuadrant('q1', 'Q1 — עשה עכשיו', 'דחוף + חשוב', JC.cancelRed),
                    _buildQuadrant('q2', 'Q2 — תכנן', 'חשוב, לא דחוף', JC.blue500),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildQuadrant('q3', 'Q3 — האצל', 'דחוף, לא חשוב', JC.amber400),
                    _buildQuadrant('q4', 'Q4 — בטל', 'לא דחוף, לא חשוב', JC.textMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
        _buildUnclassified(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: JC.surface,
      child: Row(
        children: [
          Expanded(child: _insightText()),
          TextButton.icon(
            icon: _aiLoading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: JC.amber400,
                    ),
                  )
                : Icon(Icons.auto_awesome, size: 15, color: JC.amber400),
            label: Text(
              'סיווג AI',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 12,
                color: JC.amber400,
              ),
            ),
            onPressed: _aiLoading ? null : _runAutoClassify,
          ),
        ],
      ),
    );
  }

  Widget _insightText() {
    final classified =
        _tasks.where((t) => t['eisenhower_quad'] != null).toList();
    if (classified.isEmpty) return const SizedBox.shrink();

    final q1 = classified.where((t) => t['eisenhower_quad'] == 'q1').length;
    if (q1 > classified.length * 0.6) {
      return Text(
        'רוב המשימות ב-Q1 — אתה פועל ריאקטיבית',
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 11.5,
          color: JC.amber400,
        ),
      );
    }

    final q4 = classified.where((t) => t['eisenhower_quad'] == 'q4').length;
    if (q4 > classified.length * 0.4) {
      return Text(
        'הרבה משימות ב-Q4 — שקול לבטל',
        style: TextStyle(
          fontFamily: 'Heebo',
          fontSize: 11.5,
          color: JC.textMuted,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildQuadrant(
      String quad, String title, String subtitle, Color color) {
    final quadrantTasks = _tasks
        .where((t) =>
            t['eisenhower_quad'] == quad && t['done'] != true)
        .toList();

    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
                border: Border(
                  bottom: BorderSide(color: color.withOpacity(0.2)),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 11,
                      color: JC.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: quadrantTasks
                    .map((t) => _buildTaskTile(t, color))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(Map<String, dynamic> task, Color color) {
    return GestureDetector(
      onLongPress: () => _showReassignSheet(task),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: JC.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border(right: BorderSide(color: color, width: 2)),
        ),
        child: Text(
          task['content'] as String? ?? '',
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 11.5,
            color: JC.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildUnclassified() {
    final unclassified = _tasks
        .where((t) =>
            t['eisenhower_quad'] == null && t['done'] != true)
        .toList();
    if (unclassified.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: JC.surface,
        border: Border(top: BorderSide(color: JC.bg)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'לא מסווג (${unclassified.length})',
              style: TextStyle(
                fontFamily: 'Heebo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: JC.textMuted,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: unclassified.length,
              itemBuilder: (ctx, i) {
                final t = unclassified[i];
                return GestureDetector(
                  onTap: () => _showReassignSheet(t),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: JC.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: JC.textMuted.withOpacity(0.2)),
                    ),
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      t['content'] as String? ?? '',
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 11.5,
                        color: JC.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showReassignSheet(Map<String, dynamic> task) {
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
              'סווג משימה',
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
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.5,
              children: [
                _quadrantChip('q1', 'Q1 עשה עכשיו', JC.cancelRed, task, ctx),
                _quadrantChip('q2', 'Q2 תכנן', JC.blue500, task, ctx),
                _quadrantChip('q3', 'Q3 האצל', JC.amber400, task, ctx),
                _quadrantChip('q4', 'Q4 בטל', JC.textMuted, task, ctx),
              ],
            ),
            const SizedBox(height: 8),
            if (task['eisenhower_quad'] != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _assignQuad(task, null);
                },
                child: Text(
                  'הסר סיווג',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    color: JC.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _quadrantChip(
      String quad,
      String label,
      Color color,
      Map<String, dynamic> task,
      BuildContext ctx) {
    final isSelected = task['eisenhower_quad'] == quad;
    return GestureDetector(
      onTap: () {
        Navigator.pop(ctx);
        _assignQuad(task, quad);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : JC.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Heebo',
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _assignQuad(Map<String, dynamic> task, String? quad) async {
    final prev = task['eisenhower_quad'];
    setState(() => task['eisenhower_quad'] = quad);
    try {
      await ApiService(widget.settings)
          .updateTaskEisenhower(task['id']?.toString() ?? '', quad);
      widget.onTaskUpdated?.call(task);
    } catch (_) {
      setState(() => task['eisenhower_quad'] = prev);
    }
  }

  Future<void> _runAutoClassify() async {
    setState(() => _aiLoading = true);
    final activeTasks =
        _tasks.where((t) => t['done'] != true).toList();
    if (activeTasks.isEmpty) {
      setState(() => _aiLoading = false);
      return;
    }

    final taskList =
        activeTasks.map((t) => '"${t['content']}"').join(', ');
    final message =
        'סווג את המשימות הבאות לפי מטריצת אייזנהאואר '
        '(q1=דחוף+חשוב, q2=חשוב, q3=דחוף, q4=שאר): $taskList. '
        'החזר JSON בלבד: {"classifications":[{"task":"...","quad":"q1"},...]}';

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
              'settings': {},
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final answer = data['answer'] as String? ?? '';
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(answer);

      if (match != null) {
        try {
          final parsed =
              jsonDecode(match.group(0)!) as Map<String, dynamic>;
          final classifications =
              (parsed['classifications'] as List?) ?? [];

          for (final c in classifications) {
            final taskName = c['task'] as String? ?? '';
            final quad = c['quad'] as String? ?? '';
            if (taskName.isEmpty ||
                !['q1', 'q2', 'q3', 'q4'].contains(quad)) {
              continue;
            }
            final minLen =
                (taskName.length * 0.7).round().clamp(3, taskName.length);
            final prefix = taskName.substring(0, minLen);
            final matching = _tasks
                .where((t) =>
                    (t['content'] as String? ?? '').contains(prefix))
                .toList();
            if (matching.isNotEmpty) {
              await _assignQuad(matching.first, quad);
            }
          }
        } catch (_) {}
      }
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

    if (mounted) setState(() => _aiLoading = false);
  }
}
