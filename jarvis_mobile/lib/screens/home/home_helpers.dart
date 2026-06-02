import 'package:flutter/material.dart';
import '../../main.dart' show JC;

// ─────────────────────────────────────────────────────────────────────────────
// Pure helpers — shared across all home cards.
// ─────────────────────────────────────────────────────────────────────────────

Color priorityColor(String? priority) {
  switch ((priority ?? '').toLowerCase()) {
    case 'high':
      return const Color(0xFFEF4444);
    case 'medium':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF475569);
  }
}

String priorityLabel(String? priority) {
  switch ((priority ?? '').toLowerCase()) {
    case 'high':
      return 'גבוה';
    case 'medium':
      return 'בינוני';
    default:
      return 'רגיל';
  }
}

String formatRemTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'פג תוקף';
    if (diff.inHours < 1) return 'בעוד ${diff.inMinutes} דק׳';
    if (diff.inHours < 24) return 'בעוד ${diff.inHours} שעות';
    return 'בעוד ${diff.inDays} ימים';
  } catch (_) {
    return '';
  }
}

String timeOfDay(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '';
  }
}

String dynamicGreeting(String userName) {
  final hour = DateTime.now().hour;
  final name = userName.isEmpty ? 'Jarvis' : userName;
  if (hour < 5) return 'לילה טוב, $name';
  if (hour < 12) return 'בוקר טוב, $name';
  if (hour < 17) return 'צהריים טובים, $name';
  if (hour < 21) return 'ערב טוב, $name';
  return 'לילה טוב, $name';
}

String greetingEmoji() {
  final hour = DateTime.now().hour;
  if (hour < 5) return '✨';
  if (hour < 12) return '☀️';
  if (hour < 17) return '🌤';
  if (hour < 21) return '🌙';
  return '✨';
}

/// Subtasks embedded on a task map by the server (`/tasks` select join).
List<Map<String, dynamic>> subtasksOf(Map<String, dynamic> task) {
  final raw = task['subtasks'];
  if (raw is List) return List<Map<String, dynamic>>.from(raw);
  return const [];
}

int openSubtaskCount(Map<String, dynamic> task) =>
    subtasksOf(task).where((s) => s['done'] != true).length;

/// Completion guard: if a task has open subtasks, asks the user to confirm
/// before completing. Returns true when it's OK to mark the task done.
Future<bool> guardComplete(BuildContext context, Map<String, dynamic> task) async {
  final open = openSubtaskCount(task);
  if (open == 0) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: JC.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('יש תתי-משימות פתוחות',
            style: TextStyle(
                color: JC.textPrimary,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
        content: Text(
          'נותרו $open תתי-משימות שלא הושלמו. להשלים את המשימה בכל זאת?',
          style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('ביטול',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('השלם בכל זאת',
                style:
                    TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
  return ok ?? false;
}

const hebrewDays = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];
const hebrewMonths = [
  'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
  'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר',
];

String todayDateLine() {
  final now = DateTime.now();
  return 'יום ${hebrewDays[now.weekday % 7]}, ${now.day} ב${hebrewMonths[now.month - 1]}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared presentational widgets.
// ─────────────────────────────────────────────────────────────────────────────

/// A themed section card with an icon header, divider and body.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? headerTrailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Heebo',
                      )),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
          ),
          Divider(color: JC.border, height: 1),
          Padding(padding: const EdgeInsets.all(14), child: child),
        ],
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  final String? priority;
  const PriorityBadge(this.priority, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(priorityLabel(priority),
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w600)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  const EmptyState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: JC.textMuted, fontSize: 13, fontFamily: 'Heebo')),
      ),
    );
  }
}

class CardSkeleton extends StatelessWidget {
  final int lines;
  const CardSkeleton({super.key, this.lines = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        lines,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          height: 14,
          width: i == lines - 1 ? 120 : double.infinity,
          decoration: BoxDecoration(
            color: JC.track,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const InlineError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF4444), size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 12,
                    fontFamily: 'Heebo')),
          ),
        ]),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onRetry,
          child: Text('נסה שוב',
              style: TextStyle(color: JC.blue400, fontFamily: 'Heebo')),
        ),
      ],
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: JC.textMuted, size: 48),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: JC.textSecondary, fontSize: 14, fontFamily: 'Heebo')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                  backgroundColor: JC.blue500,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('נסה שוב', style: TextStyle(fontFamily: 'Heebo')),
            ),
          ],
        ),
      ),
    );
  }
}

class SnackOverlay extends StatelessWidget {
  final String message;
  const SnackOverlay(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: JC.track,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF22C55E), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: JC.textPrimary, fontSize: 13, fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
  }
}

class QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const QuickActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.35), width: 0.8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

/// A labeled progress bar (used by the stats strip).
class ProgressMeter extends StatelessWidget {
  final String label;
  final double fraction; // 0..1
  final Color color;
  final String trailing;

  const ProgressMeter({
    super.key,
    required this.label,
    required this.fraction,
    required this.color,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: JC.textSecondary,
                      fontSize: 12,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w600)),
            ),
            Text(trailing,
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(children: [
              Container(height: 6, color: JC.track),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(height: 6, color: color),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
