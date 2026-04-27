import 'package:flutter/material.dart';
import '../main.dart' show JC;
import '../app_settings.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../transitions/slide_fade_route.dart';
import '../widgets/animated_list_item.dart';
import '../widgets/delete_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/jarvis_search_bar.dart';
import '../widgets/loading_skeleton.dart';

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
      if (mounted && _items.isEmpty) {
        setState(() {
          _error = ApiService.friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _onDismissed(Map<String, dynamic> item) {
    final id = item['id'].toString();
    final savedIndex = _items.indexOf(item);
    setState(() => _items.remove(item));
    widget.onCountUpdate?.call(_items.length);

    showDeleteSnackbar(
      context,
      message: 'ההערה נמחקה',
      onUndo: () {
        setState(() =>
            _items.insert(savedIndex.clamp(0, _items.length), item));
        widget.onCountUpdate?.call(_items.length);
      },
      onClosed: (wasUndone) {
        if (!wasUndone) {
          ApiService(widget.settings).deleteNote(id).catchError((_) {});
        }
      },
    );
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      SlideFadeRoute<Map<String, dynamic>>(
        page: NoteEditScreen(
          settings: widget.settings,
          existing: existing,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (existing == null) {
        _items.insert(0, result);
      } else {
        existing['title']   = result['title'];
        existing['content'] = result['content'];
        if (result['updated_at'] != null) {
          existing['updated_at'] = result['updated_at'];
        }
      }
    });
    widget.onCountUpdate?.call(_items.length);
    CacheService.saveList('notes', _items);
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
        onPressed: () => _openEditor(),
        backgroundColor: JC.blue500,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const LoadingSkeleton(itemCount: 5, itemHeight: 76)
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
                            hint: 'חיפוש בהערות...'),
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
                                        onTap: () => _openEditor(existing: item),
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

/// Full-screen note editor. Pops with the saved/updated note Map, or `null`
/// if nothing was changed (existing) or content is empty (new).
class NoteEditScreen extends StatefulWidget {
  final AppSettings settings;
  final Map<String, dynamic>? existing;

  const NoteEditScreen({super.key, required this.settings, this.existing});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final String _initialTitle;
  late final String _initialContent;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initialTitle   = widget.existing?['title']?.toString() ?? '';
    _initialContent = widget.existing?['content']?.toString() ?? '';
    _titleCtrl   = TextEditingController(text: _initialTitle);
    _contentCtrl = TextEditingController(text: _initialContent);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  bool get _isDirty {
    return _titleCtrl.text   != _initialTitle ||
           _contentCtrl.text != _initialContent;
  }

  /// Save current values. Pops the screen with the result, or with `null`
  /// if there's nothing to save.
  Future<void> _saveAndPop() async {
    if (_saving) return;
    final title   = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    // Empty new note → just pop without saving.
    if (widget.existing == null && content.isEmpty) {
      Navigator.pop(context);
      return;
    }
    // Unchanged existing → pop without round-tripping the API.
    if (widget.existing != null && !_isDirty) {
      Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ApiService(widget.settings);
      final res = widget.existing == null
          ? await api.addNote(content, title: title)
          : await api.updateNote(widget.existing!['id'].toString(),
              title: title, content: content);
      final saved = (res['note'] as Map<String, dynamic>?) ??
          {
            'id': widget.existing?['id'] ?? DateTime.now().toString(),
            'title': title,
            'content': content,
            'created_at': widget.existing?['created_at'] ??
                DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          };
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('שגיאה בשמירה',
              style: TextStyle(fontFamily: 'Heebo'))));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_isDirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JC.surfaceAlt,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('יציאה ללא שמירה?',
            style: TextStyle(color: JC.textPrimary, fontFamily: 'Heebo'),
            textDirection: TextDirection.rtl),
        content: const Text('יש שינויים שלא נשמרו. לצאת בכל זאת?',
            style: TextStyle(color: JC.textSecondary, fontFamily: 'Heebo'),
            textDirection: TextDirection.rtl),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('המשך עריכה',
                style: TextStyle(color: JC.blue400, fontFamily: 'Heebo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('צא',
                style: TextStyle(color: JC.cancelRed, fontFamily: 'Heebo')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Try to autosave first; if there are no changes, that just pops.
        // If saving fails, give the user a chance to discard.
        final title   = _titleCtrl.text.trim();
        final content = _contentCtrl.text.trim();
        final isNewEmpty = widget.existing == null && content.isEmpty;
        if (isNewEmpty || !_isDirty) {
          if (context.mounted) Navigator.pop(context);
          return;
        }
        // Auto-save on back.
        await _saveAndPop();
        // _saveAndPop already pops on success. If it failed, _saving was
        // reset and we stay; user can retry or use the discard dialog.
        if (mounted && !_saving) {
          // Reached only when _saveAndPop failed and didn't pop.
          final shouldLeave = await _confirmDiscard();
          if (shouldLeave && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: JC.bg,
        appBar: AppBar(
          backgroundColor: JC.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: JC.textPrimary),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            widget.existing == null ? 'הערה חדשה' : 'עריכת הערה',
            style: const TextStyle(
              color: JC.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Heebo',
            ),
          ),
          centerTitle: true,
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: JC.blue400),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check_rounded, color: JC.blue400),
                tooltip: 'שמור',
                onPressed: _saveAndPop,
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleCtrl,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    color: JC.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Heebo',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'כותרת (אופציונלי)',
                    hintStyle: TextStyle(
                        color: JC.textMuted,
                        fontFamily: 'Heebo',
                        fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                  ),
                ),
                const Divider(color: JC.border, height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: TextField(
                    controller: _contentCtrl,
                    textDirection: TextDirection.rtl,
                    autofocus: widget.existing == null,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      color: JC.textPrimary,
                      fontSize: 15,
                      height: 1.6,
                      fontFamily: 'Heebo',
                    ),
                    decoration: const InputDecoration(
                      hintText: 'כתוב כאן את ההערה...',
                      hintStyle: TextStyle(
                          color: JC.textMuted, fontFamily: 'Heebo'),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
