import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/notification_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';

class RemindersScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const RemindersScreen(
      {super.key, required this.settings, this.onCountUpdate});

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
    _loadCache();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
        // Re-sync all local notifications from server state
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
    (value: null,       label: 'חד-פעמי', icon: Icons.looks_one_rounded),
    (value: 'daily',    label: 'יומי',    icon: Icons.today_rounded),
    (value: 'weekly',   label: 'שבועי',   icon: Icons.date_range_rounded),
    (value: 'monthly',  label: 'חודשי',   icon: Icons.calendar_month_rounded),
  ];

  static const _recurrenceLabel = {
    'daily':   'יומי',
    'weekly':  'שבועי',
    'monthly': 'חודשי',
  };

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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(isEdit ? 'עריכת תזכורת' : 'תזכורת חדשה',
                  style: const TextStyle(
                      color: JC.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo'),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                textDirection: TextDirection.rtl,
                autofocus: true,
                style: const TextStyle(
                    color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  hintText: 'מה להזכיר לך?',
                  hintStyle:
                      const TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
                  filled: true,
                  fillColor: JC.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: JC.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: JC.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: JC.blue500)),
                ),
              ),
              const SizedBox(height: 10),

              // ── Date/Time picker ─────────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                    builder: (_, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                            primary: JC.blue500, surface: JC.surfaceAlt),
                      ),
                      child: child!,
                    ),
                  );
                  if (date == null) return;
                  final time = await showTimePicker(
                    context: ctx,
                    initialTime: TimeOfDay.fromDateTime(selectedDate),
                    builder: (_, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: JC.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: JC.border),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: JC.blue400, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _formatTime(selectedDate.toIso8601String()),
                        style: const TextStyle(
                            color: JC.textSecondary,
                            fontFamily: 'Heebo',
                            fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ── Recurrence selector ──────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Text('חזרתיות',
                    style: const TextStyle(
                        color: JC.textMuted,
                        fontSize: 12,
                        fontFamily: 'Heebo')),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _recurrenceOptions.map((opt) {
                  final active = selectedRecurrence == opt.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () =>
                          setSheet(() => selectedRecurrence = opt.value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
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
                                  color: active
                                      ? JC.blue400
                                      : JC.textSecondary,
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

              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () => _submitReminder(
                      textCtrl.text, selectedDate, ctx,
                      existing: existing,
                      recurrence: selectedRecurrence),
                  child: Text(isEdit ? 'שמור' : 'הוסף',
                      style: const TextStyle(
                          fontFamily: 'Heebo',
                          fontWeight: FontWeight.w600)),
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
        // Only schedule local notification for non-recurring (OS handles once)
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

    // Add new reminder
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showReminderSheet(),
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
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
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final item = _filtered[i];
                                  return AnimatedListItem(
                                    index: i,
                                    child: Dismissible(
                                      key: ValueKey(item['id']),
                                      direction: DismissDirection.endToStart,
                                      background: _remDismissBg(),
                                      onDismissed: (_) => _onDismissed(item),
                                      child: GestureDetector(
                                        onTap: () =>
                                            _showReminderSheet(existing: item),
                                        child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: JC.surfaceAlt,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                              color: JC.border, width: 0.8),
                                        ),
                                        child: Row(
                                          textDirection: TextDirection.rtl,
                                          children: [
                                            Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: JC.blue500
                                                    .withOpacity(0.15),
                                              ),
                                              child: const Icon(
                                                  Icons.access_time_rounded,
                                                  color: JC.blue400,
                                                  size: 20),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    item['text']?.toString() ??
                                                        '',
                                                    textDirection:
                                                        TextDirection.rtl,
                                                    style: const TextStyle(
                                                        color: JC.textPrimary,
                                                        fontSize: 15,
                                                        fontFamily: 'Heebo'),
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      if (item['recurrence'] != null) ...[
                                                        const Icon(Icons.repeat_rounded,
                                                            size: 11, color: JC.blue400),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          _recurrenceLabel[item['recurrence']] ?? '',
                                                          style: const TextStyle(
                                                              color: JC.blue400,
                                                              fontSize: 11,
                                                              fontFamily: 'Heebo',
                                                              fontWeight: FontWeight.w600),
                                                        ),
                                                        const SizedBox(width: 6),
                                                      ],
                                                      Text(
                                                        _formatTime(item['scheduled_time']),
                                                        textDirection: TextDirection.rtl,
                                                        style: const TextStyle(
                                                            color: JC.textMuted,
                                                            fontSize: 12,
                                                            fontFamily: 'Heebo'),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

Widget _remDismissBg() => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );

