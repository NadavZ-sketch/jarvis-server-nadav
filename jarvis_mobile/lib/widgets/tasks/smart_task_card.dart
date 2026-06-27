import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';
import '../task_edit_sheet.dart';
import 'task_inline_expand.dart';

/// Phase 5 — Redesigned task card.
///
/// Layout:
///   [Priority circle]  [Title + chip row]  (no trailing indicator)
///
/// Gestures:
///   • Tap circle   → toggle done
///   • Tap body     → open/close inline expand panel
///   • Swipe left   → reveal postpone (blue) + delete (red) action buttons
///   • Long-press   → open full edit sheet (via controller)
class SmartTaskCard extends StatefulWidget {
  final TasksController controller;
  final Map<String, dynamic> task;
  final bool dense;
  final bool draggableMode;

  const SmartTaskCard({
    super.key,
    required this.controller,
    required this.task,
    this.dense = false,
    this.draggableMode = false,
  });

  @override
  State<SmartTaskCard> createState() => _SmartTaskCardState();
}

class _SmartTaskCardState extends State<SmartTaskCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Pre-fetch so suggestions are ready when the card is expanded
    if (!_isDone) widget.controller.fetchSuggestions(widget.task);
  }

  String get _title {
    final raw = widget.task['content']?.toString() ?? '';
    final withoutAI = raw.contains('\n<<<AI_PROMPT>>>\n')
        ? raw.split('\n<<<AI_PROMPT>>>\n').first
        : raw;
    return withoutAI.split('\n').first.trim();
  }

  bool get _isDone => widget.task['done'] == true;

  bool get _overdue {
    if (_isDone) return false;
    final iso = widget.task['due_date'];
    if (iso == null) return false;
    try {
      return DateTime.parse(iso.toString()).toLocal().isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Color get _priorityColor {
    if (_isDone) return JC.blue400.withValues(alpha: 0.6);
    return switch (widget.task['priority']?.toString()) {
      'high' => JC.cancelRed,
      'medium' => JC.amber400,
      'low' => JC.green500,
      _ => JC.border,
    };
  }

  String _formatDue(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day == today) return 'היום';
      if (day == today.add(const Duration(days: 1))) return 'מחר';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  void _openEdit(BuildContext ctx) {
    showTaskEditSheet(
      ctx,
      settings: widget.controller.settings,
      task: widget.task,
      onChanged: widget.controller.notify,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel = _formatDue(widget.task['due_date']);
    final inProject =
        (widget.task['project_id']?.toString().isNotEmpty ?? false);
    final rawTags = widget.task['tags'];
    final tags = rawTags is List
        ? List<String>.from(rawTags).take(3).toList()
        : <String>[];
    // Project name for chip
    String? projectName;
    if (inProject) {
      final pid = widget.task['project_id'].toString();
      final p = widget.controller.projects.firstWhere(
        (p) => p['id'].toString() == pid,
        orElse: () => {},
      );
      projectName = p['name']?.toString();
    }

    final hasChips = dueLabel.isNotEmpty || projectName != null || tags.isNotEmpty;

    final cardColor = _isDone ? JC.surface.withValues(alpha: 0.6) : JC.surfaceAlt;

    return Container(
      margin: EdgeInsets.only(bottom: widget.dense ? 4 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _overdue
              ? JC.cancelRed.withValues(alpha: 0.4)
              : JC.border,
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.4),
        child: _SwipeableCard(
        onPostpone: () => widget.controller.postpone(widget.task),
        onDelete: () {
          final task = widget.task;
          final idx = widget.controller.removeLocal(task);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('המשימה הוסרה',
                  style: const TextStyle(fontFamily: 'Heebo')),
              backgroundColor: JC.surfaceAlt,
              action: SnackBarAction(
                label: 'בטל',
                textColor: JC.blue400,
                onPressed: () => widget.controller.restoreTask(task, idx),
              ),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Future.delayed(const Duration(seconds: 3), () {
            if (widget.controller.tasks.contains(task)) return;
            widget.controller.commitDelete(task);
          });
        },
        child: ColoredBox(
          color: cardColor,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Card body ──────────────────────────────────────────────────
            GestureDetector(
              onTap: _isDone
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              onLongPress: widget.draggableMode
                  ? null
                  : () => _openEdit(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.dense ? 10 : 14,
                  vertical: widget.dense ? 8 : 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Completion circle
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.controller.toggleDone(widget.task);
                        if (_expanded) setState(() => _expanded = false);
                      },
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10, top: 1),
                        child: _PriorityCircle(
                          done: _isDone,
                          color: _priorityColor,
                        ),
                      ),
                    ),

                    // Title + chips
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: _isDone ? JC.textMuted : JC.textPrimary,
                              fontSize: 14.5,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w500,
                              decoration:
                                  _isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (hasChips)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if (dueLabel.isNotEmpty)
                                    _chip(dueLabel,
                                        color: _overdue
                                            ? JC.cancelRed
                                            : JC.green500,
                                        icon: Icons.event_outlined),
                                  if (projectName != null)
                                    _chip(projectName!,
                                        color: JC.indigo300,
                                        icon: Icons.folder_outlined),
                                  for (final tag in tags)
                                    _chip('#$tag', color: JC.blue400),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Expand indicator
                    if (!_isDone)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6, top: 2),
                        child: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: Icon(Icons.keyboard_arrow_down_rounded,
                              size: 18, color: JC.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Inline expand panel ────────────────────────────────────────
            if (_expanded)
              TaskInlineExpand(
                controller: widget.controller,
                task: widget.task,
              ),
          ],
        ),
        ),
        ),
      ),
    );
  }

}

