import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_helpers.dart';

class RemindersCard extends StatelessWidget {
  final HomeController c;
  const RemindersCard(this.c, {super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final sorted = c.reminders.where((r) {
      final iso = r['scheduled_time'] as String?;
      if (iso == null || iso.isEmpty) return false;
      try {
        final dt = DateTime.parse(iso).toLocal();
        return !dt.isBefore(now.subtract(const Duration(minutes: 1)));
      } catch (_) {
        return false;
      }
    }).toList()
      ..sort((a, b) => (a['scheduled_time'] as String? ?? '')
          .compareTo(b['scheduled_time'] as String? ?? ''));

    final urgent = sorted.where((r) {
      try {
        final diff = DateTime.parse(r['scheduled_time'] as String)
            .toLocal()
            .difference(now);
        return diff.inMinutes >= 0 && diff.inMinutes <= 120;
      } catch (_) {
        return false;
      }
    }).toList();

    final todayLater = sorted.where((r) {
      try {
        final dt = DateTime.parse(r['scheduled_time'] as String).toLocal();
        final diff = dt.difference(now);
        return diff.inMinutes > 120 &&
            dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year;
      } catch (_) {
        return false;
      }
    }).toList();

    final upcoming = sorted.where((r) {
      try {
        final dt = DateTime.parse(r['scheduled_time'] as String).toLocal();
        return !(dt.day == now.day &&
            dt.month == now.month &&
            dt.year == now.year);
      } catch (_) {
        return false;
      }
    }).toList();

    return SectionCard(
      title: 'תזכורות (${sorted.length})',
      icon: Icons.notifications_active_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: sorted.isEmpty
          ? const EmptyState(message: 'אין תזכורות קרובות')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (urgent.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.3),
                        width: 0.8),
                  ),
                  child: Row(children: [
                    const Text('🔔', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        urgent.length == 1
                            ? 'תזכורת דחופה בתוך שעתיים'
                            : '${urgent.length} תזכורות דחופות בתוך שעתיים',
                        style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 12,
                            fontFamily: 'Heebo',
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                _header('בקרוב', const Color(0xFFEF4444)),
                const SizedBox(height: 6),
                ...urgent.map((r) => _row(r, const Color(0xFFEF4444))),
                if (todayLater.isNotEmpty || upcoming.isNotEmpty)
                  const SizedBox(height: 10),
              ],
              if (todayLater.isNotEmpty) ...[
                _header('היום', const Color(0xFFF59E0B)),
                const SizedBox(height: 6),
                ...todayLater.map((r) => _row(r, const Color(0xFFF59E0B))),
                if (upcoming.isNotEmpty) const SizedBox(height: 10),
              ],
              if (upcoming.isNotEmpty) ...[
                _header('הבא', const Color(0xFF3B82F6)),
                const SizedBox(height: 6),
                ...upcoming.take(3).map((r) => _row(r, const Color(0xFF3B82F6))),
                if (upcoming.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+${upcoming.length - 3} נוספות',
                        style: TextStyle(
                            color: JC.textMuted,
                            fontSize: 11,
                            fontFamily: 'Heebo')),
                  ),
              ],
            ]),
    );
  }

  Widget _header(String label, Color color) {
    return Row(children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontFamily: 'Heebo',
              fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _row(Map<String, dynamic> reminder, Color accent) {
    final text = reminder['text'] as String? ?? '—';
    final iso = reminder['scheduled_time'] as String?;
    final timeStr = timeOfDay(iso);
    final remaining = formatRemTime(iso);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border(right: BorderSide(color: accent, width: 2)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(timeStr.isEmpty ? '—' : timeStr,
                style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w600)),
            if (remaining.isNotEmpty)
              Text(remaining,
                  style: TextStyle(
                      color: accent, fontSize: 11, fontFamily: 'Heebo')),
          ]),
        ),
      ]),
    );
  }
}
