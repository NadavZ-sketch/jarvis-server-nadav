import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/home/home_controller.dart';
import '../../screens/home/home_dialogs.dart';
import '../../screens/home/home_helpers.dart';

/// Reminders with an inline 7-day strip on top and an AI suggestions bar.
class RemindersCard extends StatefulWidget {
  final HomeController c;
  const RemindersCard(this.c, {super.key});

  @override
  State<RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<RemindersCard> {
  bool _suggestionsOpen = false;

  HomeController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime.now();

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

    return Container(
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text('תזכורות (${sorted.length})',
                  style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo',
                  )),
            ]),
          ),
          // ── AI suggestions bar ──
          if (c.activeSuggestions.isNotEmpty || c.suggestionsLoading)
            _buildAiBar(context),
          Divider(color: JC.border, height: 1),
          // ── 7-day strip ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                itemBuilder: (_, i) {
                  final offset = i - 3;
                  final day = today.add(Duration(days: offset));
                  final isToday = offset == 0;
                  final isSelected = offset == c.selectedDayOffset;
                  final remCount = c.reminderCountForDay(day);

                  return Semantics(
                    button: true,
                    label: '${hebrewDays[day.weekday % 7]} ${day.day}, $remCount תזכורות',
                    selected: isSelected,
                    child: GestureDetector(
                      onTap: () => c.selectDay(offset),
                      child: Container(
                        width: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? JC.blue500
                              : isToday
                                  ? JC.blue500.withValues(alpha: 0.15)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(
                                  color: JC.blue500.withValues(alpha: 0.5), width: 1)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(hebrewDays[day.weekday % 7],
                                style: TextStyle(
                                  color: isSelected ? JC.onAccent : JC.textMuted,
                                  fontSize: 10,
                                  fontFamily: 'Heebo',
                                )),
                            const SizedBox(height: 3),
                            Text('${day.day}',
                                style: TextStyle(
                                  color: isSelected ? JC.onAccent : JC.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Heebo',
                                )),
                            const SizedBox(height: 3),
                            if (remCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? JC.onAccent.withValues(alpha: 0.3)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text('$remCount',
                                    style: TextStyle(
                                      color: isSelected
                                          ? JC.onAccent
                                          : const Color(0xFFF59E0B),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'Heebo',
                                    )),
                              )
                            else
                              const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Divider(color: JC.border, height: 1),
          // ── Body: today → urgency grouping, other day → that day's list ──
          Padding(
            padding: const EdgeInsets.all(14),
            child: c.selectedDayOffset == 0
                ? _todayView(now, sorted)
                : _dayView(c.selectedDayOffset),
          ),
        ],
      ),
    );
  }

  // ── AI bar ──────────────────────────────────────────────────────────────────

  Widget _buildAiBar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _suggestionsOpen = !_suggestionsOpen),
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.25), width: 0.8),
            ),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFFA78BFA),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.suggestionsLoading
                      ? '✦ טוען תובנות...'
                      : '✦ ${c.activeSuggestions.length} תובנות AI',
                  style: const TextStyle(
                    color: Color(0xFFA78BFA),
                    fontSize: 12,
                    fontFamily: 'Heebo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!c.suggestionsLoading && c.activeSuggestions.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('חדש',
                      style: TextStyle(
                          color: Color(0xFFA78BFA),
                          fontSize: 10,
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                _suggestionsOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFF64748B),
                size: 18,
              ),
            ]),
          ),
        ),
        if (_suggestionsOpen && c.activeSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(
              children: c.activeSuggestions
                  .map((s) => _suggestionRow(context, s))
                  .toList(),
            ),
          ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _suggestionRow(BuildContext context, Map<String, dynamic> s) {
    final id = s['id']?.toString() ?? '';
    final text = s['text']?.toString() ?? '';
    final sourceType = s['sourceType']?.toString() ?? 'chat';
    final sourceLabel = s['sourceLabel']?.toString() ?? '';

    final (srcEmoji, srcColor) = switch (sourceType) {
      'task' => ('📋', const Color(0xFFEF4444)),
      'plan' => ('🗓', const Color(0xFF22C55E)),
      _ => ('💬', const Color(0xFFA78BFA)),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2137),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(
            start: BorderSide(color: srcColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: srcColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$srcEmoji ${sourceType == 'task' ? 'משימה' : sourceType == 'plan' ? 'תכנון' : 'שיחה'}',
                  style: TextStyle(
                      color: srcColor,
                      fontSize: 10,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700)),
            ),
            if (sourceLabel.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(sourceLabel,
                  style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10,
                      fontFamily: 'Heebo')),
            ],
          ]),
          const SizedBox(height: 6),
          Text(text,
              style: TextStyle(
                  color: JC.textPrimary,
                  fontSize: 13,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            _actionBtn('📋 משימה', const Color(0xFF3B82F6),
                () => c.addTask(text)),
            const SizedBox(width: 6),
            _actionBtn('⏰ תזכורת', const Color(0xFFF59E0B),
                () => showAddReminderDialog(context, c, initialText: text)),
            const SizedBox(width: 6),
            _actionBtn('💬 שיחה', const Color(0xFFA78BFA),
                () => c.onNavigateToChat?.call(command: text)),
            const Spacer(),
            GestureDetector(
              onTap: () => c.dismissSuggestion(id),
              child: const Icon(Icons.close_rounded,
                  color: Color(0xFF64748B), size: 16),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── Reminders body (unchanged from original) ─────────────────────────────────

  Widget _todayView(DateTime now, List<Map<String, dynamic>> sorted) {
    if (sorted.isEmpty) {
      return const EmptyState(message: 'אין תזכורות קרובות');
    }

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

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (urgent.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 0.8),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_rounded,
                color: Color(0xFFEF4444), size: 14),
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
        _groupHeader('בקרוב', const Color(0xFFEF4444)),
        const SizedBox(height: 6),
        ...urgent.map((r) => _row(r, const Color(0xFFEF4444))),
        if (todayLater.isNotEmpty || upcoming.isNotEmpty)
          const SizedBox(height: 10),
      ],
      if (todayLater.isNotEmpty) ...[
        _groupHeader('היום', const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        ...todayLater.map((r) => _row(r, const Color(0xFFF59E0B))),
        if (upcoming.isNotEmpty) const SizedBox(height: 10),
      ],
      if (upcoming.isNotEmpty) ...[
        _groupHeader('הבא', const Color(0xFF3B82F6)),
        const SizedBox(height: 6),
        ...upcoming.take(3).map((r) => _row(r, const Color(0xFF3B82F6))),
        if (upcoming.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+${upcoming.length - 3} נוספות',
                style: TextStyle(
                    color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
          ),
      ],
    ]);
  }

  Widget _dayView(int offset) {
    final events = c.remindersForOffset(offset);
    if (events.isEmpty) {
      return const EmptyState(message: 'אין תזכורות ביום זה');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _groupHeader('אירועים ביום זה', const Color(0xFFF59E0B)),
      const SizedBox(height: 6),
      ...events.take(6).map((r) => _row(r, const Color(0xFFF59E0B))),
      if (events.length > 6)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+${events.length - 6} נוספות',
              style: TextStyle(
                  color: JC.textMuted, fontSize: 11, fontFamily: 'Heebo')),
        ),
    ]);
  }

  Widget _groupHeader(String label, Color color) {
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
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(start: BorderSide(color: accent, width: 2)),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 38,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
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
