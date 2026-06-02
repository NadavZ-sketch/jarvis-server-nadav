import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../services/api_service.dart';
import 'home_controller.dart';
import 'home_helpers.dart';

void showAddTaskDialog(BuildContext context, HomeController c) {
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF0B1422),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('משימה חדשה',
            style: TextStyle(
                color: JC.textPrimary,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
          decoration: _inputDecoration('תאר את המשימה...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ביטול',
                style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
          ),
          ElevatedButton(
            style: _primaryBtn(JC.blue500),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context);
              c.addTask(text);
            },
            child: const Text('הוסף',
                style:
                    TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );
}

void showAddReminderDialog(BuildContext context, HomeController c) {
  final textController = TextEditingController();
  DateTime reminderTime = DateTime.now()
      .add(const Duration(hours: 1))
      .copyWith(second: 0, microsecond: 0);

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDState) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0B1422),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('תזכורת חדשה',
              style: TextStyle(
                  color: JC.textPrimary,
                  fontFamily: 'Heebo',
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                autofocus: true,
                style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: _inputDecoration('תאר את התזכורת...'),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: reminderTime,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date == null || !ctx.mounted) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(reminderTime),
                  );
                  if (time == null) return;
                  setDState(() {
                    reminderTime = DateTime(date.year, date.month, date.day,
                        time.hour, time.minute);
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: JC.surfaceSunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: JC.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.schedule_rounded, color: JC.blue400, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${reminderTime.day}/${reminderTime.month}  '
                      '${reminderTime.hour.toString().padLeft(2, '0')}:'
                      '${reminderTime.minute.toString().padLeft(2, '0')}',
                      style:
                          TextStyle(color: JC.textSecondary, fontFamily: 'Heebo'),
                    ),
                    const Spacer(),
                    Text('שנה',
                        style: TextStyle(
                            color: JC.blue400,
                            fontSize: 12,
                            fontFamily: 'Heebo')),
                  ]),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('ביטול',
                  style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo')),
            ),
            ElevatedButton(
              style: _primaryBtn(const Color(0xFF22C55E)),
              onPressed: () {
                final text = textController.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                c.addReminder(text, reminderTime);
              },
              child: const Text('הוסף',
                  style: TextStyle(
                      fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}

void showBuildDaySheet(BuildContext context, HomeController c) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0B1422),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BuildDaySheet(controller: c),
  );
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: JC.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: JC.blue500),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

ButtonStyle _primaryBtn(Color bg) => ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

/// Interactive "Build my day": a structured day plan (load gauge + actionable
/// items from /day-plan) plus an engaging briefing (motivation, did-you-know,
/// notable dates) generated by the LLM.
class _BuildDaySheet extends StatefulWidget {
  final HomeController controller;
  const _BuildDaySheet({required this.controller});

  @override
  State<_BuildDaySheet> createState() => _BuildDaySheetState();
}

class _BuildDaySheetState extends State<_BuildDaySheet> {
  HomeController get c => widget.controller;

  bool _planLoading = true;
  Map<String, dynamic>? _plan;
  String? _planError;

  bool _briefLoading = true;
  String _brief = '';

  final Set<String> _completing = {};

  @override
  void initState() {
    super.initState();
    _fetchPlan();
    _fetchBrief();
  }

  Future<void> _fetchPlan() async {
    setState(() {
      _planLoading = true;
      _planError = null;
    });
    try {
      final plan = await c.api.getDayPlan();
      if (mounted) setState(() => _plan = plan);
    } catch (e) {
      if (mounted) setState(() => _planError = ApiService.friendlyError(e));
    }
    if (mounted) setState(() => _planLoading = false);
  }

  Future<void> _fetchBrief() async {
    setState(() => _briefLoading = true);
    try {
      final r = await c.api.askJarvis(
        'פתח לי את היום: שורה אחת מוטיבציה אישית, פסקה קצרה "הידעת?" עם עובדה מעניינת, '
        'וציון תאריכים או אירועים מיוחדים של היום אם יש. בעברית, קצר וקולח, בלי כותרות מודגשות.',
        c.settings,
      );
      if (mounted) setState(() => _brief = r['answer'] as String? ?? '');
    } catch (_) {
      if (mounted) setState(() => _brief = '');
    }
    if (mounted) setState(() => _briefLoading = false);
  }