// ─── Priority circle ──────────────────────────────────────────────────────────

class _PriorityCircle extends StatelessWidget {
  final bool done;
  final Color color;

  const _PriorityCircle({required this.done, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border: done ? null : Border.all(color: color, width: 1.8),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

// ─── Chip helper ──────────────────────────────────────────────────────────────

Widget _chip(String text, {required Color color, IconData? icon}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
        ],
        Text(text,
            style: TextStyle(
                color: color,
                fontFamily: 'Heebo',
                fontSize: 10.5,
                fontWeight: FontWeight.w500)),
      ],
    ),
  );
}

// ─── Swipeable card wrapper ───────────────────────────────────────────────────

class _SwipeableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onPostpone;
  final VoidCallback onDelete;

  const _SwipeableCard({
    required this.child,
    required this.onPostpone,
    required this.onDelete,
  });

  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard>
    with SingleTickerProviderStateMixin {
  double _offsetX = 0;
  static const _maxReveal = 138.0;
  static const _triggerThreshold = 50.0;

  late final AnimationController _animCtrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _snapTo(double target) {
    _anim = Tween<double>(begin: _offsetX, end: target).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl
      ..reset()
      ..forward();
    _anim.addListener(() {
      if (mounted) setState(() => _offsetX = _anim.value);
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final next = (_offsetX + d.delta.dx).clamp(-_maxReveal, 0.0);
    setState(() => _offsetX = next);
  }

  void _onDragEnd(DragEndDetails _) {
    if (_offsetX < -_triggerThreshold) {
      _snapTo(-_maxReveal);
    } else {
      _snapTo(0);
    }
  }

  void _close() => _snapTo(0);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Action buttons revealed on right when card slides left (RTL swipe)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: _maxReveal,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Row(
              children: [
                // Postpone
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _close();
                      widget.onPostpone();
                    },
                    child: Container(
                      color: JC.blue500,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(height: 3),
                          const Text('דחייה',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Heebo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
                // Delete
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _close();
                      widget.onDelete();
                    },
                    child: Container(
                      color: JC.cancelRed,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(height: 3),
                          const Text('מחיקה',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Heebo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Card on top (translates left on swipe)
        GestureDetector(
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onTap: _offsetX < 0 ? _close : null,
          child: Transform.translate(
            offset: Offset(_offsetX, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
