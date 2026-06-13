import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';

class RemindersScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;
  // Incremented by ProductivityScreen to trigger the add-reminder sheet
  final ValueListenable<int>? addTrigger;

  const RemindersScreen({
    super.key,
    required this.settings,
    this.onCountUpdate,
    this.addTrigger,
  });

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    widget.addTrigger?.addListener(_onAddTrigger);
    _loadCache();
    _fetch();
  }

  @override
  void dispose() {
    widget.addTrigger?.removeListener(_onAddTrigger);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onAddTrigger() => _showReminderSheet();

  List<Map<String, dynamic>> get _filtered => _searchQuery.isEmpty
      ? _items
      : _items
          .where((i) => (i['text']?.toString() ?? '')
              .toLowerCase()
              .contains(_searchQuery))
          .toList();

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('reminders');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
      widget.onCountUpdate?.call(cached.length);
    }
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService(widget.settings).getReminders();
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        widget.onCountUpdate?.call(items.length);
        CacheService.saveList('reminders', items);
        NotificationService.rescheduleAll(items).catchError((_) {});
      }
    } catch (e) {
      if (mounted && _items.isEmpty) {
        setState(() {
          _error = ApiService.friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  static const _recurrenceOptions = [
    (value: null,      label: 'חד-פעמי', icon: Icons.looks_one_rounded),
    (value: 'daily',   label: 'יומי',    icon: Icons.today_rounded),
    (value: 'weekly',  label: 'שבועי',   icon: Icons.date_range_rounded),
    (value: 'monthly', label: 'חודשי',   icon: Icons.calendar_month_rounded),
  ];

  // Groups: overdue, today, tomorrow, week, later
  _ReminderGroup _classify(Map<String, dynamic> item) {
    final raw = item['scheduled_time'];
    if (raw == null) return _ReminderGroup.later;
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final itemDay = DateTime(dt.year, dt.month, dt.day);
      if (itemDay.isBefore(today)) return _ReminderGroup.overdue;
      if (itemDay == today) return _ReminderGroup.today;
      if (itemDay == today.add(const Duration(days: 1))) return _ReminderGroup.tomorrow;
      if (itemDay.isBefore(today.add(const Duration(days: 8)))) return _ReminderGroup.week;
      return _ReminderGroup.later;
    } catch (_) {
      return _ReminderGroup.later;
    }
  }

  String _formatTime(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final itemDay = DateTime(dt.year, dt.month, dt.day);
      final hhmm =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (itemDay == today) return 'היום ב-$hhmm';
      if (itemDay == tomorrow) return 'מחר ב-$hhmm';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ב-$hhmm';
    } catch (_) {
      return iso.toString();
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));
    widget.onCountUpdate?.call(_items.length);

    showDeleteSnackbar(
      context,
      message: 'התזכורת הוסרה',
      onUndo: () {
        setState(() =>
            _items.insert(savedIndex.clamp(0, _items.length), item));
        widget.onCountUpdate?.call(_items.length);
      },
      onClosed: (wasUndone) {
        if (!wasUndone) {
          ApiService(widget.settings).deleteReminder(id).catchError((_) {});
          NotificationService.cancel(id).catchError((_) {});
        }
      },
    );
  }

  Future<void> _showReminderSheet({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final textCtrl = TextEditingController(
        text: isEdit ? (existing['text']?.toString() ?? '') : '');
    DateTime selectedDate;
    String? selectedRecurrence =
        isEdit ? (existing['recurrence'] as String?) : null;

    if (isEdit && existing['scheduled_time'] != null) {
      try {
        selectedDate =
            DateTime.parse(existing['scheduled_time'].toString()).toLocal();
      } catch (_) {
        selectedDate = DateTime.now().add(const Duration(hours: 1));
      }
    } else {
      selectedDate = DateTime.now().add(const Duration(hours: 1));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: JC.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(isEdit ? 'עריכת תזכורת' : 'תזכורת חדשה',
                  style: TextStyle(
                      color: JC.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Heebo'),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 14),
              TextField(
                controller: textCtrl,
                textDirection: TextDirection.rtl,
                autofocus: true,
                style: TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'מה להזכיר לך?',
                  hintStyle: TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                  filled: true,
                  fillColor: JC.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: JC.blue500, width: 1.5)),
                ),
              ),
              const SizedBox(height: 10),
              // Date+Time picker as one tap
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    builder: (_, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: ColorScheme.dark(
                            primary: JC.blue500, surface: JC.surfaceAlt),
                      ),
                      child: child!,
                    ),
                  );
                  if (date == null) return;
                  if (!ctx.mounted) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(selectedDate),
                    builder: (_, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: ColorScheme.dark(
                            primary: JC.blue500, surface: JC.surfaceAlt),
                      ),
                      child: child!,
                    ),
                  );
                  if (time == null) return;
                  setSheet(() {
                    selectedDate = DateTime(date.year, date.month, date.day,
                        time.hour, time.minute);
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: JC.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: JC.border),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          color: JC.blue400, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _formatTime(selectedDate.toIso8601String()),
                        style: TextStyle(
                            color: JC.textSecondary,
                            fontFamily: 'Heebo',
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Recurrence selector
              Align(
                alignment: Alignment.centerRight,
                child: Text('חזרתיות',
                    style: TextStyle(
                        color: JC.textMuted,
                        fontSize: 12,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _recurrenceOptions.map((opt) {
                  final active = selectedRecurrence == opt.value;
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: GestureDetector(
                      onTap: () =>
                          setSheet(() => selectedRecurrence = opt.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: active
                              ? JC.blue500.withOpacity(0.2)
                              : JC.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active ? JC.blue400 : JC.border,
                            width: active ? 1.2 : 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(opt.icon,
                                size: 13,
                                color: active ? JC.blue400 : JC.textMuted),
                            const SizedBox(width: 5),
                            Text(opt.label,
                                style: TextStyle(
                                  color: active ? JC.blue400 : JC.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'Heebo',
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                )),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () => _submitReminder(
                      textCtrl.text, selectedDate, ctx,
                      existing: existing,
                      recurrence: selectedRecurrence),
                  child: Text(isEdit ? 'שמור' : 'הוסף',
                      style: const TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReminder(
      String text, DateTime dateTime, BuildContext sheetCtx,
      {Map<String, dynamic>? existing, String? recurrence}) async {
    final val = text.trim();
    if (val.isEmpty) return;
    Navigator.pop(sheetCtx);
    final iso = dateTime.toIso8601String();

    if (existing != null) {
      final id = existing['id'].toString();
      final prevText       = existing['text'];
      final prevTime       = existing['scheduled_time'];
      final prevRecurrence = existing['recurrence'];
      setState(() {
        existing['text']           = val;
        existing['scheduled_time'] = iso;
        existing['recurrence']     = recurrence;
      });
      try {
        await ApiService(widget.settings).updateReminder(id,
            text: val,
            scheduledTime: iso,
            recurrence: recurrence ?? 'none');
        await NotificationService.cancel(id).catchError((_) {});
        if (recurrence == null) {
          await NotificationService.schedule(id, val, dateTime)
              .catchError((_) {});
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            existing['text']           = prevText;
            existing['scheduled_time'] = prevTime;
            existing['recurrence']     = prevRecurrence;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('שגיאה בעדכון',
                  style: TextStyle(fontFamily: 'Heebo'))));
        }
      }
      return;
    }

    try {
      final res = await ApiService(widget.settings)
          .addReminder(val, iso, recurrence: recurrence);
      final newItem = res['reminder'] as Map<String, dynamic>? ??
          {
            'id': DateTime.now().toString(),
            'text': val,
            'scheduled_time': iso,
            if (recurrence != null) 'recurrence': recurrence,
          };
      setState(() => _items.insert(0, newItem));
      widget.onCountUpdate?.call(_items.length);
      final nId = newItem['id']?.toString();
      if (nId != null && recurrence == null) {
        NotificationService.schedule(nId, val, dateTime).catchError((_) {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('שגיאה בהוספה',
                style: TextStyle(fontFamily: 'Heebo'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
      body: _loading
          ? const LoadingSkeleton(itemCount: 6)
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'שגיאת טעינה',
                  subtitle: _error!)
              : Column(
                  children: [
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: JarvisSearchBar(
                            controller: _searchCtrl,
                            hint: 'חיפוש בתזכורות...'),
                      ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: _searchQuery.isEmpty
                                  ? 'אין תזכורות'
                                  : 'לא נמצאו תוצאות',
                              subtitle: _searchQuery.isEmpty
                                  ? 'לחץ + להוספת תזכורת'
                                  : '')
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surfaceAlt,
                              onRefresh: _fetch,
                              child: _buildTimeline(),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTimeline() {
    // Build ordered groups
    final groups = <_ReminderGroup, List<Map<String, dynamic>>>{};
    for (final item in _filtered) {
      final g = _classify(item);
      groups.putIfAbsent(g, () => []).add(item);
    }

    final order = [
      _ReminderGroup.overdue,
      _ReminderGroup.today,
      _ReminderGroup.tomorrow,
      _ReminderGroup.week,
      _ReminderGroup.later,
    ];

    final sections = <Widget>[];
    for (final group in order) {
      final list = groups[group];
      if (list == null || list.isEmpty) continue;
      sections.add(_GroupHeader(group: group));
      for (final item in list) {
        sections.add(
          Dismissible(
            key: ValueKey(item['id']),
            direction: DismissDirection.endToStart,
            background: _dismissBg(),
            onDismissed: (_) => _onDismissed(item),
            child: _ReminderCard(
              item: item,
              group: group,
              formatTime: _formatTime,
              onTap: () => _showReminderSheet(existing: item),
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: sections,
    );
  }
}

// ─── Group enum ───────────────────────────────────────────────────────────────

enum _ReminderGroup { overdue, today, tomorrow, week, later }

// ─── Group header ─────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final _ReminderGroup group;
  const _GroupHeader({required this.group});

  static const _labels = {
    _ReminderGroup.overdue:  ('⚠️ עברו המועד', true),
    _ReminderGroup.today:    ('היום', false),
    _ReminderGroup.tomorrow: ('מחר', false),
    _ReminderGroup.week:     ('השבוע', false),
    _ReminderGroup.later:    ('אחר כך', false),
  };

  @override
  Widget build(BuildContext context) {
    final (label, isUrgent) = _labels[group] ?? ('', false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: isUrgent ? JC.cancelRed : JC.textMuted,
          fontFamily: 'Heebo',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── Reminder card ────────────────────────────────────────────────────────────

class _ReminderCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final _ReminderGroup group;
  final String Function(dynamic) formatTime;
  final VoidCallback onTap;

  static const _recurrenceLabel = {
    'daily':   'יומי',
    'weekly':  'שבועי',
    'monthly': 'חודשי',
  };

  const _ReminderCard({
    required this.item,
    required this.group,
    required this.formatTime,
    required this.onTap,
  });

  Color get _accentColor {
    if (group == _ReminderGroup.overdue) return JC.cancelRed;
    if (group == _ReminderGroup.today) return JC.amber400;
    return JC.blue400;
  }

  @override
  Widget build(BuildContext context) {
    final recurrence = item['recurrence'] as String?;
    final accent = _accentColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: JC.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: group == _ReminderGroup.overdue
                ? JC.cancelRed.withOpacity(0.4)
                : JC.border,
            width: 0.8,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item['text']?.toString() ?? '',
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: JC.textPrimary,
                                fontSize: 15,
                                fontFamily: 'Heebo',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (recurrence != null) ...[
                                  Icon(Icons.repeat_rounded,
                                      size: 11, color: JC.blue400),
                                  const SizedBox(width: 3),
                                  Text(
                                    _recurrenceLabel[recurrence] ?? '',
                                    style: TextStyle(
                                      color: JC.blue400,
                                      fontSize: 11,
                                      fontFamily: 'Heebo',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Icon(Icons.access_time_rounded,
                                    size: 11, color: JC.textMuted),
                                const SizedBox(width: 3),
                                Text(
                                  formatTime(item['scheduled_time']),
                                  style: TextStyle(
                                    color: group == _ReminderGroup.overdue
                                        ? JC.cancelRed
                                        : JC.textMuted,
                                    fontSize: 12,
                                    fontFamily: 'Heebo',
                                    fontWeight: group == _ReminderGroup.overdue
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.chevron_left_rounded,
                          color: JC.textMuted.withOpacity(0.4), size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dismiss background ───────────────────────────────────────────────────────

Widget _dismissBg() => Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 20),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: JC.cancelRed.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );
