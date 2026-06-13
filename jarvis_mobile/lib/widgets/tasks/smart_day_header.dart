import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';
import 'load_gauge.dart';

/// Compact, collapsible header that surfaces the Smart Day Engine intelligence
/// (load %, narrative, conflicts, peak window) above the single task list.
///
/// Collapsed: one row — load% pill + truncated narrative + conflicts badge.
/// Expanded: full narrative + [LoadGauge] with peak window.
/// Renders nothing when there is no day-plan data and none is loading.
class SmartDayHeader extends StatefulWidget {
  final TasksController controller;
  const SmartDayHeader({super.key, required this.controller});

  @override
  State<SmartDayHeader> createState() => _SmartDayHeaderState();
}

class _SmartDayHeaderState extends State<SmartDayHeader> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final hasData = c.dayPlan != null;
    if (!hasData && !c.dayPlanLoading) return const SizedBox.shrink();

    final load = c.loadGauge;
    final narrative = c.narrative;
    final conflicts = c.conflicts.length;
    final color = _loadColor(load);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: JC.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JC.border, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  _LoadPill(value: load, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: c.dayPlanLoading && !hasData
                        ? Text('מנתח את היום…',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: JC.textMuted,
                                fontFamily: 'Heebo',
                                fontSize: 12.5))
                        : Text(
                            narrative.isEmpty
                                ? 'תכנון היום מוכן'
                                : narrative,
                            maxLines: _expanded ? 6 : 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                                color: JC.textSecondary,
                                fontFamily: 'Heebo',
                                fontSize: 12.5,
                                height: 1.35)),
                  ),
                  if (conflicts > 0) ...[
                    const SizedBox(width: 8),
                    _ConflictBadge(count: conflicts),
                  ],
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: JC.textMuted),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState: _expanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LoadGauge(value: load, peakWindow: c.peakWindow),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _loadColor(double v) {
    if (v < 40) return JC.green500;
    if (v < 75) return JC.amber400;
    return JC.cancelRed;
  }
}

class _LoadPill extends StatelessWidget {
  final double value;
  final Color color;
  const _LoadPill({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text('${value.round()}%',
              style: TextStyle(
                  color: color,
                  fontFamily: 'Heebo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ConflictBadge extends StatelessWidget {
  final int count;
  const _ConflictBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: JC.cancelRed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: JC.cancelRed),
          const SizedBox(width: 3),
          Text('$count',
              style: TextStyle(
                  color: JC.cancelRed,
                  fontFamily: 'Heebo',
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
