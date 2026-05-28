import 'package:flutter/material.dart';
import '../../../main.dart' show JC;
import '../../../widgets/tasks/smart_task_card.dart';
import '../tasks_controller.dart';

const _kColumns = [
  ('todo', 'לעשות'),
  ('doing', 'בביצוע'),
  ('done', 'הושלם'),
];

class KanbanView extends StatelessWidget {
  final TasksController controller;
  const KanbanView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final cols = controller.kanbanColumns;
    final order = [
      for (final c in _kColumns) c.$1,
      ...cols.keys.where((k) => !_kColumns.any((c) => c.$1 == k)),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in order)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: _Column(
                controller: controller,
                id: id,
                label: _label(id),
                tasks: cols[id] ?? const [],
              ),
            ),
        ],
      ),
    );
  }

  String _label(String id) =>
      _kColumns.firstWhere((c) => c.$1 == id, orElse: () => (id, id)).$2;
}

class _Column extends StatelessWidget {
  final TasksController controller;
  final String id;
  final String label;
  final List<Map<String, dynamic>> tasks;
  const _Column({
    required this.controller,
    required this.id,
    required this.label,
    required this.tasks,
  });

  int get _sp {
    var sum = 0;
    for (final t in tasks) {
      final p = t['story_points'];
      if (p is num) sum += p.toInt();
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) =>
          (d.data['kanban_column'] ?? '').toString() != id,
      onAcceptWithDetails: (d) => controller.setKanbanColumn(d.data, id),
      builder: (ctx, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          width: 240,
          constraints: const BoxConstraints(minHeight: 120),
          decoration: BoxDecoration(
            color: hot
                ? JC.blue500.withValues(alpha: 0.1)
                : JC.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hot ? JC.blue500 : JC.border,
                width: hot ? 1.4 : 0.8),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Text(label,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                          color: JC.textPrimary,
                          fontFamily: 'Heebo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: JC.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${tasks.length}',
                        style: TextStyle(
                            color: JC.textMuted,
                            fontFamily: 'Heebo',
                            fontSize: 10.5)),
                  ),
                  const Spacer(),
                  if (_sp > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_outline_rounded,
                            size: 11, color: JC.amber400),
                        const SizedBox(width: 2),
                        Text('$_sp',
                            style: TextStyle(
                                color: JC.amber400,
                                fontFamily: 'Heebo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text('גרור משימה',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: JC.textMuted,
                          fontFamily: 'Heebo',
                          fontSize: 11)),
                )
              else
                for (final t in tasks)
                  _DraggableTaskTile(controller: controller, task: t),
            ],
          ),
        );
      },
    );
  }
}

class _DraggableTaskTile extends StatelessWidget {
  final TasksController controller;
  final Map<String, dynamic> task;
  const _DraggableTaskTile(
      {required this.controller, required this.task});

  @override
  Widget build(BuildContext context) {
    final card = SmartTaskCard(
      controller: controller,
      task: task,
      dense: true,
      draggableMode: true,
    );
    return LongPressDraggable<Map<String, dynamic>>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(width: 220, child: card),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}
