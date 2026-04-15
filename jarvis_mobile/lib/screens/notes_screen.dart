import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/empty_state.dart';

class NotesScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<int>? onCountUpdate;

  const NotesScreen({super.key, required this.settings, this.onCountUpdate});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
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
      : _items.where((i) {
          final title = (i['title']?.toString() ?? '').toLowerCase();
          final content = (i['content']?.toString() ?? '').toLowerCase();
          return title.contains(_searchQuery) || content.contains(_searchQuery);
        }).toList();

  Future<void> _loadCache() async {
    final cached = await CacheService.loadList('notes');
    if (cached != null && mounted && _items.isEmpty) {
      setState(() { _items = cached; _loading = false; });
      widget.onCountUpdate?.call(cached.length);
    }
  }

  Future<void> _fetch() async {
    if (_items.isEmpty) setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService(widget.settings).getNotes();
      if (mounted) {
        setState(() { _items = items; _loading = false; });
        widget.onCountUpdate?.call(items.length);
        CacheService.saveList('notes', items);
      }
    } catch (e) {
      if (mounted && _items.isEmpty) setState(() { _error = e.toString(); _loading = false; });
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
          content: const Text('ההערה נמחקה',
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
              setState(() => _items.insert(savedIndex.clamp(0, _items.length), item));
              widget.onCountUpdate?.call(_items.length);
            },
          ),
        ))
        .closed
        .then((_) {
          if (!undone) {
            ApiService(widget.settings).deleteNote(id).catchError((_) {});
          }
        });
  }

  Future<void> _showAddSheet() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('הערה חדשה',
                style: TextStyle(
                    color: JC.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Heebo'),
                textDirection: TextDirection.rtl),
            const SizedBox(height: 12),
            TextField(
              controller: titleCtrl,
              textDirection: TextDirection.rtl,
              autofocus: true,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
              decoration: _inputDeco('כותרת (אופציונלי)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: contentCtrl,
              textDirection: TextDirection.rtl,
              maxLines: 3,
              style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
              decoration: _inputDeco('תוכן ההערה...'),
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
                    _submitAdd(titleCtrl.text, contentCtrl.text, ctx),
                child: const Text('שמור',
                    style: TextStyle(
                        fontFamily: 'Heebo', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
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

  Future<void> _submitAdd(
      String title, String content, BuildContext sheetCtx) async {
    final val = content.trim();
    if (val.isEmpty) return;
    Navigator.pop(sheetCtx);
    try {
      final res = await ApiService(widget.settings)
          .addNote(val, title: title.trim());
      final newItem = res['note'] as Map<String, dynamic>? ??
          {
            'id': DateTime.now().toString(),
            'title': title.trim(),
            'content': val,
            'created_at': DateTime.now().toIso8601String(),
          };
      setState(() => _items.insert(0, newItem));
      widget.onCountUpdate?.call(_items.length);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('שגיאה בשמירה',
                style: TextStyle(fontFamily: 'Heebo'))));
      }
    }
  }

  void _showNoteDetail(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JC.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if ((item['title']?.toString() ?? '').isNotEmpty) ...[
              Text(item['title']!,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                      color: JC.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Heebo')),
              const SizedBox(height: 8),
            ],
            Text(item['content']?.toString() ?? '',
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                    color: JC.textSecondary,
                    fontSize: 15,
                    height: 1.6,
                    fontFamily: 'Heebo')),
          ],
        ),
      ),
    );
  }

  String _preview(Map<String, dynamic> item) {
    final content = item['content']?.toString() ?? '';
    return content.length > 80 ? '${content.substring(0, 80)}...' : content;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JC.bg,
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
                        child: _NoteSearchBar(controller: _searchCtrl),
                      ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(
                              icon: Icons.notes_rounded,
                              title: _searchQuery.isEmpty
                                  ? 'אין הערות'
                                  : 'לא נמצאו הערות',
                              subtitle: _searchQuery.isEmpty
                                  ? 'לחץ + ליצירת הערה חדשה'
                                  : '')
                          : RefreshIndicator(
                              color: JC.blue400,
                              backgroundColor: JC.surfaceAlt,
                              onRefresh: _fetch,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                itemCount: _filtered.length,
                                itemBuilder: (ctx, i) {
                                  final item = _filtered[i];
                                  final title =
                                      item['title']?.toString() ?? '';
                                  return AnimatedListItem(
                                    index: i,
                                    child: Dismissible(
                                      key: ValueKey(item['id']),
                                      direction: DismissDirection.endToStart,
                                      background: _noteDismissBg(),
                                      onDismissed: (_) => _onDismissed(item),
                                      child: GestureDetector(
                                        onTap: () => _showNoteDetail(item),
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                              bottom: 10),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: JC.surfaceAlt,
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            border: Border.all(
                                                color: JC.border, width: 0.8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              if (title.isNotEmpty) ...[
                                                Text(
                                                  title,
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: const TextStyle(
                                                    color: JC.textPrimary,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'Heebo',
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                              ],
                                              Text(
                                                _preview(item),
                                                textDirection:
                                                    TextDirection.rtl,
                                                style: TextStyle(
                                                  color: title.isNotEmpty
                                                      ? JC.textMuted
                                                      : JC.textSecondary,
                                                  fontSize: title.isNotEmpty
                                                      ? 13
                                                      : 15,
                                                  fontFamily: 'Heebo',
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

Widget _noteDismissBg() => Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: JC.cancelRed.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline_rounded, color: JC.cancelRed),
    );

class _NoteSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _NoteSearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textDirection: TextDirection.rtl,
      style: const TextStyle(color: JC.textPrimary, fontFamily: 'Heebo', fontSize: 14),
      decoration: InputDecoration(
        hintText: 'חיפוש בהערות...',
        hintStyle: const TextStyle(color: JC.textMuted, fontFamily: 'Heebo', fontSize: 14),
        prefixIcon: const Icon(Icons.search_rounded, color: JC.textMuted, size: 18),
        filled: true,
        fillColor: JC.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