  Future<void> _completeItem(Map<String, dynamic> item) async {
    if ((item['type'] ?? '') != 'task') return;
    final sourceId = item['sourceId']?.toString();
    if (sourceId == null) return;
    setState(() => _completing.add(sourceId));
    try {
      await c.api.updateTask(sourceId, done: true);
      c.showSnack('משימה הושלמה ✓');
      await _fetchPlan();
      // ignore: unawaited_futures
      c.refresh();
    } catch (e) {
      c.showSnack(ApiService.friendlyError(e));
    }
    if (mounted) setState(() => _completing.remove(sourceId));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B1422),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JC.track,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                child: Row(children: [
                  const Text('🗓', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('בנה את היום',
                        style: TextStyle(
                          color: JC.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Heebo',
                        )),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: JC.textMuted),
                    onPressed: () {
                      _fetchPlan();
                      _fetchBrief();
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: JC.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              Divider(color: JC.border),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    _briefSection(),
                    const SizedBox(height: 16),
                    _planSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _briefSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [JC.track, JC.surface],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('☀️', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text('פתיחת היום',
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Heebo')),
          ]),
          const SizedBox(height: 8),
          if (_briefLoading)
            const CardSkeleton(lines: 3)
          else
            Text(_brief.isEmpty ? 'לא ניתן לטעון כרגע' : _brief,
                style: TextStyle(
                  color: JC.textSecondary,
                  fontSize: 13,
                  height: 1.6,
                  fontFamily: 'Heebo',
                )),
        ],
      ),
    );
  }

  Widget _planSection() {
    if (_planLoading) return const CardSkeleton(lines: 4);
    if (_planError != null) {
      return InlineError(message: _planError!, onRetry: _fetchPlan);
    }
    final plan = _plan;
    if (plan == null) return const EmptyState(message: 'אין תוכנית יום כרגע');

    final load = plan['load'] as Map<String, dynamic>?;
    final quadrants = plan['quadrants'] as Map<String, dynamic>?;
    final now = ((quadrants?['now'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final next = ((quadrants?['plan'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final narrative = (plan['narrative'] as String?)?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (load != null) _loadGauge(load),
        if (narrative.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(narrative,
              style: TextStyle(
                color: JC.textSecondary,
                fontSize: 12.5,
                height: 1.55,
                fontFamily: 'Heebo',
              )),
        ],
        if (now.isNotEmpty) ...[
          const SizedBox(height: 14),
          _quadHeader('עכשיו', const Color(0xFFEF4444)),
          ...now.map(_itemRow),
        ],
        if (next.isNotEmpty) ...[
          const SizedBox(height: 14),
          _quadHeader('לתכנן', const Color(0xFF3B82F6)),
          ...next.map(_itemRow),
        ],
        if (now.isEmpty && next.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: EmptyState(message: 'אין משימות לתכנון — נצל את הזמן 🎉'),
          ),
      ],
    );
  }

  Widget _loadGauge(Map<String, dynamic> load) {
    final status = (load['status'] ?? '').toString();
    final ratio = (load['ratio'] as num?)?.toDouble() ?? 0.0;
    final color = _statusColor(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('עומס היום: ${_statusLabel(status)}',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Heebo')),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(height: 6, color: JC.track),
            FractionallySizedBox(
              widthFactor: (ratio > 1 ? 1.0 : ratio).clamp(0.0, 1.0),
              child: Container(height: 6, color: color),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _quadHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration:
                BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: 'Heebo')),
      ]),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? '—';
    final isTask = (item['type'] ?? '') == 'task';
    final priority = item['priority'] as String?;
    final sourceId = item['sourceId']?.toString() ?? '';
    final busy = _completing.contains(sourceId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JC.surfaceSunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        if (isTask)
          GestureDetector(
            onTap: busy ? null : () => _completeItem(item),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: busy ? const Color(0xFF22C55E) : JC.textMuted,
                    width: 1.5),
                color: busy
                    ? const Color(0xFF22C55E).withOpacity(0.15)
                    : Colors.transparent,
              ),
              child: busy
                  ? const Icon(Icons.check_rounded,
                      size: 13, color: Color(0xFF22C55E))
                  : null,
            ),
          )
        else
          Icon(Icons.notifications_active_rounded,
              color: const Color(0xFFF59E0B), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: JC.textPrimary,
                fontSize: 13,
                fontFamily: 'Heebo',
                fontWeight: FontWeight.w600,
              )),
        ),
        if (isTask && priority != null) ...[
          const SizedBox(width: 8),
          PriorityBadge(priority),
        ],
      ]),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'overload':
      case 'overloaded':
      case 'heavy':
        return const Color(0xFFEF4444);
      case 'tight':
      case 'moderate':
        return const Color(0xFFF59E0B);
      case 'empty':
        return JC.textMuted;
      default:
        return const Color(0xFF22C55E);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'overload':
      case 'overloaded':
        return 'עמוס מאוד';
      case 'heavy':
        return 'כבד';
      case 'tight':
        return 'צפוף';
      case 'moderate':
        return 'בינוני';
      case 'ok':
      case 'light':
        return 'קל';
      case 'empty':
        return 'פנוי';
      default:
        return status;
    }
  }
}
