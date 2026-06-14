import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../theme/jarvis_dimens.dart';
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

/// "מסלול היום" — two-layer card:
///   1. AI rank row (top): shown only when [HomeController.aiRank] is non-null.
///   2. Day timeline (bottom): local RTL timeline of today's tasks + reminders.
class DayFocusCard extends StatefulWidget {
  final HomeController c;
  const DayFocusCard(this.c, {super.key});

  @override
  State<DayFocusCard> createState() => _DayFocusCardState();
}

class _DayFocusCardState extends State<DayFocusCard>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _dotCtrl;
  late final Animation<double> _entryOpacity;
  late final Animation<double> _dotScale;

  @override
  void initState() {
    super.initState();
    // Entry pulse: fade in once on mount
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _entryOpacity = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _entryCtrl.forward();

    // Current-dot pulse: slow repeat scale
    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _dotScale = Tween<double>(begin: 1.0, end: 1.15)
        .animate(CurvedAnimation(parent: _dotCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return FadeTransition(
      opacity: _entryOpacity,
      child: SectionCard(
        title: 'מסלול היום',
        icon: Icons.timeline_rounded,
        iconColor: JC.indigo500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.aiRank != null && c.aiRank!.isNotEmpty) ...[
              _AiRankRow(text: c.aiRank!),
              JD.gapMd,
            ],
            _DayTimeline(
              tasks: c.tasks,
              reminders: c.reminders,
              dotScale: _dotScale,
              onItemTap: (name) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(name,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary)),
                  backgroundColor: JC.surfaceAlt,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AI rank row ──────────────────────────────────────────────────────────────

class _AiRankRow extends StatelessWidget {
  final String text;
  const _AiRankRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1.0,
      duration: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: JC.indigo500.withOpacity(0.08),
          borderRadius: BorderRadius.circular(JD.rSm),
          border: Border.all(
              color: JC.indigo500.withOpacity(0.2), width: 0.7),
        ),
        child: Row(
          children: [
            Icon(Icons.bolt_rounded, size: 14, color: JC.indigo500),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: JC.textSecondary,
                  fontSize: JD.label,
                  fontFamily: 'Heebo',
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Day timeline ─────────────────────────────────────────────────────────────

class _TimelineItem {
  final String name;
  final bool isReminder;
  final DateTime time;
  _TimelineItem({required this.name, required this.isReminder, required this.time});
}

class _DayTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> reminders;
  final Animation<double> dotScale;
  final void Function(String name) onItemTap;

  const _DayTimeline({
    required this.tasks,
    required this.reminders,
    required this.dotScale,
    required this.onItemTap,
  });

  static const int _startHour = 6;
  static const int _endHour = 23;
  static const double _totalHours = _endHour - _startHour;

  List<_TimelineItem> _items() {
    final result = <_TimelineItem>[];
    for (final t in tasks) {
      if (t['done'] == true) continue;
      final iso = t['due_date'] as String?;
      if (iso == null) continue;
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) continue;
      result.add(_TimelineItem(
        name: (t['content'] ?? t['title'] ?? '').toString(),
        isReminder: false,
        time: dt,
      ));
    }
    for (final r in reminders) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null) continue;
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) continue;
      result.add(_TimelineItem(
        name: (r['text'] ?? '').toString(),
        isReminder: true,
        time: dt,
      ));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  double _fraction(DateTime dt) {
    final h = dt.hour + dt.minute / 60.0;
    return ((h - _startHour) / _totalHours).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final now = DateTime.now();
    final nowFraction = _fraction(now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const dotRadius = 5.0;
        const nowRadius = 6.0;
        const lineY = 20.0;
        const totalHeight = 44.0;

        return SizedBox(
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Base line
              Positioned(
                left: 0, right: 0, top: lineY - 0.75,
                child: Container(height: 1.5, color: JC.border),
              ),
              // Zone labels
              Positioned(
                left: 0, top: lineY + 6,
                child: Text('06:00',
                    style: TextStyle(color: JC.textMuted, fontSize: 9, fontFamily: 'Heebo')),
              ),
              Positioned(
                left: width * 0.45, top: lineY + 6,
                child: Text('14:00',
                    style: TextStyle(color: JC.textMuted, fontSize: 9, fontFamily: 'Heebo')),
              ),
              Positioned(
                right: 0, top: lineY + 6,
                child: Text('23:00',
                    style: TextStyle(color: JC.textMuted, fontSize: 9, fontFamily: 'Heebo')),
              ),
              // Item dots
              ...items.map((item) {
                final x = item.isReminder
                    ? _fraction(item.time) * width
                    : _fraction(item.time) * width;
                final isPast = item.time.isBefore(now);
                final color = item.isReminder
                    ? (isPast ? JC.textMuted : const Color(0xFFF59E0B))
                    : (isPast ? JC.textMuted : JC.blue400);
                return Positioned(
                  left: x - dotRadius,
                  top: lineY - dotRadius,
                  child: GestureDetector(
                    onTap: () => onItemTap(item.name),
                    child: item.isReminder
                        ? Icon(Icons.notifications_rounded,
                            size: dotRadius * 2.2, color: color)
                        : Container(
                            width: dotRadius * 2,
                            height: dotRadius * 2,
                            decoration:
                                BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                  ),
                );
              }),
              // Now indicator (pulsing)
              Positioned(
                left: nowFraction * width - nowRadius,
                top: lineY - nowRadius,
                child: ScaleTransition(
                  scale: dotScale,
                  child: Container(
                    width: nowRadius * 2,
                    height: nowRadius * 2,
                    decoration: BoxDecoration(
                      color: JC.blue500,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: JC.blue500.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
