import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_dialogs.dart';
import '../../screens/home/home_helpers.dart';

/// Important tasks with direct interaction: tap the circle or swipe to complete,
/// swipe the other way to postpone, star to mark important.
class TasksCard extends StatelessWidget {
  final HomeController c;
  const TasksCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final done = c.doneTasks;
    final total = c.totalTasks;
    final progress = total == 0 ? 0.0 : done / total;

    bool isHigh(Map t) => (t['priority'] ?? '').toString().toLowerCase() == 'high';
    bool starred(Map t) => c.markedImportant.contains(t['id'].toString());

    final highTasks =
        c.tasks.where((t) => t['done'] != true && isHigh(t)).toList();
    final starredTasks = c.tasks
        .where((t) => t['done'] != true && !isHigh(t) && starred(t))
        .toList();
    final otherCount = c.tasks
        .where((t) => t['done'] != true && !isHigh(t) && !starred(t))
        .length;

    final importantCount = highTasks.length + starredTasks.length;

    return SectionCard(
      title: 'משימות חשובות ($importantCount)',
      icon: Icons.priority_high_rounded,
      iconColor: const Color(0xFFEF4444),
      headerTrailing: GestureDetector(
        onTap: () => showAddTaskDialog(context, c),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.3), width: 0.8),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Color(0xFFEF4444), size: 14),
            SizedBox(width: 3),
            Text('חדשה',
                style: TextStyle(
                    color: Color(0xFFEF4444),
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
                Container(height: 5, color: const Color(0xFF1A2E4A)),
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(height: 5, color: const Color(0xFF22C55E)),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Text('$done/$total הושלמו',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ]),
        if (importantCount == 0) ...[
          const SizedBox(height: 12),
          EmptyState(
              message: total == done
                  ? 'כל המשימות הושלמו! 🎉'
                  : 'אין משימות דחופות כרגע'),
        ] else ...[
          const SizedBox(height: 12),
          if (highTasks.isNotEmpty)
            _group('דחוף', const Color(0xFFEF4444), highTasks),
          if (starredTasks.isNotEmpty)
            _group('מסומן חשוב ⭐', const Color(0xFFF59E0B), starredTasks),
        ],
        if (otherCount > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.inbox_outlined, color: JC.textMuted, size: 12),
            const SizedBox(width: 5),
            Text('+ $otherCount משימות נוספות בתור',
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ]),
        ],
      ]),
    );
  }

  Widget _group(String label, Color color, List<Map<String, dynamic>> tasks) {
    const maxShown = 4;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
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
          Text('${tasks.length}',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 10, fontFamily: 'Heebo')),
        ]),
        const SizedBox(height: 6),
        ...tasks.take(maxShown).map(_row),
        if (tasks.length > maxShown)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('+${tasks.length - maxShown} נוספות',
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> task) {
    final id = task['id'].toString();
    final content = task['content'] as String? ?? '—';
    final priority = task['priority'] as String?;
    final isHigh = (priority ?? '').toString().toLowerCase() == 'high';
    final isImportant = c.markedImportant.contains(id);
    final accent = isHigh ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);

    return Dismissible(
      key: ValueKey('task-$id'),
      // Swipe end→start (RTL: leftwards) completes; start→end postpones.
      background: _swipeBg(
          Alignment.centerRight, const Color(0xFF22C55E), Icons.check_rounded, 'השלם'),
      secondaryBackground: _swipeBg(Alignment.centerLeft,
          const Color(0xFF3B82F6), Icons.schedule_rounded, 'דחה'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          c.completeTask(task);
          return false; // controller handles removal + animation
        } else {
          c.postponeTask(task);
          return false;
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1929),
          borderRadius: BorderRadius.circular(10),
          border: Border(right: BorderSide(color: accent, width: 3)),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => c.completeTask(task),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.completing.contains(id)
                      ? const Color(0xFF22C55E)
                      : accent,
                  width: 1.5,
                ),
                color: c.completing.contains(id)
                    ? const Color(0xFF22C55E).withOpacity(0.15)
                    : Colors.transparent,
              ),
              child: c.completing.contains(id)
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Color(0xFF22C55E))
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(content,
                style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600,
                )),
          ),
          const SizedBox(width: 8),
          PriorityBadge(priority),
          GestureDetector(
            onTap: isImportant ? null : () => c.markImportant(task),
            child: Padding(
              padding: const EdgeInsets.only(right: 4, left: 2),
              child: Icon(
                isImportant ? Icons.star_rounded : Icons.star_outline_rounded,
                color: isImportant ? const Color(0xFFF59E0B) : JC.textMuted,
                size: 16,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _swipeBg(
      Alignment align, Color color, IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: align,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
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
