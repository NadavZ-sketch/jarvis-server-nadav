import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_dialogs.dart';
import '../../screens/home/home_helpers.dart';

class TasksCard extends StatefulWidget {
  final HomeController c;
  const TasksCard(this.c, {super.key});

  @override
  State<TasksCard> createState() => _TasksCardState();
}

class _TasksCardState extends State<TasksCard> {
  final Set<String> _openGroups = {};
  final Set<String> _expandedTasks = {};

  HomeController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final done = c.doneTasks;
    final total = c.totalTasks;
    final open = c.openTasks;
    final progress = total == 0 ? 0.0 : done / total;

    bool isHigh(Map t) => (t['priority'] ?? '').toString().toLowerCase() == 'high';
    bool starred(Map t) => c.markedImportant.contains(t['id'].toString());

    final highTasks =
        c.tasks.where((t) => t['done'] != true && isHigh(t)).toList();
    final starredTasks = c.tasks
        .where((t) => t['done'] != true && !isHigh(t) && starred(t))
        .toList();
    final queueTasks = c.tasks
        .where((t) => t['done'] != true && !isHigh(t) && !starred(t))
        .toList();

    return SectionCard(
      title: 'משימות להיום ($open פתוחות)',
      icon: Icons.checklist_rounded,
      iconColor: const Color(0xFF3B82F6),
      headerTrailing: GestureDetector(
        onTap: () => showAddTaskDialog(context, c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.3), width: 0.8),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Color(0xFF3B82F6), size: 14),
            SizedBox(width: 3),
            Text('חדשה',
                style: TextStyle(
                    color: Color(0xFF3B82F6),
                    fontSize: 11,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(children: [
                Container(height: 5, color: JC.border),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(height: 5, color: JC.green500),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Text('$done/$total הושלמו',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ]),
        if (open == 0) ...[
          const SizedBox(height: 12),
          const EmptyState(message: 'כל המשימות הושלמו! 🎉'),
        ] else ...[
          const SizedBox(height: 12),
          if (highTasks.isNotEmpty)
            _group(context, 'high', 'דחוף', const Color(0xFFEF4444), highTasks),
          if (starredTasks.isNotEmpty)
            _group(context, 'starred', 'מסומן חשוב', const Color(0xFFF59E0B), starredTasks),
          if (queueTasks.isNotEmpty)
            _group(context, 'queue', 'בתור', const Color(0xFF3B82F6), queueTasks),
        ],
      ]),
    );
  }

  Widget _group(BuildContext context, String groupKey, String label, Color color,
      List<Map<String, dynamic>> tasks) {
    final isOpen = _openGroups.contains(groupKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Group header (always visible, tap to toggle) ──
        GestureDetector(
          onTap: () => setState(() {
            if (isOpen) {
              _openGroups.remove(groupKey);
            } else {
              _openGroups.add(groupKey);
            }
          }),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo')),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${tasks.length}',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo')),
              ),
              const Spacer(),
              Icon(
                isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                color: JC.textMuted,
                size: 16,
              ),
            ]),
          ),
        ),
        // ── Expanded task list ──
        if (isOpen) ...[
          const SizedBox(height: 4),
          ...tasks.map((t) => _row(context, t)),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> task) {
    final id = task['id'].toString();
    final content = task['content'] as String? ?? '—';
    final priority = task['priority'] as String?;
    final isHigh = (priority ?? '').toString().toLowerCase() == 'high';
    final isImportant = c.markedImportant.contains(id);
    final rowAccent = isHigh ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final subs = subtasksOf(task);
    final openSubs = subs.where((s) => s['done'] != true).length;
    final isExpanded = _expandedTasks.contains(id);

    // Due date formatting
    String dueLabel = '';
    final dueIso = task['due_date'] as String?;
    if (dueIso != null) {
      try {
        final dt = DateTime.parse(dueIso).toLocal();
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final dueDay = DateTime(dt.year, dt.month, dt.day);
        final hhmm =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        if (dueDay == today) {
          dueLabel = 'היום $hhmm';
        } else if (dueDay == DateTime(today.year, today.month, today.day - 1)) {
          dueLabel = 'אתמול';
        } else {
          dueLabel = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }
    final category = task['category'] as String?;

    return Dismissible(
      key: ValueKey('task-$id'),
      background: _swipeBg(AlignmentDirectional.centerStart,
          const Color(0xFF22C55E), Icons.check_rounded, 'השלם'),
      secondaryBackground: _swipeBg(AlignmentDirectional.centerEnd,
          const Color(0xFF3B82F6), Icons.schedule_rounded, 'דחה'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await tryCompleteTask(context, c, task);
          return false;
        } else {
          c.postponeTask(task);
          return false;
        }
      },
      child: GestureDetector(
        onTap: () => setState(() {
          if (isExpanded) {
            _expandedTasks.remove(id);
          } else {
            _expandedTasks.add(id);
          }
        }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: JC.jarvisBubble,
            borderRadius: BorderRadius.circular(10),
            border: BorderDirectional(start: BorderSide(color: rowAccent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Semantics(
                  button: true,
                  label: 'סיים משימה: $content',
                  child: GestureDetector(
                    onTap: () => tryCompleteTask(context, c, task),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.completing.contains(id)
                                  ? JC.green500
                                  : rowAccent,
                              width: 1.5,
                            ),
                            color: c.completing.contains(id)
                                ? JC.green500.withValues(alpha: 0.15)
                                : Colors.transparent,
                          ),
                          child: c.completing.contains(id)
                              ? Icon(Icons.check_rounded, size: 13, color: JC.green500)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    content,
                    maxLines: isExpanded ? null : 1,
                    overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 13,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: JC.textMuted,
                  size: 16,
                ),
                Semantics(
                  button: true,
                  label: isImportant ? 'מסומן חשוב' : 'סמן כחשוב',
                  child: GestureDetector(
                    onTap: isImportant ? null : () => c.markImportant(task),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Icon(
                          isImportant ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: isImportant ? JC.amber400 : JC.textMuted,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
              // ── Expanded detail row ──
              if (isExpanded) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (dueLabel.isNotEmpty)
                    _detailChip(Icons.schedule_rounded, dueLabel, JC.blue400),
                  if (category != null && category.isNotEmpty)
                    _detailChip(Icons.label_outline_rounded, category, JC.textMuted),
                  if (subs.isNotEmpty)
                    _detailChip(Icons.checklist_rounded,
                        '${subs.length - openSubs}/${subs.length} תתי-משימות',
                        openSubs > 0 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E)),
                ]),
              ] else if (subs.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.checklist_rounded, size: 11, color: JC.textMuted),
                  const SizedBox(width: 3),
                  Text('${subs.length - openSubs}/${subs.length} תתי-משימות',
                      style: TextStyle(
                          color: openSubs > 0
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF22C55E),
                          fontSize: 10,
                          fontFamily: 'Heebo')),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Future<void> tryCompleteTask(
      BuildContext context, HomeController c, Map<String, dynamic> task) async {
    final ok = await guardComplete(context, task);
    if (!mounted) return;
    if (ok) c.completeTask(task);
  }

  Widget _swipeBg(
      AlignmentDirectional align, Color color, IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: align,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
