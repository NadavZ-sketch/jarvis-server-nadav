import 'package:flutter/material.dart';
import '../../../main.dart' show JC;
import '../../../widgets/empty_state.dart';
import '../../../widgets/loading_skeleton.dart';
import '../../../widgets/tasks/load_gauge.dart';
import '../../../widgets/tasks/smart_task_card.dart';
import '../../../widgets/task_edit_sheet.dart';
import '../tasks_controller.dart';

const _kBuckets = [
  ('now', 'עכשיו', Icons.flash_on_rounded),
  ('plan', 'לתכנן', Icons.event_note_rounded),
  ('quick', 'מהיר', Icons.bolt_outlined),
  ('later', 'אחר כך', Icons.schedule_rounded),
];

class DayPlanView extends StatelessWidget {
  final TasksController controller;
  const DayPlanView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (controller.dayPlanLoading && controller.dayPlan == null) {
      return const LoadingSkeleton(itemCount: 4);
    }

    final buckets = controller.dayPlanBuckets;
    final hasAny = buckets.values.any((l) => l.isNotEmpty);

    if (!hasAny && controller.tasks.where((t) => t['done'] != true).isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'אין משימות פתוחות',
        subtitle: 'הוסף משימות וקבל תכנון יום חכם',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (controller.narrative.isNotEmpty)
          _NarrativeCard(text: controller.narrative),
        const SizedBox(height: 10),
        LoadGauge(
          value: controller.loadGauge,
          peakWindow: controller.peakWindow,
        ),
        if (controller.conflicts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ConflictsCard(controller: controller),
        ],
        const SizedBox(height: 14),
        for (final b in _kBuckets) ...[
          _BucketHeader(
            icon: b.$3,
            label: b.$2,
            count: buckets[b.$1]?.length ?? 0,
          ),
          const SizedBox(height: 6),
          if ((buckets[b.$1] ?? const []).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: JC.textMuted,
                      fontFamily: 'Heebo',
                      fontSize: 12)),
            )
          else
            for (final t in buckets[b.$1] ?? const <Map<String, dynamic>>[])
              SmartTaskCard(controller: controller, task: t),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _NarrativeCard extends StatelessWidget {
  final String text;
  const _NarrativeCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            JC.indigo500.withValues(alpha: 0.15),
            JC.blue500.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: JC.indigo500.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: JC.indigo300, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _ConflictsCard extends StatelessWidget {
  final TasksController controller;
  const _ConflictsCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: JC.cancelRed.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: JC.cancelRed, size: 16),
              const SizedBox(width: 6),
              Text('התנגשויות',
                  style: TextStyle(
                      color: JC.cancelRed,
                      fontFamily: 'Heebo',
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            textDirection: TextDirection.rtl,
            children: [
              for (final c in controller.conflicts)
                _ConflictChip(
                  conflict: c,
                  onTap: () => _openConflict(context, c),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _openConflict(BuildContext context, Map<String, dynamic> c) {
    final ids = <String>[];
    for (final key in ['task_id', 'a', 'b', 'first', 'second']) {
      final v = c[key];
      if (v is String) ids.add(v);
      if (v is num) ids.add(v.toString());
      if (v is Map && v['id'] != null) ids.add(v['id'].toString());
    }
    for (final id in ids) {
      final task = controller.taskById(id);
      if (task != null) {
        showTaskEditSheet(
          context,
          settings: controller.settings,
          task: task,
          onChanged: controller.notify,
        );
        return;
      }
    }
  }
}

class _ConflictChip extends StatelessWidget {
  final Map<String, dynamic> conflict;
  final VoidCallback onTap;
  const _ConflictChip({required this.conflict, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = (conflict['label'] ??
            conflict['reason'] ??
            conflict['message'] ??
            'התנגשות')
        .toString();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: JC.cancelRed.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
                color: JC.textPrimary,
                fontFamily: 'Heebo',
                fontSize: 11.5)),
      ),
    );
  }
}

class _BucketHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _BucketHeader(
      {required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(icon, size: 16, color: JC.blue400),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: JC.textPrimary,
                fontFamily: 'Heebo',
                fontSize: 14,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              color: JC.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JC.border, width: 0.6)),
          child: Text('$count',
              style: TextStyle(
                  color: JC.textMuted,
                  fontFamily: 'Heebo',
                  fontSize: 11)),
        ),
      ],
    );
  }
}
