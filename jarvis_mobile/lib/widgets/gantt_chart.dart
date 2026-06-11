import 'package:flutter/material.dart';
import '../main.dart' show JC;

// ─── Simple date-range helper ───────────────────────────────────────────────

class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange({required this.start, required this.end});
  int get days => end.difference(start).inDays + 1;
}

// ─── Color bag passed into the painter ──────────────────────────────────────

class _GanttColors {
  final Color bg;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color todayLine;
  final Color critical;
  final Color high;
  final Color medium;
  final Color low;
  final Color milestone;
  final Color divider;

  const _GanttColors({
    required this.bg,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.todayLine,
    required this.critical,
    required this.high,
    required this.medium,
    required this.low,
    required this.milestone,
    required this.divider,
  });
}

// ─── GanttChart widget ───────────────────────────────────────────────────────

class GanttChart extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> milestones;
  final Map<String, dynamic> project;

  const GanttChart({
    super.key,
    required this.tasks,
    required this.milestones,
    required this.project,
  });

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  double _scrollOffset = 0;

  static const double _rowHeight = 44.0;
  static const double _headerHeight = 40.0;
  static const double _labelWidth = 140.0;
  static const double _dayWidth = 28.0;
  static const double _monthHeaderHeight = 20.0;

  @override
  void initState() {
    super.initState();
    _hScroll.addListener(() {
      setState(() => _scrollOffset = _hScroll.offset);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  void _scrollToToday() {
    final range = _computeRange();
    final daysSinceStart = DateTime.now().difference(range.start).inDays;
    final targetX = (_labelWidth + daysSinceStart * _dayWidth - MediaQuery.of(context).size.width / 2)
        .clamp(0.0, double.infinity);
    if (_hScroll.hasClients) {
      _hScroll.animateTo(
        targetX,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      );
    }
  }

  List<Map<String, dynamic>> get _allItems => [
        ...widget.tasks,
        ...widget.milestones,
      ];

  DateRange _computeRange() {
    DateTime? earliest;
    DateTime? latest;

    final projStart = _parseDate(widget.project['start_date']);
    final projEnd = _parseDate(widget.project['due_date']);

    for (final t in _allItems) {
      final s = _parseDate(t['task_start_date'] ?? t['start_date']);
      final e = _parseDate(t['due_date']);
      if (s != null && (earliest == null || s.isBefore(earliest))) earliest = s;
      if (e != null && (latest == null || e.isAfter(latest))) latest = e;
    }

    earliest = earliest ?? projStart ?? DateTime.now().subtract(const Duration(days: 7));
    latest = latest ?? projEnd ?? DateTime.now().add(const Duration(days: 30));

    return DateRange(
      start: earliest.subtract(const Duration(days: 7)),
      end: latest.add(const Duration(days: 7)),
    );
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String _priorityLabel(String? p) {
    switch (p) {
      case 'critical':
        return 'קריטי';
      case 'high':
        return 'גבוה';
      case 'medium':
        return 'בינוני';
      default:
        return 'נמוך';
    }
  }

  String _formatDate(dynamic v) {
    final d = _parseDate(v);
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  void _handleTap(
    Offset pos,
    DateRange range,
    List<Map<String, dynamic>> allItems,
    BuildContext context,
  ) {
    final y = pos.dy - _headerHeight - _monthHeaderHeight;
    if (y < 0) return;
    final rowIdx = (y / _rowHeight).floor();
    if (rowIdx < 0 || rowIdx >= allItems.length) return;
    final item = allItems[rowIdx];
    _showItemSheet(item, context);
  }

  void _showItemSheet(Map<String, dynamic> item, BuildContext context) {
    final isMilestone = item.containsKey('completed');
    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isMilestone ? Icons.flag_rounded : Icons.task_alt_rounded,
                    color: isMilestone ? JC.indigo500 : JC.blue400,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item['content'] as String? ?? item['title'] as String? ?? '',
                      style: TextStyle(
                        fontFamily: 'Heebo',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: JC.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!isMilestone) ...[
                Text(
                  'עדיפות: ${_priorityLabel(item["priority"] as String?)}',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    color: JC.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (item['task_start_date'] != null || item['start_date'] != null)
                Text(
                  'התחלה: ${_formatDate(item["task_start_date"] ?? item["start_date"])}',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    color: JC.textSecondary,
                  ),
                ),
              if (item['due_date'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  'סיום: ${_formatDate(item["due_date"])}',
                  style: TextStyle(
                    fontFamily: 'Heebo',
                    fontSize: 13,
                    color: JC.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: JC.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    'לחץ ארוך על הפס כדי לערוך תאריכים',
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      fontSize: 11,
                      color: JC.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendItem(Color c, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 8,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Heebo',
            fontSize: 10.5,
            color: JC.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      color: JC.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _legendItem(JC.cancelRed, 'קריטי/גבוה'),
          const SizedBox(width: 12),
          _legendItem(JC.amber400, 'בינוני'),
          const SizedBox(width: 12),
          _legendItem(JC.blue500, 'נמוך'),
          const SizedBox(width: 12),
          _legendItem(JC.indigo500, 'אבן דרך ◆'),
          const Spacer(),
          Row(
            children: [
              Container(width: 2, height: 14, color: JC.blue400),
              const SizedBox(width: 4),
              Text(
                'היום',
                style: TextStyle(
                  fontFamily: 'Heebo',
                  fontSize: 10.5,
                  color: JC.blue400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _computeRange();
    final allItems = _allItems;
    final totalWidth = _labelWidth + range.days * _dayWidth;
    final totalHeight =
        _headerHeight + _monthHeaderHeight + allItems.length * _rowHeight + 20;

    return Scaffold(
      backgroundColor: JC.bg,
      body: allItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timeline_rounded, size: 48, color: JC.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'אין משימות עם תאריכים',
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      color: JC.textMuted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'הוסף תאריכי התחלה וסיום למשימות כדי לראות את הגאנט',
                    style: TextStyle(
                      fontFamily: 'Heebo',
                      color: JC.textMuted,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildLegend(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _vScroll,
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: totalWidth,
                        height: totalHeight,
                        child: GestureDetector(
                          onTapUp: (details) => _handleTap(
                            details.localPosition,
                            range,
                            allItems,
                            context,
                          ),
                          child: CustomPaint(
                            painter: GanttPainter(
                              tasks: widget.tasks,
                              milestones: widget.milestones,
                              range: range,
                              scrollOffset: _scrollOffset,
                              rowHeight: _rowHeight,
                              headerHeight: _headerHeight,
                              monthHeaderHeight: _monthHeaderHeight,
                              labelWidth: _labelWidth,
                              dayWidth: _dayWidth,
                              today: DateTime.now(),
                              colors: _GanttColors(
                                bg: JC.bg,
                                surface: JC.surface,
                                textPrimary: JC.textPrimary,
                                textSecondary: JC.textSecondary,
                                textMuted: JC.textMuted,
                                todayLine: JC.blue400,
                                critical: JC.cancelRed,
                                high: JC.cancelRed,
                                medium: JC.amber400,
                                low: JC.blue500,
                                milestone: JC.indigo500,
                                divider: JC.surface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── GanttPainter ────────────────────────────────────────────────────────────

class GanttPainter extends CustomPainter {
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> milestones;
  final DateRange range;
  final double scrollOffset;
  final double rowHeight;
  final double headerHeight;
  final double monthHeaderHeight;
  final double labelWidth;
  final double dayWidth;
  final DateTime today;
  final _GanttColors colors;

  const GanttPainter({
    required this.tasks,
    required this.milestones,
    required this.range,
    required this.scrollOffset,
    required this.rowHeight,
    required this.headerHeight,
    required this.monthHeaderHeight,
    required this.labelWidth,
    required this.dayWidth,
    required this.today,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allItems = [...tasks, ...milestones];

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = colors.bg,
    );

    // Month header (top row)
    _paintMonthHeaders(canvas, size);

    // Day header (second row)
    _paintDayHeaders(canvas, size);

    // Row backgrounds + horizontal dividers
    for (int i = 0; i < allItems.length; i++) {
      final y = headerHeight + monthHeaderHeight + i * rowHeight;
      final rowColor = i.isOdd ? colors.surface : colors.bg;
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, rowHeight),
        Paint()..color = rowColor,
      );
      canvas.drawLine(
        Offset(0, y + rowHeight),
        Offset(size.width, y + rowHeight),
        Paint()
          ..color = colors.divider
          ..strokeWidth = 0.5,
      );
    }

    // Vertical grid lines every 7 days (lightweight)
    final gridPaint = Paint()
      ..color = colors.divider.withOpacity(0.6)
      ..strokeWidth = 0.5;
    for (int d = 0; d < range.days; d++) {
      if (d % 7 == 0) {
        final x = labelWidth + d * dayWidth;
        canvas.drawLine(
          Offset(x, headerHeight + monthHeaderHeight),
          Offset(x, size.height),
          gridPaint,
        );
      }
    }

    // Today vertical line
    final todayX =
        labelWidth + today.difference(range.start).inDays * dayWidth;
    if (todayX >= labelWidth && todayX <= size.width) {
      canvas.drawLine(
        Offset(todayX, 0),
        Offset(todayX, size.height),
        Paint()
          ..color = colors.todayLine
          ..strokeWidth = 2,
      );
    }

    // Task bars and milestones (behind label overlay)
    for (int i = 0; i < allItems.length; i++) {
      final item = allItems[i];
      final isMilestone = item.containsKey('completed');
      final y = headerHeight + monthHeaderHeight + i * rowHeight;

      if (isMilestone) {
        _paintMilestone(canvas, item, y);
      } else {
        _paintTaskBar(canvas, item, y);
      }
    }

    // Label column overlay (semi-opaque background so bars don't bleed into labels)
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        headerHeight + monthHeaderHeight,
        labelWidth,
        allItems.length * rowHeight,
      ),
      Paint()..color = colors.bg.withOpacity(0.92),
    );

    // Label column header background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, labelWidth, headerHeight + monthHeaderHeight),
      Paint()..color = const Color(0xFF0B1422),
    );

    // Re-paint labels on top of the overlay
    for (int i = 0; i < allItems.length; i++) {
      final item = allItems[i];
      final isMilestone = item.containsKey('completed');
      final y = headerHeight + monthHeaderHeight + i * rowHeight;
      _paintLabel(
        canvas,
        item['content'] as String? ?? item['title'] as String? ?? '',
        y,
        isMilestone,
      );
    }
  }

  void _paintMonthHeaders(Canvas canvas, Size size) {
    String? lastMonth;
    double? monthStartX;

    for (int d = 0; d < range.days; d++) {
      final date = range.start.add(Duration(days: d));
      final x = labelWidth + d * dayWidth;
      final month = '${_monthName(date.month)} ${date.year}';
      if (month != lastMonth) {
        if (lastMonth != null && monthStartX != null) {
          _drawMonthLabel(canvas, lastMonth, monthStartX, x);
        }
        lastMonth = month;
        monthStartX = x;
      }
    }
    if (lastMonth != null && monthStartX != null) {
      _drawMonthLabel(
        canvas,
        lastMonth,
        monthStartX,
        labelWidth + range.days * dayWidth,
      );
    }
  }

  void _drawMonthLabel(
    Canvas canvas,
    String label,
    double startX,
    double endX,
  ) {
    canvas.drawRect(
      Rect.fromLTWH(startX, 0, endX - startX, monthHeaderHeight),
      Paint()..color = const Color(0xFF0F1929),
    );
    // Vertical separator
    canvas.drawLine(
      Offset(startX, 0),
      Offset(startX, monthHeaderHeight),
      Paint()
        ..color = const Color(0xFF1E293B)
        ..strokeWidth = 1,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 10.5,
          color: Color(0xFF94A3B8),
          fontFamily: 'Heebo',
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: (endX - startX - 4).clamp(0.0, double.infinity));
    tp.paint(
      canvas,
      Offset(startX + 4, (monthHeaderHeight - tp.height) / 2),
    );
  }

  void _paintDayHeaders(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        monthHeaderHeight,
        size.width,
        headerHeight - monthHeaderHeight,
      ),
      Paint()..color = const Color(0xFF0B1422),
    );

    for (int d = 0; d < range.days; d++) {
      final date = range.start.add(Duration(days: d));
      final x = labelWidth + d * dayWidth;
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isWeekend = date.weekday >= 6;

      if (date.day == 1 || d == 0 || d % 7 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${date.day}',
            style: TextStyle(
              fontSize: 9,
              color: isToday
                  ? colors.todayLine
                  : isWeekend
                      ? colors.textMuted.withOpacity(0.6)
                      : colors.textMuted,
              fontFamily: 'Heebo',
              fontWeight: isToday ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: dayWidth);
        tp.paint(
          canvas,
          Offset(
            x + (dayWidth - tp.width) / 2,
            monthHeaderHeight +
                (headerHeight - monthHeaderHeight - tp.height) / 2,
          ),
        );
      }

      // Today highlight circle
      if (isToday) {
        canvas.drawCircle(
          Offset(
            x + dayWidth / 2,
            monthHeaderHeight + (headerHeight - monthHeaderHeight) / 2,
          ),
          8,
          Paint()..color = colors.todayLine.withOpacity(0.18),
        );
      }
    }
  }

  void _paintTaskBar(Canvas canvas, Map<String, dynamic> task, double rowY) {
    final startDate =
        _parseDate(task['task_start_date']) ??
        _parseDate(task['start_date']) ??
        today;
    final endDate = _parseDate(task['due_date']);
    if (endDate == null) return;

    final startX =
        labelWidth + startDate.difference(range.start).inDays * dayWidth;
    final endX =
        labelWidth + endDate.difference(range.start).inDays * dayWidth + dayWidth;
    final barWidth = (endX - startX).clamp(dayWidth, double.infinity);

    // Skip bars entirely outside viewport
    if (endX < labelWidth || startX > labelWidth + range.days * dayWidth) {
      return;
    }

    final color = _taskColor(task['priority'] as String?);
    final isDone = task['done'] == true;
    final baseColor = isDone ? color.withOpacity(0.4) : color;

    final barRect = Rect.fromLTWH(
      startX,
      rowY + rowHeight * 0.25,
      barWidth,
      rowHeight * 0.5,
    );
    final rrect = RRect.fromRectAndRadius(barRect, const Radius.circular(4));

    // Shadow/glow for non-done tasks
    if (!isDone) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          barRect.inflate(1),
          const Radius.circular(5),
        ),
        Paint()..color = baseColor.withOpacity(0.25),
      );
    }
    canvas.drawRRect(rrect, Paint()..color = baseColor);

    // Strikethrough for done tasks
    if (isDone) {
      canvas.drawLine(
        Offset(startX + 4, rowY + rowHeight / 2),
        Offset(startX + barWidth - 4, rowY + rowHeight / 2),
        Paint()
          ..color = Colors.white.withOpacity(0.5)
          ..strokeWidth = 1.5,
      );
    }

    // Draw text inside bar if wide enough
    if (barWidth > 40) {
      final label = task['content'] as String? ?? '';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withOpacity(0.9),
            fontFamily: 'Heebo',
          ),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (barWidth - 8).clamp(0.0, double.infinity));
      tp.paint(
        canvas,
        Offset(startX + 4, rowY + (rowHeight - tp.height) / 2),
      );
    }
  }

  void _paintMilestone(
    Canvas canvas,
    Map<String, dynamic> milestone,
    double rowY,
  ) {
    final date = _parseDate(milestone['due_date']);
    if (date == null) return;

    final x = labelWidth +
        date.difference(range.start).inDays * dayWidth +
        dayWidth / 2;
    if (x < labelWidth || x > labelWidth + range.days * dayWidth) return;

    final cy = rowY + rowHeight / 2;
    final diamondSize = rowHeight * 0.3;
    final isCompleted = milestone['completed'] == true;
    final color =
        isCompleted ? colors.milestone.withOpacity(0.5) : colors.milestone;

    // Glow
    if (!isCompleted) {
      final glowPath = Path()
        ..moveTo(x, cy - diamondSize - 3)
        ..lineTo(x + diamondSize + 3, cy)
        ..lineTo(x, cy + diamondSize + 3)
        ..lineTo(x - diamondSize - 3, cy)
        ..close();
      canvas.drawPath(glowPath, Paint()..color = color.withOpacity(0.25));
    }

    // Diamond shape
    final path = Path()
      ..moveTo(x, cy - diamondSize)
      ..lineTo(x + diamondSize, cy)
      ..lineTo(x, cy + diamondSize)
      ..lineTo(x - diamondSize, cy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);

    // Checkmark for completed
    if (isCompleted) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    double rowY,
    bool isMilestone,
  ) {
    final color = isMilestone ? colors.milestone : colors.textSecondary;
    final displayText = (isMilestone ? '◆ ' : '') + text;
    final tp = TextPainter(
      text: TextSpan(
        text: displayText,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontFamily: 'Heebo',
        ),
      ),
      textDirection: TextDirection.rtl,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: (labelWidth - 12).clamp(0.0, double.infinity));
    // Paint from the right edge of the label column (RTL)
    tp.paint(
      canvas,
      Offset(
        labelWidth - tp.width - 6,
        rowY + (rowHeight - tp.height) / 2,
      ),
    );
  }

  Color _taskColor(String? priority) {
    switch (priority) {
      case 'critical':
      case 'high':
        return colors.critical;
      case 'medium':
        return colors.medium;
      default:
        return colors.low;
    }
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  String _monthName(int month) {
    const names = [
      'ינו', 'פבר', 'מרץ', 'אפר', 'מאי', 'יוני',
      'יולי', 'אוג', 'ספט', 'אוק', 'נוב', 'דצמ',
    ];
    return names[(month - 1).clamp(0, 11)];
  }

  @override
  bool shouldRepaint(GanttPainter old) =>
      old.tasks != tasks ||
      old.milestones != milestones ||
      old.scrollOffset != scrollOffset;
}
