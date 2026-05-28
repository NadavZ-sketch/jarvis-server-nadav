import 'package:flutter/material.dart';
import '../../../main.dart' show JC;
import '../../../widgets/tasks/smart_task_card.dart';
import '../tasks_controller.dart';

const _kQuads = [
  ('q1', 'דחוף וחשוב', 'עשה עכשיו'),
  ('q2', 'חשוב', 'תכנן'),
  ('q3', 'דחוף', 'האצל'),
  ('q4', 'שולי', 'בטל'),
];

class EisenhowerView extends StatelessWidget {
  final TasksController controller;
  const EisenhowerView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final buckets = controller.quadrants;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
          children: [
            for (final q in _kQuads)
              _QuadrantCell(
                controller: controller,
                quad: q.$1,
                title: q.$2,
                hint: q.$3,
                tasks: buckets[q.$1] ?? const [],
              ),
          ],
        ),
        if ((buckets['none'] ?? const []).isNotEmpty) ...[
          const SizedBox(height: 14),
          _UnclassifiedSection(
            controller: controller,
            tasks: buckets['none']!,
          ),
        ],
      ],
    );
  }
}

class _QuadrantCell extends StatelessWidget {
  final TasksController controller;
  final String quad;
  final String title;
  final String hint;
  final List<Map<String, dynamic>> tasks;
  const _QuadrantCell({
    required this.controller,
    required this.quad,
    required this.title,
    required this.hint,
    required this.tasks,
  });

  Color get _accent => switch (quad) {
        'q1' => JC.cancelRed,
        'q2' => JC.blue500,
        'q3' => JC.amber400,
        _ => JC.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) => d.data['eisenhower_quad'] != quad,
      onAcceptWithDetails: (d) => controller.setQuadrant(d.data, quad),
      builder: (ctx, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: hot
                ? _accent.withValues(alpha: 0.15)
                : JC.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: hot ? _accent : _accent.withValues(alpha: 0.4),
                width: hot ? 1.4 : 0.8),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: _accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(title,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: _accent,
                                fontFamily: 'Heebo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        Text(hint,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: JC.textMuted,
                                fontFamily: 'Heebo',
                                fontSize: 10)),
                      ],
                    ),
                  ),
                  Text('${tasks.length}',
                      style: TextStyle(
                          color: JC.textMuted,
                          fontFamily: 'Heebo',
                          fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text('גרור משימה',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: JC.textMuted,
                                fontFamily: 'Heebo',
                                fontSize: 11)),
                      )
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (final t in tasks)
                            _DraggableTaskTile(
                                controller: controller, task: t),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnclassifiedSection extends StatelessWidget {
  final TasksController controller;
  final List<Map<String, dynamic>> tasks;
  const _UnclassifiedSection(
      {required this.controller, required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JC.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('לא מסווג (${tasks.length}) — גרור לרביע מתאים',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                  color: JC.textSecondary,
                  fontFamily: 'Heebo',
                  fontSize: 12)),
          const SizedBox(height: 8),
          for (final t in tasks)
            _DraggableTaskTile(controller: controller, task: t),
        ],
      ),
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
