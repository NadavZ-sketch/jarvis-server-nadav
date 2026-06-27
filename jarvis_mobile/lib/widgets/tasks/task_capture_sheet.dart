import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart' show JC;
import '../../screens/tasks/tasks_controller.dart';

/// Phase 5 — NL task capture sheet.
///
/// Shows a large text field that parses the user's input on every keystroke
/// (local regex, instant) and updates coloured token chips showing what was
/// detected: title, date, time, priority, project.  A debounced AI call
/// enriches the parse when the user pauses typing.
class TaskCaptureSheet extends StatefulWidget {
  final TasksController controller;

  const TaskCaptureSheet({super.key, required this.controller});

  @override
  State<TaskCaptureSheet> createState() => _TaskCaptureSheetState();
}

class _TaskCaptureSheetState extends State<TaskCaptureSheet> {
  final _ctrl = TextEditingController();
  Timer? _aiDebounce;
  _NLTokens _tokens = const _NLTokens();
  bool _submitting = false;

  @override
  void dispose() {
    _aiDebounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() => _tokens = _parseLocal(text, widget.controller.projects));
    _aiDebounce?.cancel();
    if (text.trim().length < 4) return;
    _aiDebounce = Timer(const Duration(milliseconds: 700), () => _parseWithAI(text));
  }

  Future<void> _parseWithAI(String text) async {
    try {
      final result = await widget.controller.api.parseTaskNL(text);
      if (!mounted) return;
      setState(() {
        _tokens = _tokens.mergeAI(result);
      });
    } catch (_) {}
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    Navigator.pop(context);
    final t = _tokens;
    String? dueDateIso;
    if (t.date != null) {
      final d = t.date!;
      if (t.time != null) {
        final parts = t.time!.split(':');
        final h = int.tryParse(parts[0]) ?? 9;
        final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        dueDateIso = DateTime(d.year, d.month, d.day, h, m).toUtc().toIso8601String();
      } else {
        dueDateIso = DateTime(d.year, d.month, d.day, 9).toUtc().toIso8601String();
      }
    }
    // Find project ID from name
    String? projectId;
    if (t.project != null) {
      final match = widget.controller.projects.firstWhere(
        (p) => p['name']?.toString() == t.project,
        orElse: () => {},
      );
      projectId = match['id']?.toString();
    }
    final title = t.title.isNotEmpty ? t.title : text;
    final res = await widget.controller.addTask(
      title,
      priority: t.priority ?? 'medium',
      projectId: projectId,
      dueDate: dueDateIso != null ? DateTime.parse(dueDateIso) : null,
    );
    if (res != null) widget.controller.showSnack('משימה נוספה ✓');
  }

  @override
  Widget build(BuildContext context) {
    final empty = _ctrl.text.trim().isEmpty;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: JC.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // NL input field
            Container(
              decoration: BoxDecoration(
                color: JC.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: empty ? JC.border : JC.blue500,
                  width: empty ? 0.8 : 1.5,
                ),
                boxShadow: empty
                    ? null
                    : [BoxShadow(color: JC.blue500.withValues(alpha: 0.15), blurRadius: 8)],
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textDirection: TextDirection.rtl,
                maxLines: null,
                style: TextStyle(
                    color: JC.textPrimary, fontSize: 16, fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  hintText: 'מה צריך לעשות? (לדוגמה: פגישה מחר ב-10 עם דן)',
                  hintStyle: TextStyle(
                      color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 12),

            // Live token chips
            _TokenRow(tokens: _tokens, rawText: _ctrl.text),
            const SizedBox(height: 14),

            // Submit
            SizedBox(
              width: double.infinity,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: empty
                      ? null
                      : LinearGradient(
                          colors: [JC.blue500, JC.indigo500],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                  color: empty ? JC.surface : null,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                      color: empty ? JC.border : Colors.transparent, width: 0.8),
                ),
                child: TextButton(
                  onPressed: empty ? null : _submit,
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13)),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'הוסף משימה ↑',
                    style: TextStyle(
                      color: empty ? JC.textMuted : Colors.white,
                      fontFamily: 'Heebo',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Token row ────────────────────────────────────────────────────────────────

class _TokenRow extends StatelessWidget {
  final _NLTokens tokens;
  final String rawText;

  const _TokenRow({required this.tokens, required this.rawText});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (tokens.title.isNotEmpty) {
      chips.add(_chip('📝 ${tokens.title}', JC.blue400));
    }
    if (tokens.date != null) {
      final d = tokens.date!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      String label;
      if (d == today) label = 'היום';
      else if (d == today.add(const Duration(days: 1))) label = 'מחר';
      else label = '${d.day}/${d.month}';
      chips.add(_chip('📅 $label', const Color(0xFF4ade80)));
    }
    if (tokens.time != null) {
      chips.add(_chip('⏰ ${tokens.time}', const Color(0xFF60c8ff)));
    }
    if (tokens.priority == 'high') {
      chips.add(_chip('🔴 דחוף', JC.cancelRed));
    } else if (tokens.priority == 'low') {
      chips.add(_chip('🟢 נמוך', JC.green500));
    }
    if (tokens.project != null) {
      chips.add(_chip('💼 ${tokens.project}', JC.indigo300));
    }

    if (chips.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: JC.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: JC.border.withValues(alpha: 0.5), width: 0.6),
        ),
        child: Text(
          rawText.isEmpty ? 'מקלד כדי לזהות...' : 'מנתח...',
          style: TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 12),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: JC.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JC.border.withValues(alpha: 0.5), width: 0.6),
      ),
      child: Wrap(spacing: 6, runSpacing: 6, children: chips),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontFamily: 'Heebo',
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Token model ──────────────────────────────────────────────────────────────

class _NLTokens {
  final String title;
  final DateTime? date;
  final String? time;
  final String? priority;
  final String? project;

  const _NLTokens({
    this.title = '',
    this.date,
    this.time,
    this.priority,
    this.project,
  });

  _NLTokens mergeAI(Map<String, dynamic> ai) {
    DateTime? aiDate;
    final aiDateStr = ai['date']?.toString();
    if (aiDateStr != null && aiDateStr != 'null') {
      try { aiDate = DateTime.parse(aiDateStr).toLocal(); } catch (_) {}
    }
    return _NLTokens(
      title: (ai['title'] as String?)?.trim().isNotEmpty == true
          ? (ai['title'] as String).trim()
          : title,
      date: aiDate ?? date,
      time: (ai['time'] as String?)?.isNotEmpty == true ? ai['time'] as String : time,
      priority: (ai['priority'] as String?)?.isNotEmpty == true ? ai['priority'] as String : priority,
      project: (ai['project'] as String?)?.isNotEmpty == true ? ai['project'] as String : project,
    );
  }
}

// ─── Local NL parser (regex, instant) ────────────────────────────────────────

_NLTokens _parseLocal(String text, List<Map<String, dynamic>> projects) {
  var title = text;
  DateTime? date;
  String? time;
  String? priority;
  String? project;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Priority
  if (RegExp(r'דחוף|חשוב|מיידי|!!|urgent|asap', caseSensitive: false).hasMatch(text)) {
    priority = 'high';
    title = title.replaceAll(RegExp(r'דחוף|חשוב|מיידי|!!|urgent|asap', caseSensitive: false), '');
  } else if (RegExp(r'נמוך|low|אין דחיפות', caseSensitive: false).hasMatch(text)) {
    priority = 'low';
    title = title.replaceAll(RegExp(r'נמוך|low|אין דחיפות', caseSensitive: false), '');
  }

  // Date keywords (order matters: longer matches first)
  if (text.contains('שבוע הבא') || text.contains('בשבוע הבא')) {
    date = today.add(const Duration(days: 7));
    title = title.replaceAll(RegExp(r'שבוע הבא|בשבוע הבא'), '');
  } else if (text.contains('מחר')) {
    date = today.add(const Duration(days: 1));
    title = title.replaceAll('מחר', '');
  } else if (text.contains('היום')) {
    date = today;
    title = title.replaceAll('היום', '');
  } else if (text.contains('שישי') || text.contains('יום שישי')) {
    int diff = 5 - now.weekday;
    if (diff <= 0) diff += 7;
    date = today.add(Duration(days: diff));
    title = title.replaceAll(RegExp(r'יום שישי|שישי'), '');
  } else if (text.contains('שבת')) {
    int diff = 6 - now.weekday;
    if (diff <= 0) diff += 7;
    date = today.add(Duration(days: diff));
    title = title.replaceAll('שבת', '');
  }

  // Time: "ב-10", "ב-10:30", "בשעה 10", "10:00"
  final timeRe = RegExp(r'ב-?(\d{1,2})(?::(\d{2}))?|בשעה\s+(\d{1,2})(?::(\d{2}))?');
  final tm = timeRe.firstMatch(text);
  if (tm != null) {
    final h = int.tryParse(tm.group(1) ?? tm.group(3) ?? '') ?? 0;
    final m = int.tryParse(tm.group(2) ?? tm.group(4) ?? '') ?? 0;
    time = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    title = title.replaceAll(tm.group(0)!, '');
  }

  // Project name match
  for (final p in projects) {
    final name = p['name']?.toString() ?? '';
    if (name.length >= 2 && text.contains(name)) {
      project = name;
      title = title.replaceAll(name, '');
      break;
    }
  }

  // Clean up title
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

  return _NLTokens(
    title: title,
    date: date,
    time: time,
    priority: priority,
    project: project,
  );
}
