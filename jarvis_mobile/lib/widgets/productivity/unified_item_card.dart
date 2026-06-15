import 'package:flutter/material.dart';
import '../../main.dart' show JC;

/// Single card to display both tasks and reminders with a coloured left-side
/// accent bar. Used in the Dashboard and anywhere a unified item view is needed.
class UnifiedItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String itemType; // 'task' | 'reminder'
  final VoidCallback? onComplete;
  final bool isCompleting;

  const UnifiedItemCard({
    super.key,
    required this.item,
    required this.itemType,
    this.onComplete,
    this.isCompleting = false,
  });

  /// Formats an ISO timestamp for display.
  static String formatTime(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      final hhmm =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (day == today) return 'היום $hhmm';
      if (day == today.subtract(const Duration(days: 1))) return 'אתמול';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  bool get _isOverdue => item['section'] == 'overdue';

  Color get _accentColor {
    if (_isOverdue) return JC.cancelRed;
    if (itemType == 'reminder') return JC.amber400;
    return switch (item['priority']?.toString()) {
      'high' => JC.cancelRed,
      'low' => JC.green500,
      _ => JC.blue400,
    };
  }

  String get _title =>
      item['title']?.toString() ??
      item['content']?.toString() ??
      item['text']?.toString() ??
      '';

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        formatTime(item['time'] ?? item['scheduled_time'] ?? item['due_date']);
    final canComplete = itemType == 'task' && onComplete != null;
    final accent = _accentColor;

    Widget card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JC.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isOverdue ? JC.cancelRed.withOpacity(0.25) : JC.border,
          width: 0.8,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent bar on the right side (RTL start)
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _title,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: JC.textPrimary,
                        fontSize: 14,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (timeLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          color: _isOverdue ? JC.cancelRed : JC.textMuted,
                          fontSize: 11,
                          fontFamily: 'Heebo',
                          fontWeight: _isOverdue
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: Center(
                child: canComplete
                    ? GestureDetector(
                        onTap: isCompleting ? null : onComplete,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: isCompleting
                              ? CircularProgressIndicator(
                                  strokeWidth: 2.2, color: JC.green500)
                              : Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  color: accent,
                                  size: 20,
                                ),
                        ),
                      )
                    : Icon(Icons.notifications_outlined,
                        color: JC.amber400, size: 18),
              ),
            ),
          ],
        ),
      ),
    );

    if (!canComplete) return card;

    return Dismissible(
      key: ValueKey('uic_${item['id']}'),
      direction: DismissDirection.startToEnd,
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsetsDirectional.only(start: 20),
        decoration: BoxDecoration(
          color: JC.green500.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: JC.green500.withOpacity(0.3), width: 0.8),
        ),
        child: Icon(Icons.check_circle_rounded,
            color: JC.green500, size: 22),
      ),
      onDismissed: (_) => onComplete?.call(),
      child: card,
    );
  }
}
