import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';

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
      }
    } catch (e) {
      if (mounted && _items.isEmpty) setState(() { _error = e.toString(); _loading = false; });
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

    bool undone = false;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(
          content: const Text('התזכורת הוסרה',
              style: TextStyle(fontFamily: 'Heebo', color: JC.textPrimary)),
          backgroundColor: JC.surfaceAlt,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'בטל',
            textColor: JC.blue400,
            onPressed: () {
              undone = true;
              setState(() =>
                  _items.insert(savedIndex.clamp(0, _items.length), item));
              widget.onCountUpdate?.call(_items.length);
            },
          ),
        ))
        .closed
        .then((_) {
          if (!undone) {
            ApiService(widget.settings).deleteReminder(id).catchError((_) {});
          }
        });
  }

  Future<void> _showAddSheet() async {
    final textCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));

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
              const Text('תזכורת חדשה',
                  style: TextStyle(
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
                style:
                    const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: InputDecoration(
                  hintText: 'מה להזכיר לך?',
                  hintStyle: const TextStyle(
                      color: JC.textMuted, fontFamily: 'Heebo'),
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
              // Date/Time picker row
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                    builder: (_, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                            primary: JC.blue500,
                            surface: JC.surfaceAlt),
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
                            primary: JC.blue500,
                            surface: JC.surfaceAlt),
                      ),
                      child: child!,
                    ),
                  );
                  if (time == null) return;
                  setSheet(() {
                    selectedDate = DateTime(
                        date.year, date.month, date.day, time.hour, time.minute);
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: JC.blue500,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () =>
                      _submitAdd(textCtrl.text, selectedDate, ctx),
                  child: const Text('הוסף',
                      style: TextStyle(
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

  Future<void> _submitAdd(
      String text, DateTime dateTime, BuildContext sheetCtx) async {
    final val = text.trim();
    if (val.isEmpty) return;
    Navigator.pop(sheetCtx);
    try {
      final res = await ApiService(widget.settings)
          .addReminder(val, dateTime.toIso8601String());
      final newItem = res['reminder'] as Map<String, dynamic>? ??
          {
            'id': DateTime.now().toString(),
            'text': val,
            'scheduled_time': dateTime.toIso8601String(),
          };
      setState(() => _items.insert(0, newItem));
      widget.onCountUpdate?.call(_items.length);
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('תזכורות',
            style: TextStyle(
                color: JC.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Heebo'),
            textDirection: TextDirection.rtl),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JC.blue400))
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
                        child: _RemSearchBar(controller: _searchCtrl),
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
                                                  Text(
                                                    _formatTime(
                                                        item['scheduled_time']),
                                                    textDirection:
                                                        TextDirection.rtl,
                                                    style: const TextStyle(
                                                        color: JC.textMuted,
                                                        fontSize: 12,
                                                        fontFamily: 'Heebo'),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
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

class _RemSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _RemSearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textDirection: TextDirection.rtl,
      style: const TextStyle(
          color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 14),
      decoration: InputDecoration(
        hintText: 'חיפוש בתזכורות...',
        hintStyle: const TextStyle(
            color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: JC.textMuted, size: 18),
        filled: true,
        fillColor: JC.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: JC.border, width: 0.8)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: JC.border, width: 0.8)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: JC.blue500, width: 1)),
      ),
    );
  }
}
