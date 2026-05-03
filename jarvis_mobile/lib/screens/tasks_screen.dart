import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';

class TasksScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const TasksScreen({super.key, required this.settings, this.onCountUpdate});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  bool _showDone = false; // toggle: show completed tasks
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

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('tasks');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
      _updateCount();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateCount() {
    final active = _items.where((i) => i['done'] != true).length;
    widget.onCountUpdate?.call(active);
  }

  /// Sorted: active items first (by due_date asc, then created_at), then done items
  List<Map<String, dynamic>> get _sorted {
    final active = _items.where((i) => i['done'] != true).toList();
    final done   = _items.where((i) => i['done'] == true).toList();
    active.sort((a, b) {
      final aDate = a['due_date'] as String?;
      final bDate = b['due_date'] as String?;
      if (aDate != null && bDate != null) return aDate.compareTo(bDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? '');
    });
    return _showDone ? [...active, ...done] : active;
  }

  List<Map<String, dynamic>> get _filtered {
    final src = _sorted;
    if (_searchQuery.isEmpty) return src;
    return src
        .where((i) => (i['content']?.toString() ?? '')
            .toLowerCase()
            .contains(_searchQuery))
        .toList();
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService(widget.settings).getTasks();
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        _updateCount();
        CacheService.saveList('tasks', items);
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

  Future<void> _toggleDone(Map<String, dynamic> item) async {
    HapticFeedback.selectionClick();
    final id      = item['id'].toString();
    final newDone = item['done'] != true;
    setState(() => item['done'] = newDone);
    _updateCount();
    try {
      await ApiService(widget.settings).updateTask(id, done: newDone);
      CacheService.saveList('tasks', _items);
    } catch (_) {
      // revert on error
      setState(() => item['done'] = !newDone);
      _updateCount();
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id         = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));
    _updateCount();

    showDeleteSnackbar(
      context,
      message: 'המשימה הוסרה',
      onUndo: () {
        setState(() =>
            _items.insert(savedIndex.clamp(0, _items.length), item));
        _updateCount();
      },
      onClosed: (wasUndone) {
        if (!wasUndone) {
          ApiService(widget.settings).deleteTask(id).catchError((_) {});
        }
      },
    );
  }

  Future<void> _showAddSheet() async {
    final ctrl    = TextEditingController();
    DateTime? dueDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('משימה חדשה',
                  style: TextStyle(color: JC.textPrimary, fontSize: 16,
                      fontWeight: FontWeight.w600, fontFamily: 'Heebo'),
                  textDirection: TextDirection.rtl),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textDirection: TextDirection.rtl,
                autofocus: true,
                style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
                decoration: _fieldDecoration('תיאור המשימה...'),
                onSubmitted: (_) => _submitAdd(ctrl.text, dueDate, ctx),
              ),
              const SizedBox(height: 10),
              // Due date row
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (c, child) => Theme(
                        data: Theme.of(c).copyWith(
                          colorScheme: const ColorScheme.dark(
                              primary: JC.blue500, surface: JC.surface)),
                        child: child!),
                  );
                  if (picked != null) setSheet(() => dueDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: JC.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: dueDate != null ? JC.blue500 : JC.border,
                        width: dueDate != null ? 1.2 : 0.8),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 16,
                          color: dueDate != null ? JC.blue400 : JC.textMuted),
                      const SizedBox(width: 8),
                      Text(
                        dueDate == null
                            ? 'תאריך יעד (אופציונלי)'
                            : '${dueDate!.day.toString().padLeft(2, '0')}/'
                              '${dueDate!.month.toString().padLeft(2, '0')}/'
                              '${dueDate!.year}',
                        style: TextStyle(
                            color: dueDate != null ? JC.textPrimary : JC.textMuted,
                            fontFamily: 'Heebo', fontSize: 14),
                      ),
                      if (dueDate != null) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setSheet(() => dueDate = null),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: JC.textMuted),
                        ),
                      ],
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
                  onPressed: () => _submitAdd(ctrl.text, dueDate, ctx),
                  child: const Text('הוסף',
                      style: TextStyle(fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAdd(String text, DateTime? dueDate, BuildContext sheetCtx) async {
    final val = text.trim();
    if (val.isEmpty) return;
    Navigator.pop(sheetCtx);
    try {
      final res = await ApiService(widget.settings).addTask(val);
      Map<String, dynamic> newItem = res['task'] as Map<String, dynamic>? ?? {
        'id': DateTime.now().toString(),
        'content': val,
        'done': false,
        'created_at': DateTime.now().toIso8601String(),
      };
      if (dueDate != null) {
        final isoDate = '${dueDate.toIso8601String().substring(0, 10)}T00:00:00.000Z';
        newItem = Map.from(newItem)..['due_date'] = isoDate;
        ApiService(widget.settings).updateTask(
            newItem['id'].toString(), dueDate: isoDate).catchError((_) {});
      }
      setState(() => _items.insert(0, newItem));
      _updateCount();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('שגיאה בהוספה', style: TextStyle(fontFamily: 'Heebo'))));
      }
    }
  }

  String _formatDue(dynamic iso) {
    if (iso == null) return '';
    try {
      final dt  = DateTime.parse(iso.toString()).toLocal();
      final now = DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final today = DateTime(now.year, now.month, now.day);
      if (day == today) return 'היום';
      if (day == today.add(const Duration(days: 1))) return 'מחר';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  bool _isOverdue(Map<String, dynamic> item) {
    if (item['done'] == true) return false;
    final iso = item['due_date'];
    if (iso == null) return false;
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      return dt.isBefore(DateTime.now());
    } catch (_) { return false; }
  }

  @override
  Widget build(BuildContext context) {
    final doneCount = _items.where((i) => i['done'] == true).length;

    return Scaffold(
      backgroundColor: JC.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const LoadingSkeleton(itemCount: 6)
          : _error != null
              ? EmptyState(icon: Icons.error_outline_rounded,
                  title: 'שגיאת טעינה', subtitle: _error!)
              : Column(
                  children: [
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: JarvisSearchBar(
                            controller: _searchCtrl, hint: 'חיפוש במשימות...'),
                      ),
                    if (doneCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _showDone = !_showDone),
                            child: Text(
                              _showDone
                                  ? 'הסתר בוצעו'
                                  : 'הצג בוצעו ($doneCount)',
                              style: const TextStyle(
                                  color: JC.blue400,
                                  fontFamily: 'Heebo',
                                  fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.check_circle_outline_rounded,
                              title: _searchQuery.isEmpty
                                  ? 'אין משימות פתוחות'
                                  : 'לא נמצאו תוצאות',
                              subtitle: _searchQuery.isEmpty
                                  ? 'לחץ + להוספת משימה'
                                  : '')
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surfaceAlt,
                              onRefresh: _fetch,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final item     = _filtered[i];
                                  final isDone   = item['done'] == true;
                                  final overdue  = _isOverdue(item);
                                  final dueLabel = _formatDue(item['due_date']);
                                  return AnimatedListItem(
                                    index: i,
                                    child: Dismissible(
                                      key: ValueKey(item['id']),
                                      direction: DismissDirection.endToStart,
                                      background: _dismissBg(),
                                      onDismissed: (_) => _onDismissed(item),
                                      child: _TaskItem(
                                        item: item,
                                        isDone: isDone,
                                        overdue: overdue,
                                        dueLabel: dueLabel,
                                        onToggle: () => _toggleDone(item),
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

// ─── Task item widget (supports regular + proposal-prompt tasks) ─────────────
const _kPromptSep = '<<<AI_PROMPT>>>';

class _TaskItem extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isDone;
  final bool overdue;
  final String dueLabel;
  final VoidCallback onToggle;

  const _TaskItem({
    required this.item,
    required this.isDone,
    required this.overdue,
    required this.dueLabel,
    required this.onToggle,
  });

  @override
  State<_TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<_TaskItem> {
  bool _promptExpanded = false;

  @override
  Widget build(BuildContext context) {
    final raw     = widget.item['content']?.toString() ?? '';
    final sepIdx  = raw.indexOf('\n$_kPromptSep\n');
    final hasPrompt = sepIdx != -1;
    final title   = hasPrompt ? raw.substring(0, sepIdx) : raw;
    final prompt  = hasPrompt ? raw.substring(sepIdx + '\n$_kPromptSep\n'.length) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: widget.isDone ? JC.surface.withOpacity(0.6) : JC.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPrompt
              ? JC.indigo500.withOpacity(0.5)
              : widget.overdue
                  ? JC.cancelRed.withOpacity(0.4)
                  : JC.border,
          width: hasPrompt ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        children: [
          // ── Main row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                GestureDetector(
                  onTap: widget.onToggle,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      widget.isDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(widget.isDone),
                      color: widget.isDone
                          ? JC.blue400.withOpacity(0.6)
                          : JC.blue500,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        title,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: widget.isDone ? JC.textMuted : JC.textPrimary,
                          fontSize: 15,
                          fontFamily: 'Heebo',
                          decoration: widget.isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (widget.dueLabel.isNotEmpty)
                        Text(
                          widget.dueLabel,
                          style: TextStyle(
                            color: widget.overdue ? JC.cancelRed : JC.textMuted,
                            fontSize: 11,
                            fontFamily: 'Heebo',
                            fontWeight: widget.overdue ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasPrompt) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _promptExpanded = !_promptExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: JC.indigo500.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: JC.indigo500.withOpacity(0.4), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🤖', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 3),
                          Text(
                            _promptExpanded ? 'סגור' : 'פרומפט',
                            style: const TextStyle(
                              color: JC.indigo300,
                              fontSize: 11,
                              fontFamily: 'Heebo',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Icon(
                            _promptExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: JC.indigo300,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Expanded prompt section ────────────────────────────────────
          if (hasPrompt && _promptExpanded)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF080F1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: JC.indigo500.withOpacity(0.25), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        const Text(
                          'פרומפט AI לפיתוח',
                          style: TextStyle(
                            color: JC.indigo300,
                            fontFamily: 'Heebo',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: prompt));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF0F1929),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                content: const Text('הפרומפט הועתק ✓',
                                    style: TextStyle(
                                        color: Color(0xFFF1F5F9),
                                        fontFamily: 'Heebo',
                                        fontSize: 13)),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2E4A),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded,
                                    color: JC.textMuted, size: 12),
                                SizedBox(width: 4),
                                Text('העתק',
                                    style: TextStyle(
                                        color: JC.textMuted,
                                        fontFamily: 'Heebo',
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Divider
                  Container(height: 0.5, color: const Color(0xFF1A2E4A)),
                  // Prompt text
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      prompt,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontFamily: 'Heebo',
                        fontSize: 13,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _fieldDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo'),
      filled: true,
      fillColor: JC.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JC.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JC.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JC.blue500)),
    );

Widget _dismissBg() => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );

