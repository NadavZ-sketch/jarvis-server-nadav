import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../theme/jarvis_dimens.dart';
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// "פוקוס עכשיו" — the single most pressing thing right now, picked locally from
/// the task/reminder state (no server, no LLM). An imminent reminder outranks
/// tasks; otherwise the top open task. Below it, a slim progress + load line.
/// Replaces the old LLM-backed daily tip to keep the home screen token-free.
class JarvisCard extends StatelessWidget {
  final HomeController c;
  const JarvisCard(this.c, {super.key});

  static const _accent = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final focus = c.focusItem;

    return SectionCard(
      title: 'פוקוס עכשיו',
      icon: Icons.center_focus_strong_rounded,
      iconColor: _accent,
      headerTrailing: _loadChip(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (focus == null)
            const EmptyState(message: 'אין משימות דחופות — הכל תחת שליטה ✨')
          else if (focus.kind == 'reminder')
            _reminderFocus(context, focus.data)
          else
            _taskFocus(context, focus.data),
          JD.gapMd,
          _progress(),
        ],
      ),
    );
  }

  // ── Header trailing: a small day-load chip ──────────────────────────────────
  Widget _loadChip() {
    final (label, color) = _loadLabel(c.dayLoadStatus());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(JD.rSm),
        border: Border.all(color: color.withOpacity(0.35), width: 0.8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: JD.label,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600)),
    );
  }

  (String, Color) _loadLabel(String status) {
    switch (status) {
      case 'empty':
        return ('יום פנוי', const Color(0xFF22C55E));
      case 'light':
        return ('עומס קל', const Color(0xFF22C55E));
      case 'moderate':
        return ('עומס בינוני', const Color(0xFFF59E0B));
      case 'heavy':
        return ('עומס גבוה', const Color(0xFFF97316));
      default:
        return ('עומס מאוד גבוה', const Color(0xFFEF4444));
    }
  }

  // ── Task focus: title + priority + "סיים" action ───────────────────────────
  Widget _taskFocus(BuildContext context, Map<String, dynamic> task) {
    final content = task['content'] as String? ?? '—';
    final priority = task['priority'] as String?;
    final isHigh = (priority ?? '').toLowerCase() == 'high';
    final accent = isHigh ? const Color(0xFFEF4444) : _accent;

    return _focusShell(
      accent: accent,
      onTap: () => c.onNavigateToChat?.call(command: 'עזור לי עם: $content'),
      icon: Icons.task_alt_rounded,
      iconColor: accent,
      title: content,
      sub: Row(children: [
        PriorityBadge(priority),
        const SizedBox(width: JD.sm),
        Text('הדבר הכי חשוב כרגע',
            style: TextStyle(
                color: JC.textMuted, fontSize: JD.label, fontFamily: 'Heebo')),
      ]),
      action: _actionButton(
        label: 'סיים',
        icon: Icons.check_rounded,
        color: const Color(0xFF22C55E),
        onTap: () async {
          if (await guardComplete(context, task)) c.completeTask(task);
        },
      ),
    );
  }

  // ── Reminder focus: text + time/countdown ──────────────────────────────────
  Widget _reminderFocus(BuildContext context, Map<String, dynamic> rem) {
    final text = rem['text'] as String? ?? '—';
    final iso = rem['scheduled_time'] as String?;
    final time = timeOfDay(iso);
    final remaining = formatRemTime(iso);
    const accent = Color(0xFFF59E0B);

    return _focusShell(
      accent: accent,
      onTap: () => c.onNavigateToChat?.call(command: text),
      icon: Icons.notifications_active_rounded,
      iconColor: accent,
      title: text,
      sub: Text(
        [if (time.isNotEmpty) time, if (remaining.isNotEmpty) remaining]
            .join(' · '),
        style: const TextStyle(
            color: accent, fontSize: JD.label, fontFamily: 'Heebo'),
      ),
      action: null,
    );
  }

  // Shared visual shell for a focus item.
  Widget _focusShell({
    required Color accent,
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget sub,
    required Widget? action,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JD.rMd),
        child: Ink(
          padding: const EdgeInsets.all(JD.md),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1929),
            borderRadius: BorderRadius.circular(JD.rMd),
            border:
                BorderDirectional(start: BorderSide(color: accent, width: 3)),
          ),
          child: Row(children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: JD.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: JD.body + 1,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                      )),
                  const SizedBox(height: 3),
                  sub,
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: JD.sm), action],
          ]),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Future<void> Function() onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(JD.rSm),
          border: Border.all(color: color.withOpacity(0.4), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: JD.label,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  // ── Slim progress line ──────────────────────────────────────────────────────
  Widget _progress() {
    final done = c.doneTasks;
    final total = c.totalTasks;
    final fraction = total == 0 ? 0.0 : done / total;
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 5, color: const Color(0xFF1A2E4A)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(height: 5, color: const Color(0xFF22C55E)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: JD.sm),
      Text('$done/$total הושלמו',
          style: TextStyle(
              color: JC.textMuted, fontSize: JD.label, fontFamily: 'Heebo')),
    ]);
  }
}
